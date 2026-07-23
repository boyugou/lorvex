//! Tests for the low-level lifecycle primitives — `complete_task`,
//! `cancel_task`, `reopen_task`, `cancel_active_reminders`,
//! `uncancel_task_reminders`, `append_to_task_body`, and the dependency
//! edge cleanup that `cancel_task` triggers. The orchestrator-level
//! tests (recurrence spawn, focus rewire, side-effect aggregation) live
//! in sibling modules.

use rusqlite::params;

use super::super::*;
use super::support::{insert_recurring_task, insert_task, test_conn, tid, TEST_VERSION};
use lorvex_store::StoreError;

// -----------------------------------------------------------------------
// body — append_to_task_body
// -----------------------------------------------------------------------

#[test]
fn append_to_task_body_on_empty_body() {
    let conn = test_conn();
    insert_task(&conn, "t1", "open");

    let result = append_to_task_body(
        &conn,
        &tid("t1"),
        "hello world",
        TEST_VERSION,
        "2026-03-26T10:00:00Z",
    )
    .unwrap();
    assert_eq!(result, "hello world");

    let body: Option<String> = conn
        .query_row("SELECT body FROM tasks WHERE id = 't1'", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(body.as_deref(), Some("hello world"));
}

#[test]
fn append_to_task_body_on_existing_body() {
    let conn = test_conn();
    insert_task(&conn, "t1", "open");
    conn.execute(
        "UPDATE tasks SET body = 'existing notes' WHERE id = 't1'",
        [],
    )
    .unwrap();

    let result = append_to_task_body(
        &conn,
        &tid("t1"),
        "new note",
        TEST_VERSION,
        "2026-03-26T10:00:00Z",
    )
    .unwrap();
    assert_eq!(result, "existing notes\n\nnew note");
}

#[test]
fn append_to_task_body_on_null_body() {
    let conn = test_conn();
    insert_task(&conn, "t1", "open");
    // body is NULL by default from insert_task

    let result = append_to_task_body(
        &conn,
        &tid("t1"),
        "first note",
        TEST_VERSION,
        "2026-03-26T10:00:00Z",
    )
    .unwrap();
    assert_eq!(result, "first note");
}

#[test]
fn append_to_task_body_updates_timestamp_and_version() {
    let conn = test_conn();
    insert_task(&conn, "t1", "open");
    let now = "2026-04-01T12:00:00Z";

    append_to_task_body(&conn, &tid("t1"), "note", TEST_VERSION, now).unwrap();

    let (updated, version): (String, String) = conn
        .query_row(
            "SELECT updated_at, version FROM tasks WHERE id = 't1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(updated, now);
    // the version must advance with every body
    // mutation so cross-device LWW reconciliation accepts the
    // change.
    assert_eq!(version, TEST_VERSION);
}

#[test]
fn append_to_task_body_rejects_combined_over_cap() {
    // the store layer must enforce the combined-body
    // cap so both MCP and Tauri callers are protected. Previously
    // the MCP path checked only the NEW chunk — an attacker could
    // grow the body past the cap by repeated appends.
    let conn = test_conn();
    insert_task(&conn, "t1", "open");
    let now = "2026-04-01T12:00:00Z";
    let near_cap = "a".repeat(lorvex_domain::validation::MAX_BODY_LENGTH - 10);
    append_to_task_body(&conn, &tid("t1"), &near_cap, TEST_VERSION, now)
        .expect("first append fits");
    // Second append of 20 chars + 2-char separator pushes past cap.
    let err =
        append_to_task_body(&conn, &tid("t1"), &"b".repeat(20), TEST_VERSION, now).unwrap_err();
    let msg = format!("{err}");
    assert!(
        msg.contains("body"),
        "expected body validation error, got: {msg}"
    );
}

/// a stale-version `append_to_task_body` MUST NOT
/// clobber a row whose stored `version` is already strictly newer.
/// The boundary layer needs a typed `StaleVersion` so it can
/// re-stamp HLC and retry instead of silently losing the appended
/// note.
#[test]
fn append_to_task_body_rejects_stale_version() {
    let conn = test_conn();
    insert_task(&conn, "t1", "open");
    // Land a newer remote-style version on the row first.
    let newer = "9999999999999_0000_ffffffffffffffff";
    conn.execute(
        "UPDATE tasks SET body = 'remote body', version = ?1 WHERE id = 't1'",
        params![newer],
    )
    .unwrap();

    // Local stamp `TEST_VERSION` lexicographically loses to `newer`,
    // so the gate must reject and surface `StaleVersion`.
    let err = append_to_task_body(
        &conn,
        &tid("t1"),
        "stale local note",
        TEST_VERSION,
        "2026-04-01T12:00:00Z",
    )
    .unwrap_err();
    match err {
        StoreError::StaleVersion { entity, id } => {
            assert_eq!(entity, "task");
            assert_eq!(id, "t1");
        }
        other => panic!("expected StoreError::StaleVersion, got {other:?}"),
    }

    // Body and version must remain at the remote-newer state.
    let (body, version): (Option<String>, String) = conn
        .query_row(
            "SELECT body, version FROM tasks WHERE id = 't1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(body.as_deref(), Some("remote body"));
    assert_eq!(version, newer);
}

// -----------------------------------------------------------------------
// dependencies — cancel_task removes incoming/outgoing edges
// -----------------------------------------------------------------------

#[test]
fn cancel_task_removes_from_dependents() {
    let conn = test_conn();
    insert_task(&conn, "t1", "open");
    insert_task(&conn, "t2", "open");
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at)
         VALUES ('t2', 't1', '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();

    let result = cancel_task(
        &conn,
        &tid("t1"),
        "2026-03-26T10:00:00Z",
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
    )
    .unwrap();
    assert!(result.updated);
    assert_eq!(result.affected_dependent_ids, vec!["t2".to_string()]);

    let dep_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_dependencies WHERE depends_on_task_id = 't1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(dep_count, 0);
}

// -----------------------------------------------------------------------
// recurrence — primitive cancel/reopen against recurring rows
// -----------------------------------------------------------------------

#[test]
fn cancel_recurring_task_preserves_recurrence_group_id() {
    let conn = test_conn();
    insert_recurring_task(&conn, "r1", "open", "grp-abc", "2026-03-25");

    cancel_task(
        &conn,
        &tid("r1"),
        "2026-03-26T10:00:00Z",
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
    )
    .unwrap();

    let (status, group): (String, Option<String>) = conn
        .query_row(
            "SELECT status, recurrence_group_id FROM tasks WHERE id = 'r1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(status, "cancelled");
    assert_eq!(group.as_deref(), Some("grp-abc"));
}

#[test]
fn cancel_one_recurring_sibling_does_not_affect_others_in_group() {
    let conn = test_conn();
    insert_recurring_task(&conn, "r1", "open", "grp-shared", "2026-03-25");
    insert_recurring_task(&conn, "r2", "open", "grp-shared", "2026-03-26");
    insert_recurring_task(&conn, "r3", "open", "grp-shared", "2026-03-27");

    cancel_task(
        &conn,
        &tid("r2"),
        "2026-03-26T10:00:00Z",
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
    )
    .unwrap();

    let statuses: Vec<(String, String)> = conn
        .prepare(
            "SELECT id, status FROM tasks WHERE recurrence_group_id = 'grp-shared' ORDER BY id",
        )
        .unwrap()
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap();
    assert_eq!(
        statuses,
        vec![
            ("r1".to_string(), "open".to_string()),
            ("r2".to_string(), "cancelled".to_string()),
            ("r3".to_string(), "open".to_string()),
        ]
    );
}

#[test]
fn cancel_all_in_recurrence_group_leaves_group_id_intact() {
    let conn = test_conn();
    insert_recurring_task(&conn, "r1", "open", "grp-all-cancel", "2026-03-25");
    insert_recurring_task(&conn, "r2", "open", "grp-all-cancel", "2026-03-26");

    cancel_task(
        &conn,
        &tid("r1"),
        "2026-03-26T10:00:00Z",
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
    )
    .unwrap();
    cancel_task(
        &conn,
        &tid("r2"),
        "2026-03-26T10:00:00Z",
        "0000000000000_0000_test0001",
    )
    .unwrap();

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE recurrence_group_id = 'grp-all-cancel'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count, 2, "both cancelled tasks retain their group ID");
}

#[test]
fn cancel_already_cancelled_recurring_task_is_idempotent() {
    let conn = test_conn();
    insert_recurring_task(&conn, "r1", "cancelled", "grp-idem", "2026-03-25");

    let result = cancel_task(
        &conn,
        &tid("r1"),
        "2026-03-26T10:00:00Z",
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
    )
    .unwrap();
    assert!(!result.updated);
}

#[test]
fn reopen_cancelled_recurring_task_preserves_group() {
    let conn = test_conn();
    insert_recurring_task(&conn, "r1", "cancelled", "grp-reopen", "2026-03-25");

    let result = reopen_task(
        &conn,
        &tid("r1"),
        "2026-03-26T10:00:00Z",
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
    )
    .unwrap();
    assert!(result.updated);

    let (status, group): (String, Option<String>) = conn
        .query_row(
            "SELECT status, recurrence_group_id FROM tasks WHERE id = 'r1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(status, "open");
    assert_eq!(group.as_deref(), Some("grp-reopen"));
}

// -----------------------------------------------------------------------
// reminders — cancel_active_reminders / uncancel_task_reminders
// -----------------------------------------------------------------------

#[test]
fn cancel_active_reminders_skips_lww_loser_rows() {
    let conn = test_conn();
    insert_task(&conn, "t1", "open");
    // Two active reminders. The first has a strictly-newer version
    // than the caller's stamp (LWW loser); the second is older.
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES ('r-newer', 't1', '2026-04-01T09:00:00Z', '9999999999999_0000_ffffffffffffffff', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES ('r-older', 't1', '2026-04-02T09:00:00Z', '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();

    let stamp = "0000000000000_0000_aaaa0000aaaa0000";
    let cancelled =
        cancel_active_reminders(&conn, &tid("t1"), "2026-03-26T10:00:00Z", stamp).unwrap();
    // Only the older row's cancel went through.
    assert_eq!(cancelled, vec!["r-older".to_string()]);

    // The newer row is untouched.
    let (cancelled_at, version): (Option<String>, String) = conn
        .query_row(
            "SELECT cancelled_at, version FROM task_reminders WHERE id = 'r-newer'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert!(
        cancelled_at.is_none(),
        "LWW-loser row must not be cancelled"
    );
    assert_eq!(version, "9999999999999_0000_ffffffffffffffff");

    // The older row was cancelled and its version advanced.
    let (cancelled_at, version): (Option<String>, String) = conn
        .query_row(
            "SELECT cancelled_at, version FROM task_reminders WHERE id = 'r-older'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert!(cancelled_at.is_some());
    assert_eq!(version, stamp);
}

/// M1 regression — same shape as
/// `cancel_active_reminders_skips_lww_loser_rows` for the
/// reverse-direction (un-cancel) writer.
#[test]
fn uncancel_task_reminders_skips_lww_loser_rows() {
    let conn = test_conn();
    insert_task(&conn, "t1", "open");
    // Both reminders are cancelled. The first has a newer stored
    // version; the second has an older stored version.
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, cancelled_at, version, created_at)
         VALUES ('r-newer', 't1', '2026-04-01T09:00:00Z', '2026-03-25T12:00:00Z', '9999999999999_0000_ffffffffffffffff', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, cancelled_at, version, created_at)
         VALUES ('r-older', 't1', '2026-04-02T09:00:00Z', '2026-03-25T12:00:00Z', '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();

    let stamp = "0000000000000_0000_aaaa0000aaaa0000";
    let uncancelled = uncancel_task_reminders(&conn, &tid("t1"), stamp).unwrap();
    assert_eq!(uncancelled, vec!["r-older".to_string()]);

    let (cancelled_at_newer, _): (Option<String>, String) = conn
        .query_row(
            "SELECT cancelled_at, version FROM task_reminders WHERE id = 'r-newer'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert!(
        cancelled_at_newer.is_some(),
        "LWW-loser row must keep its cancelled_at"
    );

    let (cancelled_at_older, _): (Option<String>, String) = conn
        .query_row(
            "SELECT cancelled_at, version FROM task_reminders WHERE id = 'r-older'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert!(cancelled_at_older.is_none());
}

#[test]
fn complete_cancels_active_reminders() {
    let conn = test_conn();
    insert_task(&conn, "t1", "open");
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES ('r1', 't1', '2026-04-01T09:00:00Z', '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')",
        [],
    ).unwrap();

    complete_task(
        &conn,
        &tid("t1"),
        "2026-03-26T10:00:00Z",
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
    )
    .unwrap();

    let cancelled: Option<String> = conn
        .query_row(
            "SELECT cancelled_at FROM task_reminders WHERE id = 'r1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert!(cancelled.is_some());
}

#[test]
fn reopen_uncancels_reminders_and_clears_delivery_state() {
    // Seed a task with a reminder, complete it (which cancels the reminder
    // and marks delivery_state), then reopen and verify the reminder
    // comes back pending with no delivery_state row.
    let conn = test_conn();
    insert_task(&conn, "t1", "open");
    // Seed reminder with a strictly-older HLC than the
    // complete/reopen versions below so the M1 LWW gate accepts
    // both writes.
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES ('r1', 't1', '2026-04-01T09:00:00Z', '0000000000000_0000_aaaa0000', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_reminder_delivery_state (reminder_id, delivery_state, updated_at)
         VALUES ('r1', 'delivered', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();

    // Complete the task: cancels the reminder.
    complete_task(
        &conn,
        &tid("t1"),
        "2026-03-26T10:00:00Z",
        "0000000000000_0000_compl0000",
    )
    .unwrap();
    let cancelled_at: Option<String> = conn
        .query_row(
            "SELECT cancelled_at FROM task_reminders WHERE id = 'r1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert!(
        cancelled_at.is_some(),
        "reminder should be cancelled after task completion"
    );

    // Reopen the task.
    let result = reopen_task(
        &conn,
        &tid("t1"),
        "2026-03-27T10:00:00Z",
        "0000000000000_0000_reopen00",
    )
    .unwrap();
    assert!(result.updated);
    assert_eq!(
        result.reopened_reminder_ids,
        vec!["r1".to_string()],
        "reopened reminder id should be returned for sync propagation"
    );

    // Reminder is un-cancelled.
    let (cancelled_at, version): (Option<String>, String) = conn
        .query_row(
            "SELECT cancelled_at, version FROM task_reminders WHERE id = 'r1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert!(
        cancelled_at.is_none(),
        "reminder cancelled_at should be cleared after reopen"
    );
    assert_eq!(
        version, "0000000000000_0000_reopen00",
        "reminder version should be stamped with the reopen version"
    );

    // Delivery state row is cleared so reminder can re-fire.
    let delivery_rows: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_reminder_delivery_state WHERE reminder_id = 'r1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        delivery_rows, 0,
        "delivery_state row must be deleted on reopen so reminder can re-fire"
    );
}

#[test]
fn reopen_leaves_dismissed_reminders_alone() {
    // A dismissed reminder should NOT be resurrected by reopen — the user
    // explicitly acknowledged it.
    let conn = test_conn();
    insert_task(&conn, "t1", "completed");
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, dismissed_at, version, created_at)
         VALUES ('r1', 't1', '2026-04-01T09:00:00Z', '2026-03-25T12:00:00Z', '0000000000000_0000_seed0000', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();

    let result = reopen_task(
        &conn,
        &tid("t1"),
        "2026-03-27T10:00:00Z",
        "0000000000000_0000_reopen00",
    )
    .unwrap();
    assert!(result.updated);
    assert!(
        result.reopened_reminder_ids.is_empty(),
        "dismissed reminders must not be uncancelled on reopen"
    );

    let dismissed_at: Option<String> = conn
        .query_row(
            "SELECT dismissed_at FROM task_reminders WHERE id = 'r1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert!(
        dismissed_at.is_some(),
        "dismissed_at should remain set after reopen"
    );
}

// -----------------------------------------------------------------------
// status — complete_task / cancel_task / reopen_task primitive shapes
// -----------------------------------------------------------------------

#[test]
fn complete_task_sets_status_and_clears_deferral() {
    let conn = test_conn();
    insert_task(&conn, "t1", "open");
    conn.execute(
        "UPDATE tasks SET last_deferred_at = '2026-01-01T00:00:00Z' WHERE id = 't1'",
        [],
    )
    .unwrap();

    let result = complete_task(
        &conn,
        &tid("t1"),
        "2026-03-26T10:00:00Z",
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
    )
    .unwrap();
    assert!(result.updated);

    let (status, deferred): (String, Option<String>) = conn
        .query_row(
            "SELECT status, last_deferred_at FROM tasks WHERE id = 't1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(status, "completed");
    assert!(deferred.is_none());
}

#[test]
fn complete_task_rejects_stale_version() {
    let conn = test_conn();
    insert_task(&conn, "t1", "open");
    // Land a strictly newer remote version on the row.
    let newer = "9999999999999_0000_ffffffffffffffff";
    conn.execute(
        "UPDATE tasks SET version = ?1 WHERE id = 't1'",
        params![newer],
    )
    .unwrap();

    // Local stamp loses lex-compare to `newer`.
    let stale = "0000000000000_0000_a0a0a0a0a0a0a0a0";
    let err = complete_task(&conn, &tid("t1"), "2026-03-26T10:00:00Z", stale).unwrap_err();
    match err {
        StoreError::StaleVersion { entity, id } => {
            assert_eq!(entity, "task");
            assert_eq!(id, "t1");
        }
        other => panic!("expected StaleVersion, got {other:?}"),
    }

    // Row state must be untouched: status still "open", version
    // still the newer remote value.
    let (status, version): (String, String) = conn
        .query_row(
            "SELECT status, version FROM tasks WHERE id = 't1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(status, "open");
    assert_eq!(version, newer);
}

/// H1 regression for the cancel path — same shape as
/// `complete_task_rejects_stale_version`.
#[test]
fn cancel_task_rejects_stale_version() {
    let conn = test_conn();
    insert_task(&conn, "t1", "open");
    let newer = "9999999999999_0000_ffffffffffffffff";
    conn.execute(
        "UPDATE tasks SET version = ?1 WHERE id = 't1'",
        params![newer],
    )
    .unwrap();

    let stale = "0000000000000_0000_a0a0a0a0a0a0a0a0";
    let err = cancel_task(&conn, &tid("t1"), "2026-03-26T10:00:00Z", stale).unwrap_err();
    assert!(matches!(err, StoreError::StaleVersion { .. }));

    let status: String = conn
        .query_row("SELECT status FROM tasks WHERE id = 't1'", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(status, "open");
}

/// H1 regression for the reopen path.
#[test]
fn reopen_task_rejects_stale_version() {
    let conn = test_conn();
    insert_task(&conn, "t1", "completed");
    let newer = "9999999999999_0000_ffffffffffffffff";
    conn.execute(
        "UPDATE tasks SET version = ?1 WHERE id = 't1'",
        params![newer],
    )
    .unwrap();

    let stale = "0000000000000_0000_a0a0a0a0a0a0a0a0";
    let err = reopen_task(&conn, &tid("t1"), "2026-03-26T10:00:00Z", stale).unwrap_err();
    assert!(matches!(err, StoreError::StaleVersion { .. }));

    let status: String = conn
        .query_row("SELECT status FROM tasks WHERE id = 't1'", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(status, "completed");
}

#[test]
fn complete_already_completed_returns_not_updated() {
    let conn = test_conn();
    insert_task(&conn, "t1", "completed");
    let result = complete_task(
        &conn,
        &tid("t1"),
        "2026-03-26T10:00:00Z",
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
    )
    .unwrap();
    assert!(!result.updated);
}

#[test]
fn reopen_task_clears_completion_and_deferral_state() {
    let conn = test_conn();
    insert_task(&conn, "t1", "completed");
    conn.execute(
        "UPDATE tasks SET completed_at = '2026-03-01T00:00:00Z', planned_date = '2026-03-01', \
         last_deferred_at = '2026-02-28T00:00:00Z', defer_count = 2 WHERE id = 't1'",
        [],
    )
    .unwrap();

    let result = reopen_task(
        &conn,
        &tid("t1"),
        "2026-03-26T10:00:00Z",
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
    )
    .unwrap();
    assert!(result.updated);

    let (status, completed_at, planned_date, deferred, defer_count): (
        String, Option<String>, Option<String>, Option<String>, i64,
    ) = conn.query_row(
        "SELECT status, completed_at, planned_date, last_deferred_at, defer_count FROM tasks WHERE id = 't1'",
        [],
        |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?, row.get(4)?)),
    ).unwrap();
    assert_eq!(status, "open");
    assert!(completed_at.is_none());
    assert!(planned_date.is_none());
    assert!(deferred.is_none());
    assert_eq!(defer_count, 0);
}

#[test]
fn reopen_already_open_returns_not_updated() {
    let conn = test_conn();
    insert_task(&conn, "t1", "open");
    let result = reopen_task(
        &conn,
        &tid("t1"),
        "2026-03-26T10:00:00Z",
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
    )
    .unwrap();
    assert!(!result.updated);
}

#[test]
fn reopen_cancelled_task_works() {
    let conn = test_conn();
    insert_task(&conn, "t1", "cancelled");

    let result = reopen_task(
        &conn,
        &tid("t1"),
        "2026-03-26T10:00:00Z",
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
    )
    .unwrap();
    assert!(result.updated);

    let status: String = conn
        .query_row("SELECT status FROM tasks WHERE id = 't1'", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(status, "open");
}
