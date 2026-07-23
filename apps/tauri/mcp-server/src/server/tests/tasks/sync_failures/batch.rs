use super::support::*;
use lorvex_domain::Patch;

#[test]
#[serial_test::serial(hlc)]
fn batch_create_tasks_rolls_back_when_precompleted_reminder_relation_sync_enqueue_fails() {
    let server = make_server();
    install_sync_outbox_entity_failure_trigger(
        &server,
        "fail_batch_create_task_reminder_sync",
        lorvex_domain::naming::ENTITY_TASK_REMINDER,
    );

    let err = server
        .batch_create_tasks(Parameters(BatchCreateTasksArgs {
            idempotency_key: None,
            include_advice: None,
            tasks: vec![BatchCreateTaskInput {
                title: "Batch Create Sync Failure".to_string(),
                list_id: None,
                priority: None,
                due_date: None,
                due_time: None,
                estimated_minutes: None,
                tags: None,
                body: None,
                raw_input: None,
                ai_notes: None,
                depends_on: None,
                reminders: Some(vec!["2026-04-01T09:00:00Z".to_string()]),
                recurrence: None,
                planned_date: None,
                completed: Some(true),
            }],
            dry_run: false,
        }))
        .expect_err("pre-completed batch create should fail when relation sync enqueue fails");

    assert_is_tool_error(&err);
    assert_eq!(task_count(&server), 0);
    assert_eq!(reminder_count(&server), 0);
}

#[test]
#[serial_test::serial(hlc)]
fn batch_create_tasks_rolls_back_when_spawned_successor_reload_fails() {
    let server = make_server();
    install_spawned_successor_delete_trigger(&server, "delete_batch_create_spawned_successor");

    let err = server
        .batch_create_tasks(Parameters(BatchCreateTasksArgs {
            idempotency_key: None,
            include_advice: None,
            tasks: vec![BatchCreateTaskInput {
                title: "Batch Create Successor Reload Failure".to_string(),
                list_id: None,
                priority: None,
                due_date: Some("2026-04-01".to_string()),
                due_time: None,
                estimated_minutes: None,
                tags: None,
                body: None,
                raw_input: None,
                ai_notes: None,
                depends_on: None,
                reminders: None,
                recurrence: Some(crate::contract::RecurrenceRuleArgs {
                    freq: crate::contract::RecurrenceFreq::Daily,
                    interval: Some(1),
                    byday: None,
                    bymonth: None,
                    bymonthday: None,
                    bysetpos: None,
                    wkst: None,
                    until: None,
                    count: None,
                }),
                planned_date: None,
                completed: Some(true),
            }],
            dry_run: false,
        }))
        .expect_err("pre-completed batch create should fail when spawned successor reload fails");

    assert_is_tool_error(&err);
    assert_eq!(task_count(&server), 0);
}

#[test]
#[serial_test::serial(hlc)]
fn batch_update_tasks_rolls_back_when_status_relation_sync_enqueue_fails() {
    let server = make_server();
    seed_task(
        &server,
        "task-batch-update-sync-failure",
        "Batch Update Sync Failure",
        "open",
        None,
        None,
        None,
        0,
    );
    insert_task_reminder(
        &server,
        "reminder-batch-update-sync-failure",
        "task-batch-update-sync-failure",
        "2026-04-01T09:00:00Z",
    );
    install_sync_outbox_entity_failure_trigger(
        &server,
        "fail_batch_update_task_reminder_sync",
        lorvex_domain::naming::ENTITY_TASK_REMINDER,
    );

    let err = server
        .batch_update_tasks(Parameters(BatchUpdateTasksArgs {
            updates: vec![BatchUpdateTaskPatch {
                id: "task-batch-update-sync-failure".to_string(),
                title: None,
                body: Patch::Unset,
                raw_input: None,
                ai_notes: Patch::Unset,
                status: Some(TaskStatusValue::Completed),
                list_id: None,
                tags_set: None,
                tags_add: None,
                tags_remove: None,
                priority: None,
                due_date: Patch::Unset,
                due_time: Patch::Unset,
                estimated_minutes: Patch::Unset,
                recurrence: Patch::Unset,
                depends_on: None,
                depends_on_add: None,
                depends_on_remove: None,
                planned_date: Patch::Unset,
            }],
            dry_run: false,
        }))
        .expect_err("batch status update should fail when relation sync enqueue fails");

    assert_is_tool_error(&err);
    assert_eq!(
        task_status(&server, "task-batch-update-sync-failure"),
        "open"
    );
    assert_eq!(
        reminder_cancelled_at(&server, "reminder-batch-update-sync-failure"),
        None
    );
}

