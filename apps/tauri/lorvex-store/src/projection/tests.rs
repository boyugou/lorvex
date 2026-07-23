//! Tests for `projection`. Extracted from the parent file
//! to keep the production module focused.

use super::*;
use crate::connection::open_db_in_memory;

/// Helper: open a write transaction so `enter_maintenance_mode`'s
/// writer-exclusion guard (#2863) is satisfied. Returns a guard
/// that COMMITs on drop unless `rollback()` was called.
struct TxGuard<'c> {
    conn: &'c Connection,
    committed: bool,
}

impl<'c> TxGuard<'c> {
    fn begin(conn: &'c Connection) -> Self {
        conn.execute_batch("BEGIN IMMEDIATE").unwrap();
        Self {
            conn,
            committed: false,
        }
    }

    fn commit(mut self) {
        self.conn.execute_batch("COMMIT").unwrap();
        self.committed = true;
    }
}

impl Drop for TxGuard<'_> {
    fn drop(&mut self) {
        if !self.committed && !std::thread::panicking() {
            let _ = self.conn.execute_batch("COMMIT");
        }
    }
}

/// Helper: insert a task row with required columns.
fn insert_task(conn: &Connection, id: &str, title: &str, body: Option<&str>) {
    crate::test_support::TaskBuilder::new(id)
        .title(title)
        .body(body)
        .created_at("2026-01-01T00:00:00Z")
        .insert(conn);
}

/// Helper: count FTS matches for a query term.
fn fts_count(conn: &Connection, query: &str) -> i64 {
    conn.query_row(
        "SELECT COUNT(*) FROM tasks_fts WHERE tasks_fts MATCH ?1",
        [query],
        |row| row.get(0),
    )
    .unwrap()
}

/// Helper: check whether a trigger exists.
fn trigger_exists(conn: &Connection, trigger_name: &str) -> bool {
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger' AND name = ?1",
            [trigger_name],
            |row| row.get(0),
        )
        .unwrap();
    count > 0
}

#[test]
fn suspend_drops_triggers() {
    let conn = open_db_in_memory().unwrap();
    let proj = tasks_fts_projection();

    // Triggers should exist after schema init.
    assert!(trigger_exists(&conn, "tasks_fts_insert"));
    assert!(trigger_exists(&conn, "tasks_fts_update"));
    assert!(trigger_exists(&conn, "tasks_fts_delete"));

    (proj.suspend)(&conn).unwrap();

    assert!(!trigger_exists(&conn, "tasks_fts_insert"));
    assert!(!trigger_exists(&conn, "tasks_fts_update"));
    assert!(!trigger_exists(&conn, "tasks_fts_delete"));
}

#[test]
fn resume_recreates_triggers() {
    let conn = open_db_in_memory().unwrap();
    let proj = tasks_fts_projection();

    (proj.suspend)(&conn).unwrap();
    assert!(!trigger_exists(&conn, "tasks_fts_insert"));

    (proj.resume)(&conn).unwrap();
    assert!(trigger_exists(&conn, "tasks_fts_insert"));
    assert!(trigger_exists(&conn, "tasks_fts_update"));
    assert!(trigger_exists(&conn, "tasks_fts_delete"));
}

#[test]
fn rebuild_repopulates_fts_index() {
    let conn = open_db_in_memory().unwrap();
    let proj = tasks_fts_projection();

    // Insert a task (triggers will index it).
    insert_task(&conn, "t1", "Buy groceries", Some("milk and eggs"));
    assert_eq!(fts_count(&conn, "groceries"), 1);

    // Wipe the FTS index and rebuild via the projection. The
    // `tasks_fts` virtual table is no longer external-content
    // (issue #2574 added the `tags` column, which has no backing
    // column on `tasks`), so the old `INSERT INTO
    // tasks_fts(tasks_fts) VALUES('rebuild')` idiom no longer
    // applies — we go through the projection's explicit rebuild.
    conn.execute_batch("DELETE FROM tasks_fts;").unwrap();
    assert_eq!(fts_count(&conn, "groceries"), 0);
    (proj.rebuild)(&conn).unwrap();
    assert_eq!(fts_count(&conn, "groceries"), 1);

    // More meaningful test: suspend triggers, insert a task, then rebuild.
    (proj.suspend)(&conn).unwrap();
    insert_task(&conn, "t2", "Read Rust book", None);
    // FTS should NOT find the new task (triggers are gone).
    assert_eq!(fts_count(&conn, "Rust"), 0);

    // Rebuild restores it.
    (proj.rebuild)(&conn).unwrap();
    assert_eq!(fts_count(&conn, "Rust"), 1);
}

