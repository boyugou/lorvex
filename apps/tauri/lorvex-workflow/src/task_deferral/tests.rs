use super::*;
use lorvex_store::open_db_in_memory;

fn tid(s: &str) -> TaskId {
    TaskId::from_trusted(s.to_string())
}

/// Stale-version stamp used by the LWW-rejection test cases below.
/// Ordering by lex-compare: `STALE_STAMP < NEWER_STAMP`.
const STALE_STAMP: &str = "1711712640000_0000_test0001";
/// Fresh-version stamp landed on the row before the stale-version
/// rejection assertion.
const NEWER_STAMP: &str = "1711712640000_0009_test0009";

fn test_reminder_version() -> Result<String, StoreError> {
    Ok("1711712640000_0001_reminder".to_string())
}

fn setup() -> Connection {
    let conn = open_db_in_memory().unwrap();
    // the LWW-gated UPDATE compares version
    // strings lexicographically. Seed with a low-watermark that
    // dominates every realistic HLC stamp the tests supply.
    conn.execute(
        "INSERT INTO tasks (id, title, status, priority, defer_count, version, created_at, updated_at) \
         VALUES ('t1', 'Test Task', 'open', 3, 0, '0000000000000_0000_0000000000000000', '2026-03-27T00:00:00Z', '2026-03-27T00:00:00Z')",
        [],
    ).unwrap();
    conn
}

fn seed_reminder(
    conn: &Connection,
    reminder_id: &str,
    reminder_at: &str,
    dismissed_at: Option<&str>,
    cancelled_at: Option<&str>,
) {
    conn.execute(
        "INSERT INTO task_reminders \
         (id, task_id, reminder_at, dismissed_at, cancelled_at, version, created_at) \
         VALUES (?1, 't1', ?2, ?3, ?4, '0000000000000_0000_0000000000000000', \
                 '2026-03-27T00:00:00Z')",
        rusqlite::params![reminder_id, reminder_at, dismissed_at, cancelled_at],
    )
    .unwrap();
}

fn reminder_at(conn: &Connection, reminder_id: &str) -> String {
    conn.query_row(
        "SELECT reminder_at FROM task_reminders WHERE id = ?1",
        rusqlite::params![reminder_id],
        |row| row.get(0),
    )
    .unwrap()
}