#[test]
#[serial_test::serial(hlc)]
fn batch_complete_tasks_rolls_back_when_spawned_successor_reload_fails() {
    let server = make_server();
    seed_task(
        &server,
        "task-batch-complete-successor-reload-failure",
        "Batch Complete Successor Reload Failure",
        "open",
        None,
        Some("2026-04-01"),
        None,
        0,
    );
    server
        .with_conn(|conn| {
            conn.execute(
                "UPDATE tasks SET recurrence = ?1, recurrence_group_id = 'group-batch-complete-successor-reload-failure', canonical_occurrence_date = '2026-04-01' WHERE id = ?2",
                (r#"{"FREQ":"DAILY","INTERVAL":1}"#, "task-batch-complete-successor-reload-failure"),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed recurrence");
    install_spawned_successor_delete_trigger(&server, "delete_batch_complete_spawned_successor");

    let err = server
        .batch_complete_tasks(Parameters(BatchCompleteTasksArgs {
            task_ids: vec!["task-batch-complete-successor-reload-failure".to_string()],
            idempotency_key: None,
        }))
        .expect_err("batch completion should fail when spawned successor reload fails");

    assert_is_tool_error(&err);
    assert_eq!(
        task_status(&server, "task-batch-complete-successor-reload-failure"),
        "open"
    );
    assert_eq!(task_count(&server), 1);
}

#[test]
#[serial_test::serial(hlc)]
fn batch_complete_tasks_rolls_back_when_reminder_relation_sync_enqueue_fails() {
    let server = make_server();
    seed_task(
        &server,
        "task-batch-complete-sync-failure",
        "Batch Complete Sync Failure",
        "open",
        None,
        None,
        None,
        0,
    );
    insert_task_reminder(
        &server,
        "reminder-batch-complete-sync-failure",
        "task-batch-complete-sync-failure",
        "2026-04-01T09:00:00Z",
    );
    install_sync_outbox_entity_failure_trigger(
        &server,
        "fail_batch_complete_task_reminder_sync",
        lorvex_domain::naming::ENTITY_TASK_REMINDER,
    );

    let err = server
        .batch_complete_tasks(Parameters(BatchCompleteTasksArgs {
            task_ids: vec!["task-batch-complete-sync-failure".to_string()],
            idempotency_key: None,
        }))
        .expect_err("batch completion should fail when relation sync enqueue fails");

    assert_is_tool_error(&err);
    assert_eq!(
        task_status(&server, "task-batch-complete-sync-failure"),
        "open"
    );
    assert_eq!(
        reminder_cancelled_at(&server, "reminder-batch-complete-sync-failure"),
        None
    );
}

#[test]
#[serial_test::serial(hlc)]
fn batch_cancel_tasks_rolls_back_when_reminder_relation_sync_enqueue_fails() {
    let server = make_server();
    seed_task(
        &server,
        "task-batch-cancel-sync-failure",
        "Batch Cancel Sync Failure",
        "open",
        None,
        None,
        None,
        0,
    );
    insert_task_reminder(
        &server,
        "reminder-batch-cancel-sync-failure",
        "task-batch-cancel-sync-failure",
        "2026-04-01T09:00:00Z",
    );
    install_sync_outbox_entity_failure_trigger(
        &server,
        "fail_batch_cancel_task_reminder_sync",
        lorvex_domain::naming::ENTITY_TASK_REMINDER,
    );

    let err = server
        .batch_cancel_tasks(Parameters(BatchCancelTasksArgs {
            task_ids: vec!["task-batch-cancel-sync-failure".to_string()],
            reason: None,
            cancel_series: None,
            dry_run: false,
            idempotency_key: None,
        }))
        .expect_err("batch cancel should fail when relation sync enqueue fails");

    assert_is_tool_error(&err);
    assert_eq!(
        task_status(&server, "task-batch-cancel-sync-failure"),
        "open"
    );
    assert_eq!(
        reminder_cancelled_at(&server, "reminder-batch-cancel-sync-failure"),
        None
    );
}

#[test]
#[serial_test::serial(hlc)]
fn batch_cancel_tasks_in_list_rolls_back_when_reminder_relation_sync_enqueue_fails() {
    let server = make_server();
    seed_list(&server, "list-sync-failure");
    seed_task(
        &server,
        "task-batch-list-cancel-sync-failure",
        "Batch List Cancel Sync Failure",
        "open",
        Some("list-sync-failure"),
        None,
        None,
        0,
    );
    insert_task_reminder(
        &server,
        "reminder-batch-list-cancel-sync-failure",
        "task-batch-list-cancel-sync-failure",
        "2026-04-01T09:00:00Z",
    );
    install_sync_outbox_entity_failure_trigger(
        &server,
        "fail_batch_cancel_list_task_reminder_sync",
        lorvex_domain::naming::ENTITY_TASK_REMINDER,
    );

    let err = server
        .batch_cancel_tasks_in_list(Parameters(BatchCancelTasksInListArgs {
            list_id: "list-sync-failure".to_string(),
            statuses: None,
            cancel_series: None,
            dry_run: false,
            idempotency_key: None,
        }))
        .expect_err("batch list cancel should fail when relation sync enqueue fails");

    assert_is_tool_error(&err);
    assert_eq!(
        task_status(&server, "task-batch-list-cancel-sync-failure"),
        "open"
    );
    assert_eq!(
        reminder_cancelled_at(&server, "reminder-batch-list-cancel-sync-failure"),
        None
    );
}

#[test]
#[serial_test::serial(hlc)]
fn batch_reopen_tasks_rolls_back_when_successor_dependency_relation_sync_enqueue_fails() {
    let server = make_server();
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-00000000010d",
        "Batch Reopen Sync Failure",
        "open",
        None,
        Some("2026-04-01"),
        None,
        0,
    );
    server
        .with_conn(|conn| {
            conn.execute(
                "UPDATE tasks SET recurrence = ?1, recurrence_group_id = 'group-batch-reopen-sync-failure', canonical_occurrence_date = '2026-04-01' WHERE id = ?2",
                (r#"{"FREQ":"DAILY","INTERVAL":1}"#, "01966a3f-7c8b-7d4e-8f3a-00000000010d"),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed recurrence");
    let successor_id = complete_recurring_parent_and_get_successor(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-00000000010d",
    );
    seed_task(
        &server,
        "task-batch-reopen-dependency-anchor",
        "Batch Dependency Anchor",
        "open",
        None,
        None,
        None,
        0,
    );
    insert_task_dependency(
        &server,
        &successor_id,
        "task-batch-reopen-dependency-anchor",
    );
    install_sync_outbox_entity_failure_trigger(
        &server,
        "fail_batch_reopen_task_dependency_sync",
        lorvex_domain::naming::EDGE_TASK_DEPENDENCY,
    );

    let err = server
        .batch_reopen_tasks(Parameters(BatchReopenTasksArgs {
            task_ids: vec!["01966a3f-7c8b-7d4e-8f3a-00000000010d".to_string()],
            idempotency_key: None,
        }))
        .expect_err(
            "batch reopen should fail when successor dependency relation sync enqueue fails",
        );

    assert_is_tool_error(&err);
    assert_eq!(
        task_status(&server, "01966a3f-7c8b-7d4e-8f3a-00000000010d"),
        "completed"
    );
    assert_eq!(task_status(&server, &successor_id), "open");
    assert_eq!(dependency_count_for_task(&server, &successor_id), 1);
}
