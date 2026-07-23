use std::collections::HashSet;

use rusqlite::params;

use super::super::*;
use super::support::*;

#[test]
fn batch_reopen_tasks_with_conn_rejects_empty_input() {
    let conn = test_conn();
    let error =
        batch_reopen_tasks_with_conn(&conn, vec![]).expect_err("empty task_ids should be rejected");
    assert!(matches!(error, AppError::Validation(_)));
}

#[test]
fn batch_reopen_tasks_with_conn_reopens_terminal_and_skips_open() {
    let conn = test_conn();
    let task_done = uid();
    let task_killed = uid();
    let task_open = uid();
    let task_missing = uid();
    seed_task(&conn, &task_done, "Done", "inbox", "completed");
    seed_task(&conn, &task_killed, "Killed", "inbox", "cancelled");
    seed_task(&conn, &task_open, "Open", "inbox", "open");

    let result = batch_reopen_tasks_with_conn(
        &conn,
        vec![
            task_done.clone(),
            task_killed.clone(),
            task_open.clone(),
            task_missing.clone(),
        ],
    )
    .expect("batch_reopen_tasks should succeed");

    assert_eq!(result.reopened_count, 2);
    let reopened_ids: HashSet<&str> = result.reopened.iter().map(|t| t.id.as_str()).collect();
    assert!(reopened_ids.contains(task_done.as_str()));
    assert!(reopened_ids.contains(task_killed.as_str()));
    for task in &result.reopened {
        assert_eq!(task.status, "open");
    }

    // Already-open and missing ids must flow into `skipped`.
    assert!(result.skipped.contains(&task_open));
    assert!(result.skipped.contains(&task_missing));
}

#[test]
fn batch_reopen_tasks_with_conn_enqueues_reopened_reminder_outbox() {
    let conn = test_conn();
    let task_id = uid();
    let reminder_id = uid();
    seed_task(
        &conn,
        &task_id,
        "Cancelled with reminder",
        "inbox",
        "cancelled",
    );
    conn.execute(
        "INSERT INTO task_reminders
            (id, task_id, reminder_at, cancelled_at, version, created_at)
         VALUES
            (?1, ?2, '2030-04-17T13:45:00.000000Z',
             '2026-03-01T00:00:00Z', ?3, '2026-03-01T00:00:00Z')",
        params![reminder_id, task_id, SEED_VERSION],
    )
    .expect("seed cancelled reminder");

    batch_reopen_tasks_with_conn(&conn, vec![task_id]).expect("batch_reopen_tasks should succeed");

    let cancelled_at: Option<String> = conn
        .query_row(
            "SELECT cancelled_at FROM task_reminders WHERE id = ?1",
            params![reminder_id],
            |row| row.get(0),
        )
        .expect("load reminder cancelled_at");
    assert_eq!(cancelled_at, None);

    let reminder_outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            params![ENTITY_TASK_REMINDER, reminder_id],
            |row| row.get(0),
        )
        .expect("count reminder outbox rows");
    assert_eq!(reminder_outbox_count, 1);
}
