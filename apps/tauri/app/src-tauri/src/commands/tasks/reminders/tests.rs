use super::*;

use lorvex_store::repositories::task::reminders::ReminderRow;
use rusqlite::params;

use crate::test_support::test_conn;

fn seed_task(conn: &rusqlite::Connection, task_id: &str) {
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(task_id)
        .title("Task")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-03-29T08:00:00Z")
        .insert(conn);
}

#[test]
fn create_reminder_captures_original_local_time_and_tz() {
    // when PREF_TIMEZONE is set, the creation path
    // stores the reminder's wall-clock (HH:MM) in the user's
    // active zone. The re-anchor sweep later uses this pair to
    // rebuild reminder_at after a zone change.
    let conn = test_conn();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000001");
    conn.execute(
            "INSERT INTO preferences (key, value, updated_at, version) \
             VALUES ('timezone', '\"Asia/Tokyo\"', '2026-03-29T00:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0')",
            [],
        )
        .expect("seed timezone preference");

    // 2026-03-29T00:00Z → 2026-03-29 09:00 Asia/Tokyo.
    let reminder = add_task_reminder_with_conn(
        &conn,
        &lorvex_domain::TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000001".to_string()),
        "2026-03-29T00:00:00Z",
        "2026-03-28T10:00:00Z",
    )
    .expect("add reminder");

    let (original_local_time, original_tz): (Option<String>, Option<String>) = conn
        .query_row(
            "SELECT original_local_time, original_tz FROM task_reminders WHERE id = ?1",
            params![reminder.id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load anchor columns");
    assert_eq!(original_local_time.as_deref(), Some("09:00"));
    assert_eq!(original_tz.as_deref(), Some("Asia/Tokyo"));
}

#[test]
fn create_reminder_with_offset_persists_canonical_utc_timestamp() {
    let conn = test_conn();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000001");

    let reminder = add_task_reminder_with_conn(
        &conn,
        &lorvex_domain::TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000001".to_string()),
        "2026-12-01T09:00:00-05:00",
        "2026-03-28T10:00:00Z",
    )
    .expect("add offset reminder");

    assert_eq!(reminder.reminder_at, "2026-12-01T14:00:00.000Z");
    let stored: String = conn
        .query_row(
            "SELECT reminder_at FROM task_reminders WHERE id = ?1",
            params![reminder.id],
            |row| row.get(0),
        )
        .expect("load reminder_at");
    assert_eq!(stored, "2026-12-01T14:00:00.000Z");

    let due = lorvex_store::repositories::task::reminders::get_due_task_reminders(
        &conn,
        "2026-12-02T00:00:00.000Z",
        10,
    )
    .expect("canonical reminder should be readable by due-reminder query");
    assert_eq!(due.rows.len(), 1);
    assert_eq!(
        due.rows[0].reminder_at.as_string(),
        "2026-12-01T14:00:00.000Z"
    );
}

#[test]
fn create_reminder_leaves_anchor_null_when_no_timezone_preference() {
    // fresh installs / MCP-only boots have no
    // PREF_TIMEZONE. Those reminders fall back to pure
    // absolute-UTC semantics — both anchor columns NULL so the
    // re-anchor sweep skips them.
    let conn = test_conn();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000001");

    let reminder = add_task_reminder_with_conn(
        &conn,
        &lorvex_domain::TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000001".to_string()),
        "2026-03-29T00:00:00Z",
        "2026-03-28T10:00:00Z",
    )
    .expect("add reminder");

    let (original_local_time, original_tz): (Option<String>, Option<String>) = conn
        .query_row(
            "SELECT original_local_time, original_tz FROM task_reminders WHERE id = ?1",
            params![reminder.id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load anchor columns");
    assert!(original_local_time.is_none());
    assert!(original_tz.is_none());
}

#[test]
fn create_reminder_ignores_cancelled_and_dismissed_history_for_cap() {
    let conn = test_conn();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000001");
    for index in 0..MAX_REMINDERS_PER_TASK {
        let dismissed_at: Option<&str> = (index % 2 == 0).then_some("2026-03-30T00:00:00Z");
        let cancelled_at: Option<&str> = (index % 2 == 1).then_some("2026-03-30T00:00:00Z");
        conn.execute(
            "INSERT INTO task_reminders
                   (id, task_id, reminder_at, dismissed_at, cancelled_at, version, created_at)
                 VALUES (?1, '01966a3f-7c8b-7d4e-8f3a-000000000001', ?2, ?3, ?4, ?5, '2026-03-29T00:00:00Z')",
            params![
                format!("history-{index}"),
                format!("2026-03-29T{:02}:00:00Z", index % 24),
                dismissed_at,
                cancelled_at,
                format!("00000000000{index:02}_0000_0000000000000000"),
            ],
        )
        .expect("seed historical reminder");
    }

    let reminder = add_task_reminder_with_conn(
        &conn,
        &lorvex_domain::TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000001".to_string()),
        "2026-03-31T10:00:00Z",
        "2026-03-30T09:00:00Z",
    )
    .expect("historical reminders should not consume active cap");

    assert_eq!(reminder.task_id, "01966a3f-7c8b-7d4e-8f3a-000000000001");
    let active_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_reminders
                 WHERE task_id = '01966a3f-7c8b-7d4e-8f3a-000000000001'
                   AND dismissed_at IS NULL
                   AND cancelled_at IS NULL",
            [],
            |row| row.get(0),
        )
        .expect("count active reminders");
    assert_eq!(active_count, 1);
}

#[test]
fn add_task_reminder_inner_rejects_missing_task() {
    let conn = test_conn();
    let error = add_task_reminder_with_conn(
        &conn,
        &lorvex_domain::TaskId::from_trusted("missing-task".to_string()),
        "2026-03-29T10:00:00Z",
        "2026-03-29T09:00:00Z",
    )
    .expect_err("missing task should be rejected");

    match error {
        AppError::NotFound(message) => assert!(message.contains("missing-task")),
        other => panic!("expected not found error, got {other:?}"),
    }
}

#[test]
fn hydrate_due_reminder_entries_rejects_missing_task() {
    let conn = test_conn();
    let rows = vec![ReminderRow {
        id: "01966a3f-7c8b-7d4e-8f3a-00000000002c".to_string(),
        task_id: "missing-task".to_string(),
        reminder_at: lorvex_domain::SyncTimestamp::parse("2026-03-29T10:00:00Z")
            .expect("canonical reminder_at"),
        dismissed_at: None,
        cancelled_at: None,
        created_at: lorvex_domain::SyncTimestamp::parse("2026-03-29T09:00:00Z")
            .expect("canonical created_at"),
        delivery_state: "pending".to_string(),
        task_title: "Task".to_string(),
        task_status: "open".to_string(),
        task_due_date: None,
        task_priority: None,
    }];

    let error = hydrate_due_reminder_entries(&conn, rows)
        .expect_err("missing hydrated task should be rejected");

    match error {
        AppError::NotFound(message) => assert!(message.contains("missing-task")),
        other => panic!("expected not found error, got {other:?}"),
    }
}

#[test]
fn get_task_reminders_with_conn_rejects_malformed_task_id_before_trusted_wrap() {
    let conn = test_conn();

    let error = get_task_reminders_with_conn(&conn, "not-a-uuid")
        .expect_err("malformed IPC task_id should be rejected");

    match error {
        AppError::Validation(message) => {
            assert!(
                message.contains("task_id is not a valid UUID"),
                "unexpected validation message: {message}"
            );
            assert!(
                message.contains("not-a-uuid"),
                "validation message should include rejected id: {message}"
            );
        }
        other => panic!("expected validation error, got {other:?}"),
    }
}

#[test]
fn get_task_reminders_with_conn_preserves_valid_uuid_missing_as_empty() {
    let conn = test_conn();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-000000000341";

    let reminders =
        get_task_reminders_with_conn(&conn, task_id).expect("valid missing id should not error");

    assert!(reminders.is_empty());
}

#[test]
fn snooze_reminder_for_task_internal_creates_new_reminder_on_same_task() {
    let conn = test_conn();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000001");

    // Upper bound on the reminder's scheduled-at timestamp. We compute
    // it BEFORE the call and assert against the inserted row afterwards.
    let before = chrono::Utc::now();

    let reminder = snooze_reminder_for_task_internal(
        &conn,
        &lorvex_domain::TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000001".to_string()),
    )
    .expect("snooze helper should succeed");

    // Same task, not a task-level deferral.
    assert_eq!(reminder.task_id, "01966a3f-7c8b-7d4e-8f3a-000000000001");
    assert_eq!(reminder.delivery_state.as_deref(), Some("pending"));

    let reminder_at = chrono::DateTime::parse_from_rfc3339(&reminder.reminder_at)
        .expect("reminder_at must be RFC3339")
        .with_timezone(&chrono::Utc);
    let after = chrono::Utc::now();
    // `reminder_at` is stored with millisecond
    // precision via `format_sync_timestamp` whereas
    // `chrono::Utc::now()` runs at sub-millisecond precision —
    // widen the window by 1 ms on each side so a legitimate
    // round-trip truncation doesn't trip the assertion.
    let tolerance = chrono::Duration::milliseconds(1);
    let expected_min =
        before + chrono::Duration::minutes(DEFAULT_REMINDER_SNOOZE_MINUTES) - tolerance;
    let expected_max =
        after + chrono::Duration::minutes(DEFAULT_REMINDER_SNOOZE_MINUTES) + tolerance;
    assert!(
        reminder_at >= expected_min && reminder_at <= expected_max,
        "reminder_at {reminder_at:?} not within [{expected_min:?}, {expected_max:?}]"
    );

    // The task's planned_date must be untouched — snooze is a reminder
    // action, not a task action.
    let planned_date: Option<String> = conn
        .query_row(
            "SELECT planned_date FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000001'",
            [],
            |row| row.get(0),
        )
        .expect("read planned_date");
    assert!(
        planned_date.is_none(),
        "planned_date must remain unchanged after snooze, got {planned_date:?}"
    );

    // A sync outbox row must have been enqueued for the new reminder.
    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?1",
            params![reminder.id],
            |row| row.get(0),
        )
        .expect("count outbox rows");
    assert_eq!(outbox_count, 1, "snooze must enqueue a sync outbox row");
}

#[test]
fn snooze_reminder_for_task_internal_rejects_missing_task() {
    let conn = test_conn();
    let error = snooze_reminder_for_task_internal(
        &conn,
        &lorvex_domain::TaskId::from_trusted("missing-task".to_string()),
    )
    .expect_err("missing task should be rejected");
    match error {
        AppError::NotFound(message) => assert!(message.contains("missing-task")),
        other => panic!("expected not found error, got {other:?}"),
    }
}

/// the shared
/// `reminders::get_reminders_for_task` helper must skip
/// reminders whose parent task is in the Trash
/// (`archived_at IS NOT NULL`). Pre-fix, the Tauri-side
/// `get_task_reminders` IPC issued a bare `task_reminders` SELECT
/// with no `tasks` join, so it returned reminders attached to
/// trashed tasks while the notification poller (which goes
/// through `get_due_task_reminders` /
/// `get_upcoming_task_reminders_until`) correctly suppressed them.
/// The fix funnels both paths through one helper; this test pins
/// the trash-filter semantic.
#[test]
fn get_reminders_for_task_excludes_trashed_parent() {
    let conn = test_conn();
    // Seed two tasks: one live, one trashed (with `archived_at`).
    // lift to canonical TaskBuilder.
    use lorvex_store::test_support::fixtures::TaskBuilder;
    TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-000000000060")
        .title("Live task")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-04-01T08:00:00Z")
        .list_id(Some("inbox"))
        .insert(&conn);
    TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-00000000007f")
        .title("Trashed task")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-04-01T08:00:00Z")
        .list_id(Some("inbox"))
        .archived_at(Some("2026-04-02T09:00:00Z"))
        .insert(&conn);

    // One reminder per task.
    conn.execute(
            "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
             VALUES ('01966a3f-7c8b-7d4e-8f3a-00000000002d', '01966a3f-7c8b-7d4e-8f3a-000000000060', '2026-04-10T10:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z')",
            [],
        )
        .expect("seed live reminder");
    conn.execute(
            "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
             VALUES ('01966a3f-7c8b-7d4e-8f3a-00000000002eed', '01966a3f-7c8b-7d4e-8f3a-00000000007f', '2026-04-10T10:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z')",
            [],
        )
        .expect("seed trashed reminder");

    let live_rows = lorvex_store::repositories::task::reminders::get_reminders_for_task(
        &conn,
        &lorvex_domain::TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000060".to_string()),
    )
    .expect("query live reminders");
    assert_eq!(live_rows.len(), 1);
    assert_eq!(live_rows[0].id, "01966a3f-7c8b-7d4e-8f3a-00000000002d");

    // The trashed parent suppresses its reminder from this read,
    // matching the notification poller's behavior.
    let trashed_rows = lorvex_store::repositories::task::reminders::get_reminders_for_task(
        &conn,
        &lorvex_domain::TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000007f".to_string()),
    )
    .expect("query trashed reminders");
    assert!(
        trashed_rows.is_empty(),
        "reminders for trashed parent must not be returned"
    );
}

#[test]
fn add_task_reminder_in_transaction_rolls_back_when_sync_enqueue_fails() {
    let conn = test_conn();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000001");
    conn.execute("DROP TABLE sync_outbox", [])
        .expect("drop sync_outbox to force enqueue failure");

    let error = add_task_reminder_in_transaction(
        &conn,
        &lorvex_domain::TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000001".to_string()),
        "2026-03-29T10:00:00Z",
        "2026-03-29T09:00:00Z",
    )
    .expect_err("enqueue failure should roll back reminder creation");

    let message = error.to_string();
    assert!(
        message.contains("database error") || message.contains("no such table"),
        "unexpected error: {message}"
    );

    let reminder_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM task_reminders", [], |row| row.get(0))
        .expect("count reminders");
    assert_eq!(reminder_count, 0);
}

// ── mark_reminder_notified EXISTS guard ─────────────

fn seed_live_reminder(conn: &rusqlite::Connection, reminder_id: &str, task_id: &str) {
    conn.execute(
        "INSERT INTO task_reminders \
             (id, task_id, reminder_at, dismissed_at, cancelled_at, version, created_at) \
             VALUES (?1, ?2, '2026-04-26T10:00:00Z', NULL, NULL, \
                     '0000000000001_0000_0000000000000000', '2026-04-25T08:00:00Z')",
        params![reminder_id, task_id],
    )
    .expect("seed reminder");
}

fn delivery_state_for(conn: &rusqlite::Connection, reminder_id: &str) -> Option<String> {
    conn.query_row(
        "SELECT delivery_state FROM task_reminder_delivery_state WHERE reminder_id = ?1",
        params![reminder_id],
        |row| row.get::<_, String>(0),
    )
    .ok()
}

#[test]
fn mark_reminder_notified_stamps_live_reminder() {
    let conn = test_conn();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000001");
    seed_live_reminder(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000002c",
        "01966a3f-7c8b-7d4e-8f3a-000000000001",
    );

    let stamped = mark_reminder_notified_with_conn(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000002c",
        "2026-04-26T10:01:00Z",
    )
    .expect("mark live reminder");
    assert!(stamped, "live reminder should be stamped");
    assert_eq!(
        delivery_state_for(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000002c").as_deref(),
        Some("delivered"),
    );
}

#[test]
fn mark_reminder_notified_skips_cancelled_reminder() {
    let conn = test_conn();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000001");
    conn.execute(
        "INSERT INTO task_reminders \
             (id, task_id, reminder_at, dismissed_at, cancelled_at, version, created_at) \
             VALUES ('01966a3f-7c8b-7d4e-8f3a-00000000002f', '01966a3f-7c8b-7d4e-8f3a-000000000001', '2026-04-26T10:00:00Z', NULL, \
                     '2026-04-26T09:00:00Z', '0000000000001_0000_0000000000000000', \
                     '2026-04-25T08:00:00Z')",
        [],
    )
    .expect("seed cancelled reminder");

    let stamped = mark_reminder_notified_with_conn(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000002f",
        "2026-04-26T10:01:00Z",
    )
    .expect("call returns");
    assert!(!stamped, "cancelled reminder must not be stamped");
    assert!(
        delivery_state_for(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000002f").is_none(),
        "no delivery row should be written for a cancelled reminder",
    );
}

#[test]
fn mark_reminder_notified_skips_archived_task_reminder() {
    let conn = test_conn();
    // Seed a task that is in the Trash (archived_at IS NOT NULL).
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-000000000011")
        .title("Trashed")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-03-29T08:00:00Z")
        .updated_at("2026-04-26T08:00:00Z")
        .archived_at(Some("2026-04-26T08:00:00Z"))
        .insert(&conn);
    seed_live_reminder(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000002e",
        "01966a3f-7c8b-7d4e-8f3a-000000000011",
    );

    let stamped = mark_reminder_notified_with_conn(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000002e",
        "2026-04-26T10:01:00Z",
    )
    .expect("call returns");
    assert!(
        !stamped,
        "reminder for an archived task must not be stamped"
    );
    assert!(
        delivery_state_for(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000002e").is_none(),
        "no delivery row should be written for a trashed-task reminder",
    );
}

#[test]
fn mark_reminder_notified_unknown_id_is_idempotent_noop() {
    let conn = test_conn();
    let stamped = mark_reminder_notified_with_conn(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000030",
        "2026-04-26T10:01:00Z",
    )
    .expect("unknown id returns Ok");
    assert!(!stamped);
}
