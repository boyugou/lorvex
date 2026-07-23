use super::*;

#[test]
#[serial_test::serial(hlc)]
fn get_list_returns_bounded_payload_with_truncation_metadata() {
    let server = make_server();
    seed_list(&server, "list-1");
    seed_task(
        &server,
        "task-1",
        "Task 1",
        "open",
        Some("list-1"),
        Some("2026-03-10"),
        None,
        0,
    );
    seed_task(
        &server,
        "task-2",
        "Task 2",
        "open",
        Some("list-1"),
        Some("2026-03-11"),
        None,
        0,
    );
    seed_task(
        &server,
        "task-3",
        "Task 3",
        "open",
        Some("list-1"),
        Some("2026-03-12"),
        None,
        0,
    );

    let payload = server
        .get_list(Parameters(GetListArgs {
            id: "list-1".to_string(),
            limit: 2,
            offset: 0,
        }))
        .expect("get list");
    let value: Value = serde_json::from_str(&payload).expect("valid json");

    assert_eq!(value["id"], "list-1");
    assert_eq!(value["limit"], 2);
    assert_eq!(value["returned"], 2);
    assert_eq!(value["truncated"], true);
    assert_eq!(value["total_matching"], 3);
    assert_eq!(value["tasks"].as_array().expect("tasks array").len(), 2);
}

#[test]
#[serial_test::serial(hlc)]
fn get_list_excludes_completed_tasks_older_than_retention_window() {
    let server = make_server();
    seed_list(&server, "list-retention");
    seed_task(
        &server,
        "task-open",
        "Task Open",
        "open",
        Some("list-retention"),
        None,
        None,
        0,
    );
    seed_task(
        &server,
        "task-completed-recent",
        "Task Completed Recent",
        "completed",
        Some("list-retention"),
        None,
        None,
        0,
    );
    seed_task(
        &server,
        "task-completed-old",
        "Task Completed Old",
        "completed",
        Some("list-retention"),
        None,
        None,
        0,
    );
    seed_task(
        &server,
        "task-cancelled",
        "Task Cancelled",
        "cancelled",
        Some("list-retention"),
        None,
        None,
        0,
    );

    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO preferences (key, value, version, updated_at)
                 VALUES ('timezone', '\"America/Los_Angeles\"', '0000000000000_0000_0000000000000000', '2026-03-08T01:00:00Z')
                 ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
                [],
            )
            .map_err(to_error_message)?;
            conn.execute(
                "UPDATE tasks SET completed_at = datetime('now') WHERE id = 'task-completed-recent'",
                [],
            )
            .map_err(to_error_message)?;
            conn.execute(
                "UPDATE tasks SET completed_at = datetime('now', '-8 days') WHERE id = 'task-completed-old'",
                [],
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed retention timestamps");

    let payload = server
        .get_list(Parameters(GetListArgs {
            id: "list-retention".to_string(),
            limit: 10,
            offset: 0,
        }))
        .expect("get list");
    let value: Value = serde_json::from_str(&payload).expect("valid json");
    let task_ids = value["tasks"]
        .as_array()
        .expect("tasks array")
        .iter()
        .filter_map(|row| row.get("id").and_then(Value::as_str))
        .collect::<Vec<_>>();

    assert!(task_ids.contains(&"task-open"));
    assert!(task_ids.contains(&"task-completed-recent"));
    assert!(!task_ids.contains(&"task-completed-old"));
    assert!(!task_ids.contains(&"task-cancelled"));
    assert_eq!(value["total_matching"], 2);
}
