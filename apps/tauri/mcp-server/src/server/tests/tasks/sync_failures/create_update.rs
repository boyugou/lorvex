use super::support::*;
use lorvex_domain::Patch;

#[test]
#[serial_test::serial(hlc)]
fn create_task_rolls_back_when_precompleted_reminder_relation_sync_enqueue_fails() {
    let server = make_server();
    install_sync_outbox_entity_failure_trigger(
        &server,
        "fail_create_task_reminder_sync",
        lorvex_domain::naming::ENTITY_TASK_REMINDER,
    );

    let err = server
        .create_task(Parameters(CreateTaskArgs {
            title: "Create Sync Failure".to_string(),
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
            include_advice: None,
            idempotency_key: None,
        }))
        .expect_err("pre-completed create should fail when relation sync enqueue fails");

    assert_is_tool_error(&err);
    assert_eq!(task_count(&server), 0);
    assert_eq!(reminder_count(&server), 0);
}

#[test]
#[serial_test::serial(hlc)]
fn create_task_rolls_back_when_spawned_successor_reload_fails() {
    let server = make_server();
    install_spawned_successor_delete_trigger(&server, "delete_create_spawned_successor");

    let err = server
        .create_task(Parameters(CreateTaskArgs {
            title: "Create Successor Reload Failure".to_string(),
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
            include_advice: None,
            idempotency_key: None,
        }))
        .expect_err("pre-completed create should fail when spawned successor reload fails");

    assert_is_tool_error(&err);
    assert_eq!(task_count(&server), 0);
}

#[test]
#[serial_test::serial(hlc)]
fn update_task_rolls_back_when_status_relation_sync_enqueue_fails() {
    let server = make_server();
    seed_task(
        &server,
        "task-update-sync-failure",
        "Update Sync Failure",
        "open",
        None,
        None,
        None,
        0,
    );
    insert_task_reminder(
        &server,
        "reminder-update-sync-failure",
        "task-update-sync-failure",
        "2026-04-01T09:00:00Z",
    );
    install_sync_outbox_entity_failure_trigger(
        &server,
        "fail_update_task_reminder_sync",
        lorvex_domain::naming::ENTITY_TASK_REMINDER,
    );

    let err = server
        .update_task(Parameters(UpdateTaskArgs {
            id: "task-update-sync-failure".to_string(),
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
            idempotency_key: None,
        }))
        .expect_err("status update should fail when relation sync enqueue fails");

    assert_is_tool_error(&err);
    assert_eq!(task_status(&server, "task-update-sync-failure"), "open");
    assert_eq!(
        reminder_cancelled_at(&server, "reminder-update-sync-failure"),
        None
    );
}