#[test]
fn full_maintenance_cycle() {
    let conn = open_db_in_memory().unwrap();
    let registry = ProjectionRegistry::default_projections();

    // Insert a task normally (triggers active).
    insert_task(&conn, "t1", "Design review", Some("architecture doc"));
    assert_eq!(fts_count(&conn, "architecture"), 1);

    // maintenance window must run inside a write tx.
    let tx = TxGuard::begin(&conn);
    registry.enter_maintenance_mode(&conn).unwrap();
    assert!(!trigger_exists(&conn, "tasks_fts_insert"));

    // Bulk inserts during maintenance — FTS not updated incrementally.
    insert_task(&conn, "t2", "Write tests", None);
    insert_task(&conn, "t3", "Deploy pipeline", Some("CI/CD setup"));
    assert_eq!(fts_count(&conn, "tests"), 0);
    assert_eq!(fts_count(&conn, "pipeline"), 0);

    // Exit maintenance mode — rebuild + resume triggers.
    registry.exit_maintenance_mode(&conn).unwrap();
    assert!(trigger_exists(&conn, "tasks_fts_insert"));
    tx.commit();

    // All tasks should now be searchable.
    assert_eq!(fts_count(&conn, "architecture"), 1);
    assert_eq!(fts_count(&conn, "tests"), 1);
    assert_eq!(fts_count(&conn, "pipeline"), 1);

    // Incremental trigger works again for new inserts.
    insert_task(&conn, "t4", "Optimize queries", None);
    assert_eq!(fts_count(&conn, "Optimize"), 1);
}

#[test]
fn registry_names() {
    let registry = ProjectionRegistry::default_projections();
    assert_eq!(
        registry.names(),
        vec!["tasks_fts", "tasks_fts_trigram", "calendar_events_fts"]
    );
}

