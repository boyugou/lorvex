//! Unit tests for the FTS mutation helpers (#3281).
//!
//! Two test surfaces:
//!
//! 1. **Canonical SQL shape** — pin the SQL string constants so a
//!    refactor that accidentally drops the FTS5 `'delete'` command
//!    (or types the column list in the wrong order) breaks here
//!    instead of silently leaking stale postings.
//! 2. **Behavioural** — round-trip through an in-memory DB to prove
//!    `*_upsert` truly tombstones-then-inserts (the prior row's
//!    postings disappear, the new row's postings appear).
//!
//! Trigger DDL is exercised by the existing
//! `projection/tests.rs::*_trigger_is_scoped_to_text_columns` and
//! `repositories::task::read::tests::trigram` suites — the
//! production [`projection::tasks_fts_trigram_projection`]
//! call now goes through [`super::tasks_trigram::install_triggers`],
//! so those tests also cover the helper indirectly.

use crate::connection::open_db_in_memory;
use crate::test_support::TaskBuilder;
use rusqlite::Connection;

// ---------------------------------------------------------------------------
// Canonical-SQL pins
// ---------------------------------------------------------------------------

#[test]
fn tasks_trigram_tombstone_sql_is_canonical_delete_command() {
    // The FTS5 `'delete'` command shape is the only way to drop
    // postings on an external-content table without touching the
    // backing row — pin the column ordering and command keyword.
    let sql = super::tasks_trigram::TOMBSTONE_SQL;
    assert!(
        sql.contains("INSERT INTO tasks_fts_trigram"),
        "expected INSERT INTO tasks_fts_trigram, got {sql}"
    );
    assert!(
        sql.contains("(tasks_fts_trigram, rowid, title, body, ai_notes)"),
        "expected canonical column ordering, got {sql}"
    );
    assert!(
        sql.contains("'delete'"),
        "tombstone must use the FTS5 'delete' command, got {sql}"
    );
}

#[test]
fn tasks_trigram_insert_sql_is_bare_insert() {
    let sql = super::tasks_trigram::INSERT_SQL;
    assert!(sql.contains("INSERT INTO tasks_fts_trigram"));
    assert!(
        sql.contains("(rowid, title, body, ai_notes)"),
        "expected bare insert column list, got {sql}"
    );
    assert!(
        !sql.contains("'delete'"),
        "INSERT_SQL must not carry the 'delete' command"
    );
}

#[test]
fn calendar_events_tombstone_sql_is_canonical_delete_command() {
    let sql = super::calendar::TOMBSTONE_SQL;
    assert!(sql.contains("INSERT INTO calendar_events_fts"));
    assert!(
        sql.contains("(calendar_events_fts, rowid, title, description, location)"),
        "expected canonical column ordering, got {sql}"
    );
    assert!(sql.contains("'delete'"));
}

#[test]
fn calendar_events_insert_sql_is_bare_insert() {
    let sql = super::calendar::INSERT_SQL;
    assert!(sql.contains("INSERT INTO calendar_events_fts"));
    assert!(
        sql.contains("(rowid, title, description, location)"),
        "expected bare insert column list, got {sql}"
    );
    assert!(!sql.contains("'delete'"));
}

#[test]
fn calendar_events_optimize_sql_uses_optimize_command() {
    assert!(super::calendar::OPTIMIZE_SQL.contains("'optimize'"));
    assert!(super::calendar::OPTIMIZE_SQL.contains("calendar_events_fts"));
}

// ---------------------------------------------------------------------------
// Behavioural: tasks_fts_trigram_upsert
// ---------------------------------------------------------------------------

fn trigram_match_count(conn: &Connection, query: &str) -> i64 {
    conn.query_row(
        "SELECT COUNT(*) FROM tasks_fts_trigram WHERE tasks_fts_trigram MATCH ?1",
        [query],
        |row| row.get(0),
    )
    .unwrap()
}

fn calendar_match_count(conn: &Connection, query: &str) -> i64 {
    conn.query_row(
        "SELECT COUNT(*) FROM calendar_events_fts WHERE calendar_events_fts MATCH ?1",
        [query],
        |row| row.get(0),
    )
    .unwrap()
}

#[test]
fn tasks_trigram_upsert_is_tombstone_then_insert() {
    let conn = open_db_in_memory().unwrap();

    // Seed a task — the schema's INSERT trigger projects it.
    TaskBuilder::new("t1")
        .title("写一个中文任务说明")
        .body(Some("早上好"))
        .created_at("2026-01-01T00:00:00Z")
        .insert(&conn);

    // Pre-condition: the trigram is searchable.
    assert_eq!(trigram_match_count(&conn, "\"中文任务\""), 1);

    let rowid: i64 = conn
        .query_row("SELECT rowid FROM tasks WHERE id = 't1'", [], |row| {
            row.get(0)
        })
        .unwrap();

    // Drop the schema's UPDATE trigger so the helper's behaviour
    // is observed in isolation — otherwise the trigger would also
    // tombstone+reinsert and we couldn't distinguish what the
    // helper itself did.
    super::tasks_trigram::drop_triggers(&conn).unwrap();
    // We have to re-install the INSERT trigger only? No — for this
    // assertion we simply mutate the postings directly via the
    // helper.

    // Helper flow: tombstone the old postings using the *previous*
    // column values, then insert new postings.
    super::tasks_trigram::tasks_fts_trigram_upsert(
        &conn,
        rowid,
        super::tasks_trigram::TasksTrigramColumns {
            title: Some("写一个中文任务说明"),
            body: Some("早上好"),
            ai_notes: None,
        },
        super::tasks_trigram::TasksTrigramColumns {
            title: Some("English title only"),
            body: Some("plain ascii body"),
            ai_notes: None,
        },
    )
    .unwrap();

    // Old CJK 3-grams must be gone (the tombstone half).
    assert_eq!(
        trigram_match_count(&conn, "\"中文任务\""),
        0,
        "tombstone half should remove old postings"
    );
    // New ascii 3-grams must be present (the insert half).
    assert_eq!(
        trigram_match_count(&conn, "\"plain ascii\""),
        1,
        "insert half should add new postings"
    );
}

