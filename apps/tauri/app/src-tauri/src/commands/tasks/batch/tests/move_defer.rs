use rusqlite::params;

use super::super::*;
use super::support::*;

#[test]
fn batch_move_tasks_with_conn_requires_target_list_id() {
    let conn = test_conn();
    let task_a = uid();
    seed_task(&conn, &task_a, "Task 1", "inbox", "open");

    let error = batch_move_tasks_with_conn(&conn, vec![task_a], None)
        .expect_err("missing target_list_id should be rejected");
    match error {
        AppError::Validation(message) => {
            assert!(message.contains("list"), "unexpected: {message}");
        }
        other => panic!("expected Validation, got {other:?}"),
    }
}

/// `target_list_id` is now UUID-shape-validated
/// before the writer transaction opens. A non-UUID list id would
/// otherwise bind to `tasks.list_id` and only surface as an FK
/// existence mismatch downstream.
#[test]
fn batch_move_tasks_with_conn_rejects_non_uuid_target_list_id() {
    let conn = test_conn();
    let task_a = uid();
    seed_task(&conn, &task_a, "Task 1", "inbox", "open");

    let error = batch_move_tasks_with_conn(&conn, vec![task_a], Some("not-a-uuid".into()))
        .expect_err("non-UUID target_list_id must be rejected");
    match error {
        AppError::Validation(message) => assert!(
            message.contains("target_list_id"),
            "expected target_list_id-tagged error, got: {message}"
        ),
        other => panic!("expected Validation, got {other:?}"),
    }
}

#[test]
fn batch_move_tasks_with_conn_moves_open_tasks_and_skips_cancelled_and_missing() {
    let conn = test_conn();
    let list_dest = uid();
    let task_open = uid();
    let task_cancelled = uid();
    let task_no_op = uid();
    let task_missing = uid();
    seed_list(&conn, &list_dest, "Destination");
    seed_task(&conn, &task_open, "Open task", "inbox", "open");
    seed_task(&conn, &task_cancelled, "Cancelled", "inbox", "cancelled");
    seed_task(&conn, &task_no_op, "Already here", &list_dest, "open");

    let result = batch_move_tasks_with_conn(
        &conn,
        vec![
            task_open.clone(),
            task_cancelled.clone(),
            task_no_op.clone(),
            task_missing.clone(),
        ],
        Some(list_dest.clone()),
    )
    .expect("batch_move_tasks should succeed");

    assert_eq!(result.moved_count, 1);
    assert_eq!(result.moved.len(), 1);
    assert_eq!(result.moved[0].id, task_open);
    assert_eq!(result.moved[0].list_id, list_dest);

    // skipped carries the non-moved ids.
    assert!(result.skipped.contains(&task_cancelled));
    assert!(result.skipped.contains(&task_no_op));
    assert!(result.skipped.contains(&task_missing));

    // DB state: the moved task is now in list_dest.
    let list_id: String = conn
        .query_row(
            "SELECT list_id FROM tasks WHERE id = ?1",
            params![task_open],
            |row| row.get(0),
        )
        .expect("load moved task list_id");
    assert_eq!(list_id, list_dest);

    // Cancelled task must NOT have been resurrected / moved.
    let cancelled_list: String = conn
        .query_row(
            "SELECT list_id FROM tasks WHERE id = ?1",
            params![task_cancelled],
            |row| row.get(0),
        )
        .expect("load cancelled task list_id");
    assert_eq!(cancelled_list, "inbox");
}

#[test]
fn batch_defer_tasks_with_conn_rejects_invalid_structured_reason() {
    let conn = test_conn();
    let task_a = uid();
    seed_task(&conn, &task_a, "Task 1", "inbox", "open");

    let error = batch_defer_tasks_with_conn(
        &conn,
        vec![task_a],
        "2026-05-01".into(),
        Some("bogus-reason".into()),
    )
    .expect_err("invalid defer reason should be rejected");

    match error {
        AppError::Validation(message) => {
            assert!(
                message.contains("Invalid defer reason"),
                "unexpected: {message}"
            );
        }
        other => panic!("expected Validation, got {other:?}"),
    }
}

#[test]
fn batch_defer_tasks_with_conn_rejects_malformed_until_date() {
    let conn = test_conn();
    let task_a = uid();
    seed_task(&conn, &task_a, "Task 1", "inbox", "open");

    let error = batch_defer_tasks_with_conn(&conn, vec![task_a.clone()], "not-a-date".into(), None)
        .expect_err("malformed until_date should be rejected");

    // The malformed date flows through
    // `normalize_date_input_for_conn`, which surfaces the failure
    // somewhere in the Validation / Sql error hierarchy. Both
    // shapes are a safe negative signal — we just need to confirm
    // the call did NOT silently succeed with garbage on disk.
    let message = error.to_string();
    assert!(
        !message.is_empty(),
        "error message must be populated for malformed until_date"
    );

    // DB state: no deferred row should have been written.
    let planned: Option<String> = conn
        .query_row(
            "SELECT planned_date FROM tasks WHERE id = ?1",
            params![task_a],
            |row| row.get(0),
        )
        .expect("load planned_date");
    assert!(planned.is_none(), "malformed batch must roll back");
}