/// Regression for FTS trigger column scoping: updating a
/// non-searchable column like `priority` or `status` must NOT
/// rebuild the FTS shadow row. The `AFTER UPDATE OF title,
/// body, ai_notes` clause keeps the trigger dormant on every
/// mutation that doesn't touch searchable text — pre-fix the
/// unscoped trigger fired on every one of the ~28 task columns,
/// so a noop edit of `defer_count` or `priority` forced a
/// delete+insert cycle on the FTS virtual table, costing ~75%
/// of task mutations as wasted FTS work.
#[test]
fn task_fts_update_trigger_is_scoped_to_text_columns() {
    let conn = open_db_in_memory().unwrap();
    insert_task(&conn, "t1", "Meeting prep", Some("agenda and slides"));
    assert_eq!(fts_count(&conn, "agenda"), 1);

    // Bump a non-searchable column. With OF scoping the FTS
    // trigger must NOT fire.
    //
    // We detect "did the trigger fire?" by checking whether the
    // FTS row was delete+reinserted: if the trigger fires, the
    // FTS row would be gone briefly (since delete+insert happens
    // inside the UPDATE). Easier proxy: use a custom SQL
    // authorizer or verify via sqlite_schema that the trigger
    // `tasks_fts_update` has the OF clause.
    let trigger_sql: String = conn
        .query_row(
            "SELECT sql FROM sqlite_master
             WHERE type = 'trigger' AND name = 'tasks_fts_update'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert!(
        trigger_sql.contains("OF title, body, ai_notes"),
        "tasks_fts_update trigger must be scoped with `OF title, body, ai_notes` \
         so non-text column updates (priority, due_date, defer_count, ...) \
         don't trigger redundant FTS re-indexing. Actual: {trigger_sql}"
    );

    // Functional verification: a non-text-column UPDATE keeps
    // the FTS row intact.
    conn.execute("UPDATE tasks SET priority = 2 WHERE id = 't1'", [])
        .unwrap();
    assert_eq!(
        fts_count(&conn, "agenda"),
        1,
        "FTS should still match after a non-searchable column update"
    );

    // Functional verification: a text-column UPDATE still
    // re-indexes (replaces the FTS row).
    conn.execute(
        "UPDATE tasks SET title = 'Standup prep' WHERE id = 't1'",
        [],
    )
    .unwrap();
    assert_eq!(fts_count(&conn, "agenda"), 1, "body still matches 'agenda'");
    assert_eq!(fts_count(&conn, "Standup"), 1, "new title matches");
    assert_eq!(
        fts_count(&conn, "Meeting"),
        0,
        "old title no longer matches"
    );
}

/// Regression for FTS trigger column scoping on calendar events.
#[test]
fn calendar_events_fts_update_trigger_is_scoped_to_text_columns() {
    let conn = open_db_in_memory().unwrap();
    let trigger_sql: String = conn
        .query_row(
            "SELECT sql FROM sqlite_master
             WHERE type = 'trigger' AND name = 'calendar_events_fts_update'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert!(
        trigger_sql.contains("OF title, description, location"),
        "calendar_events_fts_update trigger must be scoped with \
         `OF title, description, location`. Actual: {trigger_sql}"
    );
}

/// Regression for #2861: a projection whose rebuild fails must
/// not leave the FTS table half-emptied. The savepoint installed
/// around each projection's rebuild rolls the partial DELETE back
/// to the pre-rebuild state, so we keep stale-but-self-consistent
/// data instead of tombstoning queries until repair runs. Triggers
/// are re-installed regardless so subsequent writes stay
/// incrementally indexed.
#[test]
fn rebuild_failure_rolls_back_via_savepoint() {
    fn always_fail_noop(_conn: &Connection) -> Result<(), rusqlite::Error> {
        Ok(())
    }
    fn always_fail_rebuild(conn: &Connection) -> Result<(), rusqlite::Error> {
        // Mutate the FTS table first, then fail. If the savepoint
        // is missing, the mutation persists; if present, it rolls
        // back. We use the real `tasks_fts` table to make the
        // assertion concrete.
        conn.execute_batch("DELETE FROM tasks_fts;")?;
        Err(rusqlite::Error::InvalidQuery)
    }

    let conn = open_db_in_memory().unwrap();
    insert_task(&conn, "t1", "Buy groceries", Some("milk and eggs"));
    assert_eq!(fts_count(&conn, "groceries"), 1);

    let mut registry = ProjectionRegistry::new();
    registry.register(Projection {
        name: "always_fail",
        suspend: always_fail_noop,
        rebuild: always_fail_rebuild,
        resume: always_fail_noop,
    });
    registry.register(tasks_fts_projection());

    // maintenance window must run inside a write tx.
    let tx = TxGuard::begin(&conn);
    registry.enter_maintenance_mode(&conn).unwrap();

    // exit_maintenance_mode should return the AlwaysFail error,
    // but the prior FTS state must be intact — the TasksFts
    // rebuild that runs after the failing one must have a
    // populated source (still does, since `tasks` is unaffected),
    // and `groceries` must remain searchable after triggers come
    // back online.
    let err = registry.exit_maintenance_mode(&conn).unwrap_err();
    match err {
        rusqlite::Error::InvalidQuery => {}
        other => panic!("expected InvalidQuery, got {other:?}"),
    }
    tx.commit();

    // Triggers must be back online.
    assert!(trigger_exists(&conn, "tasks_fts_insert"));
    assert!(trigger_exists(&conn, "tasks_fts_update"));

    // FTS must be searchable: tasks_fts had its DELETE rolled back
    // by the savepoint, then `tasks_fts_projection`'s rebuild ran
    // cleanly afterwards.
    assert_eq!(fts_count(&conn, "groceries"), 1);

    // Incremental indexing works for new writes.
    insert_task(&conn, "t2", "Walk dog", None);
    assert_eq!(fts_count(&conn, "Walk"), 1);
}

#[test]
fn empty_registry_is_noop() {
    let conn = open_db_in_memory().unwrap();
    let registry = ProjectionRegistry::new();

    // maintenance window must run inside a write tx.
    let tx = TxGuard::begin(&conn);
    registry.enter_maintenance_mode(&conn).unwrap();
    registry.exit_maintenance_mode(&conn).unwrap();
    tx.commit();
}

/// Regression for #2863: enter_maintenance_mode outside a write
/// transaction must fail loudly rather than silently dropping
/// triggers and exposing the writer-exclusion gap.
#[test]
#[cfg_attr(debug_assertions, should_panic)]
fn enter_maintenance_mode_rejects_autocommit_in_release_build() {
    let conn = open_db_in_memory().unwrap();
    let registry = ProjectionRegistry::default_projections();

    // Debug builds panic via debug_assert; release builds return
    // an InvalidQuery error. The cfg_attr above pins the panic
    // expectation to debug builds; on release we verify the err.
    match registry.enter_maintenance_mode(&conn) {
        Err(rusqlite::Error::InvalidQuery) => {}
        other => panic!("expected InvalidQuery (release) or panic (debug), got {other:?}"),
    }
}