#[test]
fn tasks_trigram_delete_removes_postings_only() {
    let conn = open_db_in_memory().unwrap();
    TaskBuilder::new("t1")
        .title("写一个中文任务说明")
        .body(None)
        .created_at("2026-01-01T00:00:00Z")
        .insert(&conn);
    let rowid: i64 = conn
        .query_row("SELECT rowid FROM tasks WHERE id = 't1'", [], |row| {
            row.get(0)
        })
        .unwrap();

    assert_eq!(trigram_match_count(&conn, "\"中文任务\""), 1);

    // Drop triggers so the helper-only effect is observed.
    super::tasks_trigram::drop_triggers(&conn).unwrap();

    super::tasks_trigram::tasks_fts_trigram_delete(
        &conn,
        rowid,
        super::tasks_trigram::TasksTrigramColumns {
            title: Some("写一个中文任务说明"),
            body: None,
            ai_notes: None,
        },
    )
    .unwrap();

    assert_eq!(trigram_match_count(&conn, "\"中文任务\""), 0);

    // Backing row must still exist — the FTS `'delete'` command
    // only touches postings.
    let task_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM tasks WHERE id = 't1'", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(task_count, 1);
}

// ---------------------------------------------------------------------------
// Behavioural: calendar_events_fts_upsert
// ---------------------------------------------------------------------------

/// Insert a minimal `calendar_events` row — enough columns to make
/// the FTS triggers fire. The schema requires more NOT NULL fields
/// than just the FTS columns; this helper fills them with safe
/// defaults that won't disturb the assertions below.
fn insert_calendar_event(
    conn: &Connection,
    id: &str,
    title: &str,
    description: Option<&str>,
    location: Option<&str>,
) {
    conn.execute(
        "INSERT INTO calendar_events (
            id, title, description, location,
            start_date, all_day, event_type, version,
            created_at, updated_at
         ) VALUES (
            ?1, ?2, ?3, ?4,
            '2026-01-01', 1, 'event', 'v1',
            '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
         )",
        rusqlite::params![id, title, description, location],
    )
    .unwrap();
}

#[test]
fn calendar_events_fts_upsert_is_tombstone_then_insert() {
    let conn = open_db_in_memory().unwrap();

    insert_calendar_event(
        &conn,
        "ev1",
        "Architecture review",
        Some("Design discussion for the planning service"),
        Some("Conf room A"),
    );

    assert_eq!(calendar_match_count(&conn, "Architecture"), 1);

    let rowid: i64 = conn
        .query_row(
            "SELECT rowid FROM calendar_events WHERE id = 'ev1'",
            [],
            |row| row.get(0),
        )
        .unwrap();

    // Drop FTS triggers so the helper's behaviour is observed in
    // isolation.
    super::calendar::drop_triggers(&conn).unwrap();

    super::calendar::calendar_events_fts_upsert(
        &conn,
        rowid,
        super::calendar::CalendarEventsColumns {
            title: Some("Architecture review"),
            description: Some("Design discussion for the planning service"),
            location: Some("Conf room A"),
        },
        super::calendar::CalendarEventsColumns {
            title: Some("Sprint planning"),
            description: Some("Backlog grooming"),
            location: Some("Conf room B"),
        },
    )
    .unwrap();

    assert_eq!(
        calendar_match_count(&conn, "Architecture"),
        0,
        "tombstone half should remove old postings"
    );
    assert_eq!(
        calendar_match_count(&conn, "Sprint"),
        1,
        "insert half should add new postings"
    );
}

// ---------------------------------------------------------------------------
// Trigger DDL parity: helper installs the same triggers as the schema
// ---------------------------------------------------------------------------

/// Pre-fix the trigger DDL was duplicated as two byte-for-byte
/// strings — one in `001_schema.sql` (install-time), one in
/// `projection.rs` (post-maintenance re-install). This test pins
/// the post-maintenance path: dropping then re-installing via the
/// helper must restore working triggers (i.e. a subsequent UPDATE
/// on the base table re-projects into the FTS index).
#[test]
fn install_triggers_round_trips_for_tasks_trigram() {
    let conn = open_db_in_memory().unwrap();
    TaskBuilder::new("t1")
        .title("first title")
        .body(None)
        .created_at("2026-01-01T00:00:00Z")
        .insert(&conn);

    super::tasks_trigram::drop_triggers(&conn).unwrap();
    super::tasks_trigram::install_triggers(&conn).unwrap();

    conn.execute(
        "UPDATE tasks SET title = '写一个中文任务说明' WHERE id = 't1'",
        [],
    )
    .unwrap();

    assert_eq!(trigram_match_count(&conn, "\"中文任务\""), 1);
}

#[test]
fn install_triggers_round_trips_for_calendar_events() {
    let conn = open_db_in_memory().unwrap();
    insert_calendar_event(&conn, "ev1", "First title", None, None);

    super::calendar::drop_triggers(&conn).unwrap();
    super::calendar::install_triggers(&conn).unwrap();

    conn.execute(
        "UPDATE calendar_events SET title = 'Sprint planning' WHERE id = 'ev1'",
        [],
    )
    .unwrap();

    assert_eq!(calendar_match_count(&conn, "Sprint"), 1);
}
