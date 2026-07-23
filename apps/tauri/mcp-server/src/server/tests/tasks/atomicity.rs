//! batch task tools that
//! mutate state must reject the whole batch when any subset of the
//! supplied IDs is in a state that should not be re-mutated.
//! Pre-fix the tools silently split into "to-process" and
//! "already-done" subsets and applied to only the former, leaving
//! the assistant unable to distinguish the racing-peer case from
//! the user-error case.
//!
//! Each test seeds a mixed-eligibility set, calls the batch tool,
//! and confirms (a) the call returns an error naming the bad ids,
//! (b) NO row was mutated, (c) the outbox saw zero envelopes from
//! the rejected batch.
//!
//! The router maps `McpError::Validation(_)` to `Result<_, String>`
//! so test-side assertions compare against the rendered string.

use super::*;
use crate::contract::{
    BatchCancelTasksArgs, BatchDeferTasksArgs, BatchMoveTasksArgs, BatchReopenTasksArgs,
};

fn count_outbox_for_tasks(server: &LorvexMcpServer, ids: &[&str]) -> i64 {
    if ids.is_empty() {
        return 0;
    }
    server
        .with_conn(|conn| {
            let placeholders = ids.iter().map(|_| "?").collect::<Vec<_>>().join(",");
            let sql = format!(
                "SELECT COUNT(*) FROM sync_outbox \
                 WHERE entity_type = 'task' AND entity_id IN ({placeholders})"
            );
            let count: i64 = conn
                .query_row(
                    &sql,
                    rusqlite::params_from_iter(ids.iter().map(ToString::to_string)),
                    |row| row.get(0),
                )
                .map_err(crate::system::handler_support::to_error_message)?;
            Ok(count)
        })
        .expect("count outbox")
}

fn task_status(server: &LorvexMcpServer, id: &str) -> String {
    server
        .with_conn(|conn| {
            let status: String = conn
                .query_row("SELECT status FROM tasks WHERE id = ?1", [id], |row| {
                    row.get(0)
                })
                .map_err(crate::system::handler_support::to_error_message)?;
            Ok(status)
        })
        .expect("read status")
}

