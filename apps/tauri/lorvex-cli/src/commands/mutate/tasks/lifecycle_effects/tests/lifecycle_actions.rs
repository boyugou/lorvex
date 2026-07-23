use super::super::*;
use super::support::*;

#[test]
fn complete_task_with_conn_updates_task_and_outbox() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let task_id = "01949c00-0000-7000-8000-000000000044";

    seed_task(&conn, task_id, "Finish CLI action tests", "open");

    complete_task_with_conn(&conn, &tid(task_id)).expect("complete task");

    let (status, completed_at): (String, Option<String>) = conn
        .query_row(
            "SELECT status, completed_at FROM tasks WHERE id = ?1",
            [task_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load completed task");
    assert_eq!(status, "completed");
    assert!(completed_at.is_some());

    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            [ENTITY_TASK, task_id],
            |row| row.get(0),
        )
        .expect("count outbox");
    assert_eq!(outbox_count, 1);

    let seq = read_local_change_seq(&conn).expect("read local seq");
    assert_eq!(seq, 1);
}

#[test]
fn reopen_task_with_conn_updates_task_and_outbox() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let task_id = "01949c00-0000-7000-8000-000000000045";
    let reminder_id = "01949c00-0000-7000-8000-000000000046";

    seed_task(&conn, task_id, "Reopen me", "completed");
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, cancelled_at, version, created_at)
         VALUES (?1, ?2, '2026-05-01T13:00:00Z', '2026-04-30T00:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-30T00:00:00Z')",
        [reminder_id, task_id],
    )
    .expect("seed cancelled reminder");

    reopen_task_with_conn(&conn, &tid(task_id)).expect("reopen task");

    let (status, completed_at): (String, Option<String>) = conn
        .query_row(
            "SELECT status, completed_at FROM tasks WHERE id = ?1",
            [task_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load reopened task");
    assert_eq!(status, "open");
    assert!(completed_at.is_none());
    let reminder_cancelled_at: Option<String> = conn
        .query_row(
            "SELECT cancelled_at FROM task_reminders WHERE id = ?1",
            [reminder_id],
            |row| row.get(0),
        )
        .expect("load reopened reminder");
    assert!(reminder_cancelled_at.is_none());

    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            [ENTITY_TASK, task_id],
            |row| row.get(0),
        )
        .expect("count outbox");
    assert_eq!(outbox_count, 1);

    let reminder_outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            [ENTITY_TASK_REMINDER, reminder_id],
            |row| row.get(0),
        )
        .expect("count reminder outbox");
    assert_eq!(
        reminder_outbox_count, 1,
        "CLI reopen must sync reminder uncancel side effects"
    );
}

#[test]
fn defer_task_with_conn_updates_planned_date_notes_and_outbox() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let task_id = "01949c00-0000-7000-8000-000000000047";

    seed_task(&conn, task_id, "Defer me", "open");

    defer_task_with_conn(
        &conn,
        &tid(task_id),
        Some(3),
        Some("Waiting on response"),
        Some("needs_info"),
    )
    .expect("defer task");

    let (planned_date, ai_notes, defer_count, last_defer_reason): (
        Option<String>,
        Option<String>,
        i64,
        Option<String>,
    ) = conn
        .query_row(
            "SELECT planned_date, ai_notes, defer_count, last_defer_reason FROM tasks WHERE id = ?1",
            [task_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("load deferred task");
    assert!(planned_date.is_some());
    assert_eq!(defer_count, 1);
    assert_eq!(last_defer_reason.as_deref(), Some("needs_info"));
    assert!(ai_notes
        .as_deref()
        .unwrap_or_default()
        .contains("Waiting on response"));

    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            [ENTITY_TASK, task_id],
            |row| row.get(0),
        )
        .expect("count outbox");
    assert_eq!(outbox_count, 1);
}

#[test]
fn defer_task_in_tx_shifts_pending_reminder_and_enqueues_reminder_outbox() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let task_id = "01949c00-0000-7000-8000-000000000048";
    let reminder_id = "01949c00-0000-7000-8000-000000000049";

    seed_task(&conn, task_id, "Defer reminder", "open");
    conn.execute(
        "UPDATE tasks SET planned_date = '2030-04-17', due_date = '2030-04-17'
         WHERE id = ?1",
        [task_id],
    )
    .expect("seed task dates");
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES (?1, ?2, '2030-04-17T13:45:00.000000Z',
                 '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-16T00:00:00Z')",
        [reminder_id, task_id],
    )
    .expect("seed reminder");

    lorvex_store::transaction::with_immediate_transaction(&conn, |conn| {
        defer_task_in_tx(conn, &tid(task_id), None, None, None, Some("2030-04-20"))
    })
    .expect("defer task");

    let reminder_at: String = conn
        .query_row(
            "SELECT reminder_at FROM task_reminders WHERE id = ?1",
            [reminder_id],
            |row| row.get(0),
        )
        .expect("load reminder timestamp");
    assert!(
        reminder_at.starts_with("2030-04-20T13:45:00"),
        "expected reminder to shift +3 days, got {reminder_at}"
    );

    let reminder_outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            [ENTITY_TASK_REMINDER, reminder_id],
            |row| row.get(0),
        )
        .expect("count reminder outbox");
    assert_eq!(reminder_outbox_count, 1);
}