#[test]
fn batch_defer_tasks_with_conn_defers_open_tasks_and_skips_terminal_tasks() {
    let conn = test_conn();
    let task_open = uid();
    let task_completed = uid();
    seed_task(&conn, &task_open, "Open", "inbox", "open");
    seed_task(&conn, &task_completed, "Completed", "inbox", "completed");

    let result = batch_defer_tasks_with_conn(
        &conn,
        vec![task_open.clone(), task_completed.clone()],
        "2026-05-01".into(),
        None,
    )
    .expect("batch_defer_tasks should succeed");

    assert_eq!(result.deferred_count, 1);
    assert_eq!(result.deferred[0].id, task_open);
    assert_eq!(
        result.deferred[0].planned_date.as_deref(),
        Some("2026-05-01")
    );
    assert!(result.skipped.contains(&task_completed));

    // A sync_outbox row must have been enqueued for the deferred task.
    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?1",
            params![task_open],
            |row| row.get(0),
        )
        .expect("count outbox rows");
    assert!(outbox_count >= 1);
}

#[test]
fn batch_defer_tasks_with_conn_shifts_pending_reminder_and_enqueues_outbox() {
    let conn = test_conn();
    let task_id = uid();
    let reminder_id = uid();
    seed_task(&conn, &task_id, "Open with reminder", "inbox", "open");
    conn.execute(
        "UPDATE tasks SET planned_date = '2030-04-17', due_date = '2030-04-17'
         WHERE id = ?1",
        params![task_id],
    )
    .expect("seed task dates");
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES (?1, ?2, '2030-04-17T13:45:00.000000Z', ?3, '2026-04-01T08:00:00Z')",
        params![reminder_id, task_id, SEED_VERSION],
    )
    .expect("seed reminder");

    let result = batch_defer_tasks_with_conn(&conn, vec![task_id], "2030-04-20".to_string(), None)
        .expect("batch defer task");

    assert_eq!(result.deferred_count, 1);
    let reminder_at: String = conn
        .query_row(
            "SELECT reminder_at FROM task_reminders WHERE id = ?1",
            params![reminder_id],
            |row| row.get(0),
        )
        .expect("load shifted reminder");
    assert!(
        reminder_at.starts_with("2030-04-20T13:45:00"),
        "expected reminder to shift +3 days, got {reminder_at}"
    );

    let reminder_outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            params![ENTITY_TASK_REMINDER, reminder_id],
            |row| row.get(0),
        )
        .expect("count reminder outbox rows");
    assert_eq!(reminder_outbox_count, 1);
}

#[test]
fn batch_defer_tasks_with_conn_rejects_stale_version_without_side_effects() {
    let conn = test_conn();
    let task_id = uid();
    seed_task(&conn, &task_id, "Stale Defer", "inbox", "open");
    conn.execute(
        "UPDATE tasks SET planned_date = '2030-04-17', due_date = '2030-04-17',
            version = '9999999999999_0000_ffffffffffffffff'
         WHERE id = ?1",
        params![task_id],
    )
    .expect("force stale-loser task version");
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES (?1, ?2, '2030-04-17T13:45:00.000000Z', ?3, '2026-04-01T08:00:00Z')",
        params![uid(), task_id, SEED_VERSION],
    )
    .expect("seed reminder");

    let error =
        batch_defer_tasks_with_conn(&conn, vec![task_id.clone()], "2030-04-20".to_string(), None)
            .expect_err("stale batch defer must reject");
    match error {
        AppError::Store(boxed) => match *boxed {
            lorvex_store::StoreError::StaleVersion { entity, id } => {
                assert_eq!(entity, "task");
                assert_eq!(id, task_id);
            }
            other => panic!("expected task StaleVersion, got {other:?}"),
        },
        other => panic!("expected task StaleVersion, got {other:?}"),
    }

    let (planned_date, defer_count): (Option<String>, i64) = conn
        .query_row(
            "SELECT planned_date, defer_count FROM tasks WHERE id = ?1",
            params![task_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load task after stale defer");
    assert_eq!(planned_date.as_deref(), Some("2030-04-17"));
    assert_eq!(defer_count, 0);

    let reminder_at: String = conn
        .query_row(
            "SELECT reminder_at FROM task_reminders WHERE task_id = ?1",
            params![task_id],
            |row| row.get(0),
        )
        .expect("load reminder after stale defer");
    assert_eq!(
        reminder_at, "2030-04-17T13:45:00.000000Z",
        "stale batch defer must not shift reminders"
    );

    let outbox_rows: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?1",
            params![task_id],
            |row| row.get(0),
        )
        .expect("count outbox rows");
    assert_eq!(outbox_rows, 0);
}

#[test]
fn batch_move_tasks_with_conn_rejects_empty_task_ids() {
    let conn = test_conn();
    let error = batch_move_tasks_with_conn(&conn, vec![], Some(uid()))
        .expect_err("empty task_ids should be rejected");
    assert!(matches!(error, AppError::Validation(_)));
}

// ──────────────────────────────────────────────────────────────────
// `batch_cancel_tasks` must emit one undo token per
// successfully cancelled task so the UI can retract a bulk cancel
// — including recurrence-successor spawn — via
// `undo_task_lifecycle_batch`. Previously the result carried no
// tokens, silently dropping undo for series-cancel.
// ──────────────────────────────────────────────────────────────────
