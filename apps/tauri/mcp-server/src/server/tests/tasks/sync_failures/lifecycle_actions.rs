use super::support::*;

#[test]
#[serial_test::serial(hlc)]
fn complete_task_rolls_back_when_reminder_relation_sync_enqueue_fails() {
    let server = make_server();
    seed_task(
        &server,
        "task-complete-sync-failure",
        "Complete Sync Failure",
        "open",
        None,
        None,
        None,
        0,
    );
    insert_task_reminder(
        &server,
        "reminder-complete-sync-failure",
        "task-complete-sync-failure",
        "2026-04-01T09:00:00Z",
    );
    install_sync_outbox_entity_failure_trigger(
        &server,
        "fail_complete_task_reminder_sync",
        lorvex_domain::naming::ENTITY_TASK_REMINDER,
    );

    let err = server
        .complete_task(Parameters(CompleteTaskArgs {
            id: "task-complete-sync-failure".to_string(),
            idempotency_key: None,
        }))
        .expect_err("completion should fail when relation sync enqueue fails");

    assert_is_tool_error(&err);
    assert_eq!(task_status(&server, "task-complete-sync-failure"), "open");
    assert_eq!(
        reminder_cancelled_at(&server, "reminder-complete-sync-failure"),
        None
    );
}

#[test]
#[serial_test::serial(hlc)]
fn cancel_task_rolls_back_when_reminder_relation_sync_enqueue_fails() {
    let server = make_server();
    seed_task(
        &server,
        "task-cancel-sync-failure",
        "Cancel Sync Failure",
        "open",
        None,
        None,
        None,
        0,
    );
    insert_task_reminder(
        &server,
        "reminder-cancel-sync-failure",
        "task-cancel-sync-failure",
        "2026-04-01T09:00:00Z",
    );
    install_sync_outbox_entity_failure_trigger(
        &server,
        "fail_cancel_task_reminder_sync",
        lorvex_domain::naming::ENTITY_TASK_REMINDER,
    );

    let err = server
        .cancel_task(Parameters(CancelTaskArgs {
            id: "task-cancel-sync-failure".to_string(),
            reason: None,
            cancel_series: None,
            idempotency_key: None,
            dry_run: false,
        }))
        .expect_err("cancel should fail when relation sync enqueue fails");

    assert_is_tool_error(&err);
    assert_eq!(task_status(&server, "task-cancel-sync-failure"), "open");
    assert_eq!(
        reminder_cancelled_at(&server, "reminder-cancel-sync-failure"),
        None
    );
}

#[test]
#[serial_test::serial(hlc)]
fn reopen_task_rolls_back_when_successor_dependency_relation_sync_enqueue_fails() {
    let server = make_server();
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000112",
        "Reopen Sync Failure",
        "open",
        None,
        Some("2026-04-01"),
        None,
        0,
    );
    server
        .with_conn(|conn| {
            conn.execute(
                "UPDATE tasks SET recurrence = ?1, recurrence_group_id = 'group-reopen-sync-failure', canonical_occurrence_date = '2026-04-01' WHERE id = ?2",
                (r#"{"FREQ":"DAILY","INTERVAL":1}"#, "01966a3f-7c8b-7d4e-8f3a-000000000112"),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed recurrence");
    let successor_id = complete_recurring_parent_and_get_successor(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000112",
    );
    seed_task(
        &server,
        "task-reopen-dependency-anchor",
        "Dependency Anchor",
        "open",
        None,
        None,
        None,
        0,
    );
    insert_task_dependency(&server, &successor_id, "task-reopen-dependency-anchor");
    install_sync_outbox_entity_failure_trigger(
        &server,
        "fail_reopen_task_dependency_sync",
        lorvex_domain::naming::EDGE_TASK_DEPENDENCY,
    );

    let err = server
        .reopen_task(Parameters(ReopenTaskArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-000000000112".to_string(),
            idempotency_key: None,
        }))
        .expect_err("reopen should fail when successor dependency relation sync enqueue fails");

    assert_is_tool_error(&err);
    assert_eq!(
        task_status(&server, "01966a3f-7c8b-7d4e-8f3a-000000000112"),
        "completed"
    );
    assert_eq!(task_status(&server, &successor_id), "open");
    assert_eq!(dependency_count_for_task(&server, &successor_id), 1);
}