/// pin the documented contract that `cancel_series`
/// is a no-op for non-recurring tasks. A mixed batch — one recurring,
/// one not — must end with both rows cancelled exactly once and the
/// recurring task's series cleared (no successor spawned).
#[test]
#[serial_test::serial(hlc)]
fn batch_cancel_mixed_recurring_and_non_recurring_respects_cancel_series() {
    let server = make_server();
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000801",
        "Recurring",
        "open",
        None,
        Some("2026-04-01"),
        None,
        0,
    );
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000802",
        "Non-recurring",
        "open",
        None,
        None,
        None,
        0,
    );
    server
        .with_conn(|conn| {
            conn.execute(
                "UPDATE tasks SET recurrence = ?1, recurrence_group_id = 'mixed-grp', canonical_occurrence_date = '2026-04-01' WHERE id = ?2",
                rusqlite::params![r#"{"FREQ":"DAILY","INTERVAL":1}"#, "01966a3f-7c8b-7d4e-8f3a-000000000801"],
            )
            .map_err(crate::system::handler_support::to_error_message)?;
            Ok(())
        })
        .expect("seed recurrence on 01966a3f-7c8b-7d4e-8f3a-000000000801");

    let response = server
        .batch_cancel_tasks(Parameters(BatchCancelTasksArgs {
            task_ids: vec![
                "01966a3f-7c8b-7d4e-8f3a-000000000801".to_string(),
                "01966a3f-7c8b-7d4e-8f3a-000000000802".to_string(),
            ],
            reason: Some("M22 mixed-batch contract".to_string()),
            cancel_series: Some(true),
            dry_run: false,
            idempotency_key: None,
        }))
        .expect("mixed batch with cancel_series=true should succeed");

    let parsed: Value = serde_json::from_str(&response).expect("parse batch_cancel_tasks response");
    assert_eq!(
        parsed["cancelled_count"].as_u64(),
        Some(2),
        "both tasks must be cancelled exactly once"
    );
    let next_occurrences = parsed["next_occurrences"]
        .as_array()
        .expect("next_occurrences array");
    assert!(
        next_occurrences.is_empty(),
        "cancel_series=true must not spawn a successor for the recurring task: {next_occurrences:?}"
    );
    assert_eq!(
        task_status(&server, "01966a3f-7c8b-7d4e-8f3a-000000000801"),
        "cancelled"
    );
    assert_eq!(
        task_status(&server, "01966a3f-7c8b-7d4e-8f3a-000000000802"),
        "cancelled"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn batch_cancel_tasks_rejects_whole_batch_when_any_id_is_already_terminal() {
    let server = make_server();
    seed_task(
        &server,
        "task-a-open",
        "Open A",
        "open",
        None,
        None,
        None,
        0,
    );
    seed_task(
        &server,
        "task-b-completed",
        "Completed B",
        "completed",
        None,
        None,
        None,
        0,
    );
    seed_task(
        &server,
        "task-c-open",
        "Open C",
        "open",
        None,
        None,
        None,
        0,
    );
    let baseline_outbox =
        count_outbox_for_tasks(&server, &["task-a-open", "task-b-completed", "task-c-open"]);

    let err = server
        .batch_cancel_tasks(Parameters(BatchCancelTasksArgs {
            task_ids: vec![
                "task-a-open".to_string(),
                "task-b-completed".to_string(),
                "task-c-open".to_string(),
            ],
            reason: Some("planned cleanup".to_string()),
            cancel_series: None,
            dry_run: false,
            idempotency_key: None,
        }))
        .expect_err("mixed-eligibility batch must be rejected wholesale");

    assert!(
        err.contains("rejects partial application"),
        "expected partial-rejection diagnostic, got: {err}"
    );
    assert!(
        err.contains("task-b-completed"),
        "diagnostic should name the offending id, got: {err}"
    );

    // Atomicity: no eligible task was cancelled.
    assert_eq!(task_status(&server, "task-a-open"), "open");
    assert_eq!(task_status(&server, "task-c-open"), "open");
    assert_eq!(task_status(&server, "task-b-completed"), "completed");

    // No outbox envelope was enqueued for any task in the batch.
    let after_outbox =
        count_outbox_for_tasks(&server, &["task-a-open", "task-b-completed", "task-c-open"]);
    assert_eq!(
        after_outbox, baseline_outbox,
        "rejected batch must not enqueue any outbox envelope"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn batch_defer_tasks_rejects_whole_batch_when_any_id_is_terminal() {
    let server = make_server();
    seed_task(
        &server,
        "task-d-open",
        "Open D",
        "open",
        None,
        None,
        None,
        0,
    );
    seed_task(
        &server,
        "task-e-cancelled",
        "Cancelled E",
        "cancelled",
        None,
        None,
        None,
        0,
    );
    let baseline_outbox = count_outbox_for_tasks(&server, &["task-d-open", "task-e-cancelled"]);

    let err = server
        .batch_defer_tasks(Parameters(BatchDeferTasksArgs {
            task_ids: vec!["task-d-open".to_string(), "task-e-cancelled".to_string()],
            until_date: "2026-12-01".to_string(),
            reason: None,
            structured_reason: None,
            idempotency_key: None,
        }))
        .expect_err("mixed-eligibility batch must be rejected wholesale");

    assert!(
        err.contains("rejects partial application"),
        "expected partial-rejection diagnostic, got: {err}"
    );
    assert!(
        err.contains("task-e-cancelled"),
        "diagnostic should name the offending id, got: {err}"
    );

    // Atomicity: the eligible task was not deferred.
    let due_d: Option<String> = server
        .with_conn(|conn| {
            let row: Option<String> = conn
                .query_row(
                    "SELECT due_date FROM tasks WHERE id = 'task-d-open'",
                    [],
                    |r| r.get(0),
                )
                .map_err(crate::system::handler_support::to_error_message)?;
            Ok(row)
        })
        .expect("read due_date");
    assert!(
        due_d.is_none(),
        "rejected batch must not have written the new due_date"
    );

    let after_outbox = count_outbox_for_tasks(&server, &["task-d-open", "task-e-cancelled"]);
    assert_eq!(after_outbox, baseline_outbox);
}

#[test]
#[serial_test::serial(hlc)]
fn batch_defer_tasks_shifts_pending_reminder_and_enqueues_reminder_outbox() {
    let server = make_server();
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000802",
        "Batch reminder defer",
        "open",
        None,
        Some("2030-04-17"),
        None,
        0,
    );
    server
        .with_conn(|conn| {
            conn.execute(
                "UPDATE tasks SET planned_date = '2030-04-17'
                 WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000802'",
                [],
            )
            .map_err(crate::system::handler_support::to_error_message)?;
            conn.execute(
                "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
                 VALUES ('01966a3f-7c8b-7d4e-8f3a-000000000803', '01966a3f-7c8b-7d4e-8f3a-000000000802',
                         '2030-04-17T13:45:00.000000Z',
                         '0000000000000_0000_0000000000000000',
                         '2026-03-01T00:00:00Z')",
                [],
            )
            .map_err(crate::system::handler_support::to_error_message)?;
            Ok(())
        })
        .expect("seed reminder");

    server
        .batch_defer_tasks(Parameters(BatchDeferTasksArgs {
            task_ids: vec!["01966a3f-7c8b-7d4e-8f3a-000000000802".to_string()],
            until_date: "2030-04-20".to_string(),
            reason: None,
            structured_reason: None,
            idempotency_key: None,
        }))
        .expect("batch defer task");

    let (reminder_at, reminder_outbox_count): (String, i64) = server
        .with_conn(|conn| {
            let reminder_at: String = conn
                .query_row(
                    "SELECT reminder_at FROM task_reminders WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000803'",
                    [],
                    |row| row.get(0),
                )
                .map_err(crate::system::handler_support::to_error_message)?;
            let reminder_outbox_count: i64 = conn
                .query_row(
                    "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
                    rusqlite::params![
                        lorvex_domain::naming::ENTITY_TASK_REMINDER,
                        "01966a3f-7c8b-7d4e-8f3a-000000000803"
                    ],
                    |row| row.get(0),
                )
                .map_err(crate::system::handler_support::to_error_message)?;
            Ok((reminder_at, reminder_outbox_count))
        })
        .expect("read reminder state");

    assert!(
        reminder_at.starts_with("2030-04-20T13:45:00"),
        "expected reminder to shift +3 days, got {reminder_at}"
    );
    assert_eq!(reminder_outbox_count, 1);
}

#[test]
#[serial_test::serial(hlc)]
fn batch_defer_tasks_rejects_stale_version_without_side_effects() {
    let server = make_server();
    seed_task(
        &server,
        "task-stale-batch-defer",
        "Stale Batch Defer",
        "open",
        None,
        Some("2030-04-17"),
        None,
        0,
    );
    server
        .with_conn(|conn| {
            conn.execute(
                "UPDATE tasks SET planned_date = '2030-04-17',
                    version = '9999999999999_0000_ffffffffffffffff'
                 WHERE id = 'task-stale-batch-defer'",
                [],
            )
            .map_err(crate::system::handler_support::to_error_message)?;
            Ok(())
        })
        .expect("force stale task version");
    let baseline_outbox = count_outbox_for_tasks(&server, &["task-stale-batch-defer"]);

    let err = server
        .batch_defer_tasks(Parameters(BatchDeferTasksArgs {
            task_ids: vec!["task-stale-batch-defer".to_string()],
            until_date: "2030-04-20".to_string(),
            reason: Some("should not apply".to_string()),
            structured_reason: None,
            idempotency_key: None,
        }))
        .expect_err("stale-version batch defer must be rejected");

    assert!(
        err.contains("stale version") || err.contains("sync_conflict"),
        "expected stale-version diagnostic, got: {err}"
    );

    let (planned_date, defer_count, ai_notes): (Option<String>, i64, Option<String>) = server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT planned_date, defer_count, ai_notes \
                 FROM tasks WHERE id = 'task-stale-batch-defer'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .map_err(crate::system::handler_support::to_error_message)
        })
        .expect("read task after stale batch defer");
    assert_eq!(planned_date.as_deref(), Some("2030-04-17"));
    assert_eq!(defer_count, 0);
    assert!(ai_notes.is_none());

    let after_outbox = count_outbox_for_tasks(&server, &["task-stale-batch-defer"]);
    assert_eq!(after_outbox, baseline_outbox);
}

#[test]
#[serial_test::serial(hlc)]
fn batch_move_tasks_rejects_stale_version_without_side_effects() {
    let server = make_server();
    seed_list(&server, "target-list-stale-move");
    seed_task(
        &server,
        "task-stale-batch-move",
        "Stale Batch Move",
        "open",
        None,
        None,
        None,
        0,
    );
    let stale_barrier = "9999999999999_0000_ffffffffffffffff";
    server
        .with_conn(|conn| {
            conn.execute(
                "UPDATE tasks SET version = ?1 WHERE id = 'task-stale-batch-move'",
                [stale_barrier],
            )
            .map_err(crate::system::handler_support::to_error_message)?;
            Ok(())
        })
        .expect("force stale task version");
    let baseline_outbox = count_outbox_for_tasks(&server, &["task-stale-batch-move"]);

    let err = server
        .batch_move_tasks(Parameters(BatchMoveTasksArgs {
            task_ids: vec!["task-stale-batch-move".to_string()],
            list_id: "target-list-stale-move".to_string(),
            idempotency_key: None,
        }))
        .expect_err("stale-version batch move must be rejected");

    assert!(
        err.contains("stale version") || err.contains("sync_conflict"),
        "expected stale-version diagnostic, got: {err}"
    );

    let (list_id, version): (String, String) = server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT list_id, version FROM tasks WHERE id = 'task-stale-batch-move'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .map_err(crate::system::handler_support::to_error_message)
        })
        .expect("read task after stale batch move");
    assert_eq!(list_id, "inbox");
    assert_eq!(version, stale_barrier);

    let after_outbox = count_outbox_for_tasks(&server, &["task-stale-batch-move"]);
    assert_eq!(after_outbox, baseline_outbox);
}

