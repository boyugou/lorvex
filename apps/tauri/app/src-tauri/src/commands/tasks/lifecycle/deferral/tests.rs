use super::*;
use crate::test_support::test_conn;

fn seed_task(conn: &Connection, id: &str, planned: Option<&str>, due: Option<&str>) {
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title("Call mom")
        .list_id(Some("inbox"))
        .planned_date(planned)
        .due_date(due)
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-04-16T00:00:00Z")
        .insert(conn);
}

fn seed_reminder(conn: &Connection, rid: &str, task_id: &str, reminder_at: &str) {
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES (?1, ?2, ?3, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-16T00:00:00Z')",
        rusqlite::params![rid, task_id, reminder_at],
    )
    .unwrap();
}

fn reminder_at_of(conn: &Connection, rid: &str) -> String {
    conn.query_row(
        "SELECT reminder_at FROM task_reminders WHERE id = ?1",
        rusqlite::params![rid],
        |row| row.get(0),
    )
    .unwrap()
}

fn reminder_outbox_count(conn: &Connection, rid: &str) -> i64 {
    conn.query_row(
        "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
        rusqlite::params![lorvex_domain::naming::ENTITY_TASK_REMINDER, rid],
        |row| row.get(0),
    )
    .unwrap()
}

#[test]
fn defer_until_moves_pending_reminder_forward_by_planned_delta() {
    // deferring a task's planned_date from D to D+3
    // shifts pending reminders forward by 3 days, so "remind 15 min
    // before" continues to mean 15 min before the new target.
    let conn = test_conn();
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000035",
        Some("2030-04-17"),
        Some("2030-04-17"),
    );
    seed_reminder(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000002f",
        "01966a3f-7c8b-7d4e-8f3a-000000000035",
        "2030-04-17T13:45:00.000000Z",
    );

    defer_task_until_with_conn(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000035",
        "2030-04-20",
        None,
    )
    .unwrap();

    let shifted = reminder_at_of(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000002f");
    assert!(
        shifted.starts_with("2030-04-20T13:45:00"),
        "expected reminder to shift +3 days, got {shifted}"
    );
    assert_eq!(
        reminder_outbox_count(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000002f"),
        1
    );
}

#[test]
fn defer_until_leaves_past_reminders_alone() {
    let conn = test_conn();
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000035",
        Some("2030-04-17"),
        None,
    );
    seed_reminder(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000031",
        "01966a3f-7c8b-7d4e-8f3a-000000000035",
        "2020-01-01T00:00:00.000000Z",
    );

    defer_task_until_with_conn(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000035",
        "2030-04-20",
        None,
    )
    .unwrap();

    let reminder_at = reminder_at_of(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000031");
    assert_eq!(reminder_at, "2020-01-01T00:00:00.000000Z");
    assert_eq!(
        reminder_outbox_count(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000031"),
        0
    );
}

#[test]
fn defer_until_does_not_shift_when_no_old_reference_date() {
    // Task has neither planned_date nor due_date before defer;
    // nothing to shift against.
    let conn = test_conn();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000035", None, None);
    seed_reminder(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000002f",
        "01966a3f-7c8b-7d4e-8f3a-000000000035",
        "2030-04-17T13:45:00.000000Z",
    );

    defer_task_until_with_conn(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000035",
        "2030-04-20",
        None,
    )
    .unwrap();

    assert_eq!(
        reminder_at_of(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000002f"),
        "2030-04-17T13:45:00.000000Z"
    );
    assert_eq!(
        reminder_outbox_count(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000002f"),
        0
    );
}

// ──────────────────────────────────────────────────────────────────
// IPC test coverage for `defer_task`, `defer_task_until`,
// `reset_task_deferral`, and `restore_task_deferral`. Each test runs
// the `_with_conn` shim against an in-memory DB.
// ──────────────────────────────────────────────────────────────────

fn seed_task_with_status(conn: &Connection, id: &str, status: &str) {
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title("Plan lunch")
        .status(status)
        .list_id(Some("inbox"))
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-04-16T00:00:00Z")
        .insert(conn);
}

fn force_future_task_version(conn: &Connection, id: &str) {
    conn.execute(
        "UPDATE tasks SET version = '9999999999999_0000_ffffffffffffffff' WHERE id = ?1",
        rusqlite::params![id],
    )
    .expect("force future task version");
}

fn assert_stale_task_version(error: AppError, id: &str) {
    match error {
        AppError::Store(boxed) => match *boxed {
            lorvex_store::StoreError::StaleVersion { entity, id: actual } => {
                assert_eq!(entity, "task");
                assert_eq!(actual, id);
            }
            other => panic!("expected task StaleVersion, got {other:?}"),
        },
        other => panic!("expected task StaleVersion, got {other:?}"),
    }
}

fn assert_no_task_side_effect_rows(conn: &Connection, id: &str) {
    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?1",
            rusqlite::params![id],
            |row| row.get(0),
        )
        .expect("count task outbox rows");
    assert_eq!(
        outbox_count, 0,
        "stale deferral operation must not enqueue task sync rows"
    );

    let changelog_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE entity_id = ?1",
            rusqlite::params![id],
            |row| row.get(0),
        )
        .expect("count task changelog rows");
    assert_eq!(
        changelog_count, 0,
        "stale deferral operation must not log a successful mutation"
    );
}

#[test]
fn defer_task_with_conn_rejects_missing_task() {
    let conn = test_conn();
    let error = defer_task_with_conn(&conn, "does-not-exist", None)
        .expect_err("missing task should be rejected");
    assert!(matches!(error, AppError::NotFound(_)));
}

#[test]
fn defer_task_with_conn_sets_planned_date_to_tomorrow_and_bumps_count() {
    let conn = test_conn();
    seed_task_with_status(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000048", "open");

    let task = defer_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000048", None)
        .expect("defer should succeed");
    assert!(
        task.planned_date.is_some(),
        "defer_task must populate planned_date"
    );
    assert_eq!(task.defer_count, 1, "defer must bump defer_count");
}

#[test]
fn defer_task_with_conn_rejects_completed_task() {
    let conn = test_conn();
    seed_task_with_status(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000004c", "completed");

    let error = defer_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000004c", None)
        .expect_err("completed task should not be deferrable");
    match error {
        AppError::Validation(msg) => {
            assert!(msg.contains("Cannot defer"), "unexpected: {msg}");
        }
        other => panic!("expected Validation, got {other:?}"),
    }
}

#[test]
fn defer_task_until_with_conn_rejects_malformed_date() {
    let conn = test_conn();
    seed_task_with_status(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000048", "open");

    let error = defer_task_until_with_conn(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000048",
        "not-a-date",
        None,
    )
    .expect_err("malformed until_date should be rejected");
    assert!(
        !error.to_string().is_empty(),
        "error message must surface a reason"
    );
    // No row should have been written.
    let planned: Option<String> = conn
        .query_row(
            "SELECT planned_date FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000048'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert!(planned.is_none(), "malformed defer must roll back");
}

#[test]
fn defer_task_until_with_conn_defers_to_specific_date() {
    let conn = test_conn();
    seed_task_with_status(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000048", "open");

    let task = defer_task_until_with_conn(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000048",
        "2026-05-15",
        Some("blocked"),
    )
    .expect("defer_until should succeed");
    assert_eq!(task.planned_date.as_deref(), Some("2026-05-15"));
    assert_eq!(
        task.last_defer_reason
            .map(lorvex_domain::naming::DeferReason::as_str),
        Some("blocked"),
    );
}

#[test]
fn defer_task_until_with_conn_rejects_stale_version_without_side_effects() {
    let conn = test_conn();
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000007a",
        Some("2030-04-17"),
        Some("2030-04-17"),
    );
    seed_reminder(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000032",
        "01966a3f-7c8b-7d4e-8f3a-00000000007a",
        "2030-04-17T13:45:00.000000Z",
    );
    force_future_task_version(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000007a");

    let error = defer_task_until_with_conn(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000007a",
        "2030-04-20",
        None,
    )
    .expect_err("stale version must reject deferral");
    assert_stale_task_version(error, "01966a3f-7c8b-7d4e-8f3a-00000000007a");

    let (planned_date, defer_count): (Option<String>, i64) = conn
        .query_row(
            "SELECT planned_date, defer_count FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-00000000007a'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load stale defer task");
    assert_eq!(planned_date.as_deref(), Some("2030-04-17"));
    assert_eq!(defer_count, 0);
    assert_eq!(
        reminder_at_of(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000032"),
        "2030-04-17T13:45:00.000000Z",
        "stale defer must not shift reminders when the task row did not update"
    );
    assert_no_task_side_effect_rows(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000007a");
}

#[test]
fn defer_task_until_with_conn_rejects_invalid_structured_reason() {
    let conn = test_conn();
    seed_task_with_status(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000048", "open");

    let error = defer_task_until_with_conn(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000048",
        "2026-05-15",
        Some("totally-bogus-reason"),
    )
    .expect_err("invalid reason should be rejected");
    match error {
        AppError::Validation(msg) => {
            assert!(msg.contains("Invalid defer reason"), "unexpected: {msg}");
        }
        other => panic!("expected Validation, got {other:?}"),
    }
}

#[test]
fn reset_task_deferral_with_conn_rejects_cancelled_task() {
    let conn = test_conn();
    seed_task_with_status(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000005f", "cancelled");

    let error = reset_task_deferral_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000005f")
        .expect_err("cannot reset deferral on a cancelled task");
    match error {
        AppError::Validation(msg) => {
            assert!(msg.contains("Cannot reset deferral"), "unexpected: {msg}");
        }
        other => panic!("expected Validation, got {other:?}"),
    }
}

#[test]
fn reset_task_deferral_with_conn_clears_deferral_state() {
    let conn = test_conn();
    // Seed a task that already has defer state populated.
    // Stays raw: TaskBuilder doesn't expose `last_deferred_at` or
    // `last_defer_reason`, both load-bearing for the deferral
    // reset path this test exercises.
    conn.execute(
        "INSERT INTO tasks (id, title, status, list_id, planned_date, last_deferred_at,
            last_defer_reason, defer_count, version, created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-00000000006b', 'Ping team', 'open', 'inbox', '2026-05-01',
            '2026-04-18T00:00:00Z', 'blocked', 3, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-16T00:00:00Z',
            '2026-04-16T00:00:00Z')",
        [],
    )
    .unwrap();

    let task = reset_task_deferral_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000006b")
        .expect("reset should succeed");

    assert_eq!(task.defer_count, 0, "defer_count must be zeroed");
    assert!(
        task.planned_date.is_none(),
        "planned_date must be cleared on reset"
    );
    assert!(
        task.last_defer_reason.is_none(),
        "last_defer_reason must be cleared"
    );
}

#[test]
fn reset_task_deferral_with_conn_rejects_stale_version_without_side_effects() {
    let conn = test_conn();
    // Stays raw: TaskBuilder doesn't expose `last_deferred_at` or
    // `last_defer_reason`, both load-bearing for the deferral
    // reset path this test exercises.
    conn.execute(
        "INSERT INTO tasks (id, title, status, list_id, planned_date, last_deferred_at,
            last_defer_reason, defer_count, version, created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-00000000007d', 'Ping team', 'open', 'inbox', '2026-05-01',
            '2026-04-18T00:00:00Z', 'blocked', 3, '0000000000000_0000_a0a0a0a0a0a0a0a0',
            '2026-04-16T00:00:00Z', '2026-04-16T00:00:00Z')",
        [],
    )
    .unwrap();
    force_future_task_version(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000007d");

    let error = reset_task_deferral_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000007d")
        .expect_err("stale version must reject reset");
    assert_stale_task_version(error, "01966a3f-7c8b-7d4e-8f3a-00000000007d");

    let (planned_date, defer_count, reason): (Option<String>, i64, Option<String>) = conn
        .query_row(
            "SELECT planned_date, defer_count, last_defer_reason FROM tasks \
             WHERE id = '01966a3f-7c8b-7d4e-8f3a-00000000007d'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("load stale reset task");
    assert_eq!(planned_date.as_deref(), Some("2026-05-01"));
    assert_eq!(defer_count, 3);
    assert_eq!(reason.as_deref(), Some("blocked"));
    assert_no_task_side_effect_rows(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000007d");
}

#[test]
fn restore_task_deferral_with_conn_restores_exact_snapshot() {
    let conn = test_conn();
    seed_task_with_status(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000006d", "open");

    let snapshot = DeferralSnapshot {
        planned_date: Some("2026-04-20".to_string()),
        defer_count: 2,
        last_deferred_at: Some("2026-04-19T12:00:00Z".to_string()),
        last_defer_reason: Some("low_energy".to_string()),
    };

    let task =
        restore_task_deferral_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000006d", &snapshot)
            .expect("restore should succeed");

    assert_eq!(task.planned_date.as_deref(), Some("2026-04-20"));
    assert_eq!(task.defer_count, 2);
    assert_eq!(
        task.last_defer_reason
            .map(lorvex_domain::naming::DeferReason::as_str),
        Some("low_energy"),
    );
}

#[test]
fn restore_task_deferral_with_conn_rejects_completed_task() {
    let conn = test_conn();
    seed_task_with_status(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000004c", "completed");

    let snapshot = DeferralSnapshot {
        planned_date: None,
        defer_count: 0,
        last_deferred_at: None,
        last_defer_reason: None,
    };
    let error =
        restore_task_deferral_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000004c", &snapshot)
            .expect_err("completed task must reject restore");
    assert!(matches!(error, AppError::Validation(_)));
}

#[test]
fn restore_task_deferral_with_conn_rejects_stale_version_without_side_effects() {
    let conn = test_conn();
    seed_task_with_status(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000007e", "open");
    force_future_task_version(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000007e");

    let snapshot = DeferralSnapshot {
        planned_date: Some("2026-04-20".to_string()),
        defer_count: 2,
        last_deferred_at: Some("2026-04-19T12:00:00Z".to_string()),
        last_defer_reason: Some("low_energy".to_string()),
    };
    let error =
        restore_task_deferral_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000007e", &snapshot)
            .expect_err("stale version must reject restore");
    assert_stale_task_version(error, "01966a3f-7c8b-7d4e-8f3a-00000000007e");

    let (planned_date, defer_count, reason): (Option<String>, i64, Option<String>) = conn
        .query_row(
            "SELECT planned_date, defer_count, last_defer_reason FROM tasks \
             WHERE id = '01966a3f-7c8b-7d4e-8f3a-00000000007e'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("load stale restore task");
    assert!(planned_date.is_none());
    assert_eq!(defer_count, 0);
    assert!(reason.is_none());
    assert_no_task_side_effect_rows(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000007e");
}