#[test]
fn defer_with_date_updates_planned_date_and_increments_count() {
    let conn = setup();
    let patch = TaskDeferralPatch {
        planned_date: Some("2026-04-01"),
        ai_notes: None,
        last_defer_reason: None,
    };
    let ok = defer_task(
        &conn,
        &tid("t1"),
        &patch,
        "v1",
        "2026-03-27T12:00:00Z",
        test_reminder_version,
    )
    .unwrap();
    assert!(ok.updated);

    let (planned, defer_count, last_def, version): (Option<String>, i64, Option<String>, String) = conn
        .query_row(
            "SELECT planned_date, defer_count, last_deferred_at, version FROM tasks WHERE id = 't1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .unwrap();
    assert_eq!(planned.as_deref(), Some("2026-04-01"));
    assert_eq!(defer_count, 1);
    assert_eq!(last_def.as_deref(), Some("2026-03-27T12:00:00Z"));
    assert_eq!(version, "v1");
}

#[test]
fn defer_with_new_planned_date_shifts_only_pending_reminders() {
    let conn = setup();
    conn.execute(
        "UPDATE tasks SET planned_date = '2030-04-17' WHERE id = 't1'",
        [],
    )
    .unwrap();
    seed_reminder(&conn, "r-active", "2030-04-17T13:45:00.000000Z", None, None);
    seed_reminder(&conn, "r-past", "2020-01-01T00:00:00.000000Z", None, None);
    seed_reminder(
        &conn,
        "r-dismissed",
        "2030-04-17T13:45:00.000000Z",
        Some("2026-03-27T00:00:00Z"),
        None,
    );
    seed_reminder(
        &conn,
        "r-cancelled",
        "2030-04-17T13:45:00.000000Z",
        None,
        Some("2026-03-27T00:00:00Z"),
    );

    let patch = TaskDeferralPatch {
        planned_date: Some("2030-04-20"),
        ai_notes: None,
        last_defer_reason: None,
    };
    let result = defer_task(
        &conn,
        &tid("t1"),
        &patch,
        "1711712640000_0001_task",
        "2026-03-27T12:00:00Z",
        test_reminder_version,
    )
    .unwrap();

    assert!(result.updated);
    assert_eq!(result.shifted_reminder_ids, vec!["r-active"]);
    assert!(
        reminder_at(&conn, "r-active").starts_with("2030-04-20T13:45:00"),
        "active reminder should move by +3 days"
    );
    assert_eq!(reminder_at(&conn, "r-past"), "2020-01-01T00:00:00.000000Z");
    assert_eq!(
        reminder_at(&conn, "r-dismissed"),
        "2030-04-17T13:45:00.000000Z"
    );
    assert_eq!(
        reminder_at(&conn, "r-cancelled"),
        "2030-04-17T13:45:00.000000Z"
    );
}

#[test]
fn defer_uses_due_date_as_reminder_shift_anchor_when_planned_date_is_absent() {
    let conn = setup();
    conn.execute(
        "UPDATE tasks SET due_date = '2030-04-17' WHERE id = 't1'",
        [],
    )
    .unwrap();
    seed_reminder(&conn, "r-due", "2030-04-17T13:45:00.000000Z", None, None);

    let patch = TaskDeferralPatch {
        planned_date: Some("2030-04-20"),
        ai_notes: None,
        last_defer_reason: None,
    };
    let result = defer_task(
        &conn,
        &tid("t1"),
        &patch,
        "1711712640000_0001_task",
        "2026-03-27T12:00:00Z",
        test_reminder_version,
    )
    .unwrap();

    assert_eq!(result.shifted_reminder_ids, vec!["r-due"]);
    assert!(reminder_at(&conn, "r-due").starts_with("2030-04-20T13:45:00"));
}

#[test]
fn defer_without_existing_date_anchor_does_not_shift_reminders() {
    let conn = setup();
    seed_reminder(
        &conn,
        "r-unanchored",
        "2030-04-17T13:45:00.000000Z",
        None,
        None,
    );

    let patch = TaskDeferralPatch {
        planned_date: Some("2030-04-20"),
        ai_notes: None,
        last_defer_reason: None,
    };
    let result = defer_task(
        &conn,
        &tid("t1"),
        &patch,
        "1711712640000_0001_task",
        "2026-03-27T12:00:00Z",
        test_reminder_version,
    )
    .unwrap();

    assert!(result.shifted_reminder_ids.is_empty());
    assert_eq!(
        reminder_at(&conn, "r-unanchored"),
        "2030-04-17T13:45:00.000000Z"
    );
}

#[test]
fn defer_without_date_leaves_planned_date_unchanged() {
    let conn = setup();
    // Set an initial planned_date
    conn.execute(
        "UPDATE tasks SET planned_date = '2026-03-28' WHERE id = 't1'",
        [],
    )
    .unwrap();

    let patch = TaskDeferralPatch::default();
    let ok = defer_task(
        &conn,
        &tid("t1"),
        &patch,
        "v1",
        "2026-03-27T12:00:00Z",
        test_reminder_version,
    )
    .unwrap();
    assert!(ok.updated);

    let (planned, defer_count): (Option<String>, i64) = conn
        .query_row(
            "SELECT planned_date, defer_count FROM tasks WHERE id = 't1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(planned.as_deref(), Some("2026-03-28"));
    assert_eq!(defer_count, 1);
}

#[test]
fn defer_with_ai_notes_writes_notes_atomically() {
    let conn = setup();
    let patch = TaskDeferralPatch {
        planned_date: Some("2026-04-01"),
        ai_notes: Some("Deferred (#1): too busy today"),
        last_defer_reason: None,
    };
    let ok = defer_task(
        &conn,
        &tid("t1"),
        &patch,
        "v1",
        "2026-03-27T12:00:00Z",
        test_reminder_version,
    )
    .unwrap();
    assert!(ok.updated);

    let (ai_notes, defer_count, version): (Option<String>, i64, String) = conn
        .query_row(
            "SELECT ai_notes, defer_count, version FROM tasks WHERE id = 't1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    assert_eq!(ai_notes.as_deref(), Some("Deferred (#1): too busy today"));
    assert_eq!(defer_count, 1);
    assert_eq!(version, "v1");
}

#[test]
fn defer_without_ai_notes_leaves_existing_notes_unchanged() {
    let conn = setup();
    conn.execute(
        "UPDATE tasks SET ai_notes = 'existing notes' WHERE id = 't1'",
        [],
    )
    .unwrap();

    let patch = TaskDeferralPatch {
        planned_date: Some("2026-04-01"),
        ai_notes: None,
        last_defer_reason: None,
    };
    defer_task(
        &conn,
        &tid("t1"),
        &patch,
        "v1",
        "2026-03-27T12:00:00Z",
        test_reminder_version,
    )
    .unwrap();

    let ai_notes: Option<String> = conn
        .query_row("SELECT ai_notes FROM tasks WHERE id = 't1'", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(ai_notes.as_deref(), Some("existing notes"));
}

#[test]
fn defer_completed_task_returns_false() {
    let conn = setup();
    conn.execute("UPDATE tasks SET status = 'completed' WHERE id = 't1'", [])
        .unwrap();

    let patch = TaskDeferralPatch {
        planned_date: Some("2026-04-01"),
        ai_notes: None,
        last_defer_reason: None,
    };
    let ok = defer_task(
        &conn,
        &tid("t1"),
        &patch,
        "v1",
        "2026-03-27T12:00:00Z",
        test_reminder_version,
    )
    .unwrap();
    assert!(!ok.updated);
}

#[test]
fn defer_cancelled_task_returns_false() {
    let conn = setup();
    conn.execute("UPDATE tasks SET status = 'cancelled' WHERE id = 't1'", [])
        .unwrap();

    let patch = TaskDeferralPatch {
        planned_date: Some("2026-04-01"),
        ai_notes: None,
        last_defer_reason: None,
    };
    let ok = defer_task(
        &conn,
        &tid("t1"),
        &patch,
        "v1",
        "2026-03-27T12:00:00Z",
        test_reminder_version,
    )
    .unwrap();
    assert!(!ok.updated);
}

#[test]
fn defer_nonexistent_task_returns_false() {
    let conn = setup();
    let patch = TaskDeferralPatch {
        planned_date: Some("2026-04-01"),
        ai_notes: None,
        last_defer_reason: None,
    };
    let ok = defer_task(
        &conn,
        &tid("nonexistent"),
        &patch,
        "v1",
        "2026-03-27T12:00:00Z",
        test_reminder_version,
    )
    .unwrap();
    assert!(!ok.updated);
}

#[test]
fn defer_increments_count_cumulatively() {
    let conn = setup();
    let patch1 = TaskDeferralPatch {
        planned_date: Some("2026-04-01"),
        ai_notes: None,
        last_defer_reason: None,
    };
    defer_task(
        &conn,
        &tid("t1"),
        &patch1,
        "v1",
        "2026-03-27T12:00:00Z",
        test_reminder_version,
    )
    .unwrap();
    let patch2 = TaskDeferralPatch {
        planned_date: Some("2026-04-02"),
        ai_notes: None,
        last_defer_reason: None,
    };
    defer_task(
        &conn,
        &tid("t1"),
        &patch2,
        "v2",
        "2026-03-27T13:00:00Z",
        test_reminder_version,
    )
    .unwrap();

    let defer_count: i64 = conn
        .query_row("SELECT defer_count FROM tasks WHERE id = 't1'", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(defer_count, 2);
}

#[test]
fn version_is_properly_written() {
    let conn = setup();
    let patch = TaskDeferralPatch {
        planned_date: Some("2026-04-01"),
        ai_notes: None,
        last_defer_reason: None,
    };
    // the LWW gate compares version strings as
    // ordinary text. Use the realistic HLC shape
    // (`<unix_ms>_<seq>_<device>`) so the stamp lexicographically
    // dominates the seed `'0000000000000_0000_0000000000000000'` — same
    // lexical ordering CockroachDB / our outbox stamper produce in
    // practice.
    let stamp = "1711712640000_0001_ABCDEF12";
    defer_task(
        &conn,
        &tid("t1"),
        &patch,
        stamp,
        "2026-03-27T12:00:00Z",
        test_reminder_version,
    )
    .unwrap();

    let version: String = conn
        .query_row("SELECT version FROM tasks WHERE id = 't1'", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(version, stamp);
    assert!(!version.is_empty());
}

#[test]
fn reset_task_deferral_clears_fields() {
    let conn = setup();
    // First defer the task with a reason
    let patch = TaskDeferralPatch {
        planned_date: Some("2026-04-01"),
        ai_notes: None,
        last_defer_reason: Some("not_today"),
    };
    defer_task(
        &conn,
        &tid("t1"),
        &patch,
        "v1",
        "2026-03-27T12:00:00Z",
        test_reminder_version,
    )
    .unwrap();

    // Then reset
    let ok = reset_task_deferral(&conn, &tid("t1"), "v2", "2026-03-27T14:00:00Z").unwrap();
    assert!(ok);

    let (planned, defer_count, last_def, reason, version, updated_at): (Option<String>, i64, Option<String>, Option<String>, String, String) = conn
        .query_row(
            "SELECT planned_date, defer_count, last_deferred_at, last_defer_reason, version, updated_at FROM tasks WHERE id = 't1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?, row.get(4)?, row.get(5)?)),
        )
        .unwrap();
    assert_eq!(planned, None);
    assert_eq!(defer_count, 0);
    assert_eq!(last_def, None);
    assert_eq!(reason, None);
    assert_eq!(version, "v2");
    assert_eq!(updated_at, "2026-03-27T14:00:00Z");
}

#[test]
fn reset_deferral_completed_task_returns_false() {
    let conn = setup();
    conn.execute("UPDATE tasks SET status = 'completed' WHERE id = 't1'", [])
        .unwrap();

    let ok = reset_task_deferral(&conn, &tid("t1"), "v2", "2026-03-27T14:00:00Z").unwrap();
    assert!(!ok);
}

#[test]
fn reset_deferral_nonexistent_task_returns_false() {
    let conn = setup();
    let ok = reset_task_deferral(&conn, &tid("nonexistent"), "v2", "2026-03-27T14:00:00Z").unwrap();
    assert!(!ok);
}

#[test]
fn defer_with_reason_writes_last_defer_reason() {
    let conn = setup();
    let patch = TaskDeferralPatch {
        planned_date: Some("2026-04-01"),
        ai_notes: None,
        last_defer_reason: Some("low_energy"),
    };
    let ok = defer_task(
        &conn,
        &tid("t1"),
        &patch,
        "v1",
        "2026-03-27T12:00:00Z",
        test_reminder_version,
    )
    .unwrap();
    assert!(ok.updated);

    let reason: Option<String> = conn
        .query_row(
            "SELECT last_defer_reason FROM tasks WHERE id = 't1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(reason.as_deref(), Some("low_energy"));
}

#[test]
fn defer_without_reason_leaves_last_defer_reason_unchanged() {
    let conn = setup();
    let patch1 = TaskDeferralPatch {
        planned_date: Some("2026-04-01"),
        ai_notes: None,
        last_defer_reason: Some("blocked"),
    };
    defer_task(
        &conn,
        &tid("t1"),
        &patch1,
        "v1",
        "2026-03-27T12:00:00Z",
        test_reminder_version,
    )
    .unwrap();

    let patch2 = TaskDeferralPatch {
        planned_date: Some("2026-04-02"),
        ai_notes: None,
        last_defer_reason: None,
    };
    defer_task(
        &conn,
        &tid("t1"),
        &patch2,
        "v2",
        "2026-03-27T13:00:00Z",
        test_reminder_version,
    )
    .unwrap();

    let reason: Option<String> = conn
        .query_row(
            "SELECT last_defer_reason FROM tasks WHERE id = 't1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(reason.as_deref(), Some("blocked"));
}

/// a stale-version `defer_task` MUST be a no-op.
/// Returns `Ok(false)` so the caller can re-stamp HLC and retry.
#[test]
fn defer_with_stale_version_is_rejected() {
    let conn = setup();
    // Land a newer version on the row first.
    conn.execute(
        "UPDATE tasks SET version = ?1, planned_date = '2026-05-01', defer_count = 4 WHERE id = 't1'",
        [NEWER_STAMP],
    )
    .unwrap();

    let patch = TaskDeferralPatch {
        planned_date: Some("2026-04-01"),
        ai_notes: None,
        last_defer_reason: None,
    };
    let ok = defer_task(
        &conn,
        &tid("t1"),
        &patch,
        STALE_STAMP,
        "2026-03-27T12:00:00Z",
        test_reminder_version,
    )
    .unwrap();
    assert!(!ok.updated, "stale-version defer must report Ok(false)");

    // Row state must be untouched.
    let (planned, defer_count, version): (Option<String>, i64, String) = conn
        .query_row(
            "SELECT planned_date, defer_count, version FROM tasks WHERE id = 't1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    assert_eq!(planned.as_deref(), Some("2026-05-01"));
    assert_eq!(defer_count, 4);
    assert_eq!(version, NEWER_STAMP);
}

/// same gate on `reset_task_deferral`.
#[test]
fn reset_with_stale_version_is_rejected() {
    let conn = setup();
    conn.execute(
        "UPDATE tasks SET version = ?1, planned_date = '2026-05-01', defer_count = 4, \
         last_deferred_at = '2026-04-30T00:00:00Z', last_defer_reason = 'blocked' WHERE id = 't1'",
        [NEWER_STAMP],
    )
    .unwrap();

    let ok = reset_task_deferral(&conn, &tid("t1"), STALE_STAMP, "2026-03-27T14:00:00Z").unwrap();
    assert!(!ok, "stale-version reset must report Ok(false)");

    let (planned, defer_count, reason, version): (
        Option<String>, i64, Option<String>, String,
    ) = conn
        .query_row(
            "SELECT planned_date, defer_count, last_defer_reason, version FROM tasks WHERE id = 't1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .unwrap();
    assert_eq!(planned.as_deref(), Some("2026-05-01"));
    assert_eq!(defer_count, 4);
    assert_eq!(reason.as_deref(), Some("blocked"));
    assert_eq!(version, NEWER_STAMP);
}

/// same gate on `restore_task_deferral`. The undo
/// path must not clobber a newer peer write either.
#[test]
fn restore_with_stale_version_is_rejected() {
    let conn = setup();
    conn.execute(
        "UPDATE tasks SET version = ?1, planned_date = '2026-05-01', defer_count = 4 WHERE id = 't1'",
        [NEWER_STAMP],
    )
    .unwrap();

    let snapshot = TaskDeferralSnapshot {
        planned_date: None,
        defer_count: 0,
        last_deferred_at: None,
        last_defer_reason: None,
    };
    let ok = restore_task_deferral(
        &conn,
        &tid("t1"),
        &snapshot,
        STALE_STAMP,
        "2026-03-27T15:00:00Z",
    )
    .unwrap();
    assert!(!ok, "stale-version restore must report Ok(false)");

    let (planned, defer_count, version): (Option<String>, i64, String) = conn
        .query_row(
            "SELECT planned_date, defer_count, version FROM tasks WHERE id = 't1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    assert_eq!(planned.as_deref(), Some("2026-05-01"));
    assert_eq!(defer_count, 4);
    assert_eq!(version, NEWER_STAMP);
}

#[test]
fn reset_clears_last_defer_reason() {
    let conn = setup();
    let patch = TaskDeferralPatch {
        planned_date: Some("2026-04-01"),
        ai_notes: None,
        last_defer_reason: Some("needs_info"),
    };
    defer_task(
        &conn,
        &tid("t1"),
        &patch,
        "v1",
        "2026-03-27T12:00:00Z",
        test_reminder_version,
    )
    .unwrap();

    reset_task_deferral(&conn, &tid("t1"), "v2", "2026-03-27T14:00:00Z").unwrap();

    let reason: Option<String> = conn
        .query_row(
            "SELECT last_defer_reason FROM tasks WHERE id = 't1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(reason, None);
}
