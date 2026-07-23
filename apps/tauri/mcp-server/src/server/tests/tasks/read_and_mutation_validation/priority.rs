use super::support::PRIORITY_TASK_UUID;
use super::*;
use lorvex_domain::Patch;

#[test]
#[serial_test::serial(hlc)]
fn create_task_rejects_priority_outside_allowed_range() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    let err = server
        .create_task(Parameters(CreateTaskArgs {
            title: "Priority Create Test".to_string(),
            list_id: Some("list-inbox".to_string()),
            priority: Some(5),
            due_date: None,
            due_time: None,
            estimated_minutes: None,
            tags: None,
            body: None,
            raw_input: None,
            ai_notes: None,

            planned_date: None,

            depends_on: None,

            completed: None,

            reminders: None,
            recurrence: None,
            include_advice: None,
            idempotency_key: None,
        }))
        .expect_err("invalid create priority should be rejected");

    assert!(err.contains("Invalid priority '5'"));
}

#[test]
#[serial_test::serial(hlc)]
fn update_task_rejects_priority_outside_allowed_range() {
    let server = make_server();
    seed_task(
        &server,
        PRIORITY_TASK_UUID,
        "Priority Test",
        "open",
        None,
        None,
        None,
        0,
    );

    let err = server
        .update_task(Parameters(UpdateTaskArgs {
            id: PRIORITY_TASK_UUID.to_string(),
            title: None,
            body: Patch::Unset,
            raw_input: None,
            ai_notes: Patch::Unset,
            status: None,
            list_id: None,
            tags_set: None,
            tags_add: None,
            tags_remove: None,
            priority: Some(5),

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
        .expect_err("invalid update priority should be rejected");

    assert!(err.contains("Invalid priority '5'"));
}

#[test]
#[serial_test::serial(hlc)]
fn batch_create_tasks_rejects_priority_outside_allowed_range() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    let err = server
        .batch_create_tasks(Parameters(BatchCreateTasksArgs {
            idempotency_key: None,
            include_advice: None,
            tasks: vec![BatchCreateTaskInput {
                title: "Batch Priority Test".to_string(),
                list_id: Some("list-inbox".to_string()),
                priority: Some(5),
                due_date: None,
                due_time: None,
                estimated_minutes: None,
                tags: None,
                body: None,
                raw_input: None,
                ai_notes: None,

                planned_date: None,

                depends_on: None,

                completed: None,
                reminders: None,
                recurrence: None,
            }],
            dry_run: false,
        }))
        .expect_err("invalid batch create priority should be rejected");

    assert!(err.contains("Invalid priority '5'"));
}
