use super::*;

#[test]
#[serial_test::serial(hlc)]
fn create_task_returns_intake_advice_when_requested() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");
    seed_task(
        &server,
        "existing-duplicate",
        "Duplicate Candidate",
        "open",
        None,
        None,
        None,
        0,
    );

    let response = server
        .create_task(Parameters(CreateTaskArgs {
            title: "Duplicate Candidate".to_string(),
            list_id: Some("list-inbox".to_string()),
            priority: None,
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
            include_advice: Some(true),
            idempotency_key: None,
        }))
        .expect("create task with advice should succeed");

    let payload: Value = serde_json::from_str(&response).expect("parse create_task response");
    let advice = payload
        .get("advice")
        .and_then(Value::as_array)
        .expect("response should include advice array");
    let codes = advice
        .iter()
        .filter_map(|entry| entry.get("code").and_then(Value::as_str))
        .collect::<Vec<_>>();

    assert!(
        codes.contains(&"missing_estimate"),
        "expected missing_estimate advice, got {codes:?}"
    );
    assert!(
        codes.contains(&"missing_planned_date"),
        "expected missing_planned_date advice, got {codes:?}"
    );
    assert!(
        codes.contains(&"likely_duplicate_title"),
        "expected likely_duplicate_title advice, got {codes:?}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn batch_create_tasks_returns_intake_advice_when_requested() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");
    seed_task(
        &server,
        "existing-batch-duplicate",
        "Batch Duplicate Candidate",
        "open",
        None,
        None,
        None,
        0,
    );

    let response = server
        .batch_create_tasks(Parameters(BatchCreateTasksArgs {
            idempotency_key: None,
            include_advice: Some(true),
            tasks: vec![BatchCreateTaskInput {
                title: "Batch Duplicate Candidate".to_string(),
                list_id: Some("list-inbox".to_string()),
                priority: None,
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
        .expect("batch_create_tasks with advice should succeed");

    let payload: Value =
        serde_json::from_str(&response).expect("parse batch_create_tasks response");
    let advice_entries = payload
        .get("advice")
        .and_then(Value::as_array)
        .expect("response should include advice array");
    assert_eq!(advice_entries.len(), 1, "expected one batch advice entry");
    let advice = advice_entries[0]
        .get("advice")
        .and_then(Value::as_array)
        .expect("batch advice entry should include advice list");
    let codes = advice
        .iter()
        .filter_map(|entry| entry.get("code").and_then(Value::as_str))
        .collect::<Vec<_>>();
    assert!(
        codes.contains(&"likely_duplicate_title"),
        "expected likely_duplicate_title advice, got {codes:?}"
    );
}
