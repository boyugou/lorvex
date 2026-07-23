use super::*;

#[test]
fn build_get_all_tasks_sql_includes_completed_within_limit() {
    let conn = setup_sync_test_conn();
    for index in 0..240 {
        insert_task_for_all_tasks_test(
            &conn,
            &format!("open-{index}"),
            "open",
            "2026-03-03T09:00:00Z",
        );
    }
    insert_task_for_all_tasks_test(&conn, "completed-last", "completed", "2026-03-03T09:10:00Z");

    let sql = build_get_all_tasks_sql(true, false);
    // A LIMIT of 2000 is applied for performance but is generous enough that
    // completed tasks are visible in normal-size datasets.
    let tasks = tasks_from_query(&conn, &sql, []).expect("query all tasks with completed");
    assert_eq!(tasks.len(), 241);
    assert!(tasks.iter().any(|task| task.id == "completed-last"));
}

#[test]
fn build_get_all_tasks_sql_respects_completed_and_cancelled_flags() {
    let conn = setup_sync_test_conn();
    insert_task_for_all_tasks_test(&conn, "open-1", "open", "2026-03-03T09:00:00Z");
    insert_task_for_all_tasks_test(&conn, "completed-1", "completed", "2026-03-03T09:01:00Z");
    insert_task_for_all_tasks_test(&conn, "cancelled-1", "cancelled", "2026-03-03T09:02:00Z");

    let open_only = tasks_from_query(&conn, &build_get_all_tasks_sql(false, false), [])
        .expect("open-only tasks");
    assert_eq!(open_only.len(), 1);
    assert_eq!(open_only[0].status, "open");

    let with_completed = tasks_from_query(&conn, &build_get_all_tasks_sql(true, false), [])
        .expect("tasks including completed");
    let statuses_with_completed: Vec<&str> = with_completed
        .iter()
        .map(|task| task.status.as_str())
        .collect();
    assert!(statuses_with_completed.contains(&"open"));
    assert!(statuses_with_completed.contains(&"completed"));
    assert!(!statuses_with_completed.contains(&"cancelled"));

    let with_cancelled = tasks_from_query(&conn, &build_get_all_tasks_sql(false, true), [])
        .expect("tasks including cancelled");
    let statuses_with_cancelled: Vec<&str> = with_cancelled
        .iter()
        .map(|task| task.status.as_str())
        .collect();
    assert!(statuses_with_cancelled.contains(&"open"));
    assert!(statuses_with_cancelled.contains(&"cancelled"));
    assert!(!statuses_with_cancelled.contains(&"completed"));

    let with_all = tasks_from_query(&conn, &build_get_all_tasks_sql(true, true), [])
        .expect("tasks including completed and cancelled");
    let statuses_with_all: Vec<&str> = with_all.iter().map(|task| task.status.as_str()).collect();
    assert!(statuses_with_all.contains(&"open"));
    assert!(statuses_with_all.contains(&"completed"));
    assert!(statuses_with_all.contains(&"cancelled"));
}