#[test]
#[serial_test::serial(hlc)]
fn batch_move_tasks_skips_cancelled_tasks_without_resurrecting_tombstones() {
    let server = make_server();
    seed_list(&server, "target-list-cancelled-move");
    let task_id = "0196c771-1111-7111-8111-111111114301";
    seed_task(
        &server,
        task_id,
        "Cancelled Batch Move",
        "cancelled",
        None,
        None,
        None,
        0,
    );
    let baseline_outbox = count_outbox_for_tasks(&server, &[task_id]);

    let response = server
        .batch_move_tasks(Parameters(BatchMoveTasksArgs {
            task_ids: vec![task_id.to_string()],
            list_id: "target-list-cancelled-move".to_string(),
            idempotency_key: None,
        }))
        .expect("cancelled batch move should skip instead of mutating");
    let parsed: Value = serde_json::from_str(&response).expect("parse batch_move_tasks response");
    assert_eq!(parsed["moved_count"].as_u64(), Some(0));
    assert_eq!(parsed["skipped"], serde_json::json!([task_id]));
    assert_eq!(parsed["tasks"], serde_json::json!([]));

    let (list_id, status): (String, String) = server
        .with_conn(|conn| {
            conn.query_row(
                "SELECT list_id, status FROM tasks WHERE id = ?1",
                [task_id],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .map_err(crate::system::handler_support::to_error_message)
        })
        .expect("read cancelled task after skipped move");
    assert_eq!(list_id, "inbox");
    assert_eq!(status, "cancelled");

    let after_outbox = count_outbox_for_tasks(&server, &[task_id]);
    assert_eq!(after_outbox, baseline_outbox);
}

#[test]
#[serial_test::serial(hlc)]
fn batch_move_tasks_moves_live_tasks_while_reporting_cancelled_skips() {
    let server = make_server();
    seed_list(&server, "target-list-mixed-move");
    let live_task_id = "0196c771-3333-7333-8333-333333334301";
    let cancelled_task_id = "0196c771-4444-7444-8444-444444444301";
    seed_task(
        &server,
        live_task_id,
        "Live Batch Move",
        "open",
        None,
        None,
        None,
        0,
    );
    seed_task(
        &server,
        cancelled_task_id,
        "Cancelled Batch Move",
        "cancelled",
        None,
        None,
        None,
        0,
    );
    let cancelled_baseline_outbox = count_outbox_for_tasks(&server, &[cancelled_task_id]);

    let response = server
        .batch_move_tasks(Parameters(BatchMoveTasksArgs {
            task_ids: vec![live_task_id.to_string(), cancelled_task_id.to_string()],
            list_id: "target-list-mixed-move".to_string(),
            idempotency_key: None,
        }))
        .expect("mixed batch move should move live tasks and report cancelled skips");
    let parsed: Value = serde_json::from_str(&response).expect("parse mixed batch_move response");
    assert_eq!(parsed["moved_count"].as_u64(), Some(1));
    assert_eq!(parsed["skipped"], serde_json::json!([cancelled_task_id]));
    assert_eq!(parsed["tasks"][0]["id"].as_str(), Some(live_task_id));
    assert_eq!(
        parsed["tasks"][0]["list_id"].as_str(),
        Some("target-list-mixed-move")
    );

    let (live_list_id, cancelled_list_id, cancelled_status): (String, String, String) = server
        .with_conn(|conn| {
            let live_list_id: String = conn
                .query_row(
                    "SELECT list_id FROM tasks WHERE id = ?1",
                    [live_task_id],
                    |row| row.get(0),
                )
                .map_err(crate::system::handler_support::to_error_message)?;
            let (cancelled_list_id, cancelled_status): (String, String) = conn
                .query_row(
                    "SELECT list_id, status FROM tasks WHERE id = ?1",
                    [cancelled_task_id],
                    |row| Ok((row.get(0)?, row.get(1)?)),
                )
                .map_err(crate::system::handler_support::to_error_message)?;
            Ok((live_list_id, cancelled_list_id, cancelled_status))
        })
        .expect("read tasks after mixed move");
    assert_eq!(live_list_id, "target-list-mixed-move");
    assert_eq!(cancelled_list_id, "inbox");
    assert_eq!(cancelled_status, "cancelled");
    assert_eq!(
        count_outbox_for_tasks(&server, &[cancelled_task_id]),
        cancelled_baseline_outbox
    );
}

#[test]
#[serial_test::serial(hlc)]
fn batch_reopen_tasks_rejects_whole_batch_when_any_id_is_already_open() {
    let server = make_server();
    seed_task(
        &server,
        "task-f-completed",
        "Completed F",
        "completed",
        None,
        None,
        None,
        0,
    );
    seed_task(
        &server,
        "task-g-open",
        "Open G (already reopen target)",
        "open",
        None,
        None,
        None,
        0,
    );
    let baseline_outbox = count_outbox_for_tasks(&server, &["task-f-completed", "task-g-open"]);

    let err = server
        .batch_reopen_tasks(Parameters(BatchReopenTasksArgs {
            task_ids: vec!["task-f-completed".to_string(), "task-g-open".to_string()],
            idempotency_key: None,
        }))
        .expect_err("mixed-eligibility reopen batch must be rejected wholesale");

    assert!(
        err.contains("rejects partial application"),
        "expected partial-rejection diagnostic, got: {err}"
    );
    assert!(
        err.contains("task-g-open"),
        "diagnostic should name the already-open id, got: {err}"
    );

    // Atomicity: the eligible completed task was not reopened.
    assert_eq!(task_status(&server, "task-f-completed"), "completed");
    assert_eq!(task_status(&server, "task-g-open"), "open");

    let after_outbox = count_outbox_for_tasks(&server, &["task-f-completed", "task-g-open"]);
    assert_eq!(after_outbox, baseline_outbox);
}

#[test]
#[serial_test::serial(hlc)]
fn batch_reopen_tasks_enqueues_reopened_reminder_outbox() {
    let server = make_server();
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000804",
        "Reopen Reminder",
        "cancelled",
        None,
        None,
        None,
        0,
    );
    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO task_reminders
                   (id, task_id, reminder_at, cancelled_at, version, created_at)
                 VALUES
                   ('01966a3f-7c8b-7d4e-8f3a-000000000805', '01966a3f-7c8b-7d4e-8f3a-000000000804',
                    '2030-04-17T13:45:00.000000Z',
                    '2026-03-01T00:00:00Z',
                    '0000000000000_0000_0000000000000000',
                    '2026-03-01T00:00:00Z')",
                [],
            )
            .map_err(crate::system::handler_support::to_error_message)?;
            Ok(())
        })
        .expect("seed cancelled reminder");

    server
        .batch_reopen_tasks(Parameters(BatchReopenTasksArgs {
            task_ids: vec!["01966a3f-7c8b-7d4e-8f3a-000000000804".to_string()],
            idempotency_key: None,
        }))
        .expect("batch reopen task");

    let (cancelled_at, reminder_outbox_count): (Option<String>, i64) = server
        .with_conn(|conn| {
            let cancelled_at: Option<String> = conn
                .query_row(
                    "SELECT cancelled_at FROM task_reminders WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000805'",
                    [],
                    |row| row.get(0),
                )
                .map_err(crate::system::handler_support::to_error_message)?;
            let reminder_outbox_count: i64 = conn
                .query_row(
                    "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
                    rusqlite::params![
                        lorvex_domain::naming::ENTITY_TASK_REMINDER,
                        "01966a3f-7c8b-7d4e-8f3a-000000000805"
                    ],
                    |row| row.get(0),
                )
                .map_err(crate::system::handler_support::to_error_message)?;
            Ok((cancelled_at, reminder_outbox_count))
        })
        .expect("read reminder state");

    assert_eq!(cancelled_at, None);
    assert_eq!(reminder_outbox_count, 1);
}
