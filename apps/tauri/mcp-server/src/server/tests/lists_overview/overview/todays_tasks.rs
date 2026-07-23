use super::super::*;

#[test]
#[serial_test::serial(hlc)]
fn get_todays_tasks_exposes_bucket_summary_and_truncation() {
    let server = make_server();
    let today = today_ymd_local_for_test();
    let yesterday = crate::time::date_plus_days_ymd_local_for_test(-1);
    seed_list(&server, "list-today");

    seed_task(
        &server,
        "overdue-1",
        "Overdue 1",
        "open",
        Some("list-today"),
        Some(&yesterday),
        None,
        0,
    );
    seed_task(
        &server,
        "overdue-2",
        "Overdue 2",
        "open",
        Some("list-today"),
        Some(&yesterday),
        None,
        0,
    );
    seed_task(
        &server,
        "today-1",
        "Today 1",
        "open",
        Some("list-today"),
        Some(&today),
        Some("09:00"),
        0,
    );
    seed_task(
        &server,
        "today-2",
        "Today 2",
        "open",
        Some("list-today"),
        Some(&today),
        Some("10:00"),
        0,
    );
    seed_task(
        &server,
        "undated-1",
        "Undated 1",
        "open",
        Some("list-today"),
        None,
        None,
        0,
    );
    seed_task(
        &server,
        "undated-2",
        "Undated 2",
        "open",
        Some("list-today"),
        None,
        None,
        0,
    );
    // Set priority on undated tasks so they match the high-priority undated bucket.
    server
        .with_conn(|conn| {
            conn.execute(
                "UPDATE tasks SET priority = 1 WHERE id IN ('undated-1', 'undated-2')",
                [],
            )
            .map_err(crate::system::handler_support::to_error_message)?;
            Ok(())
        })
        .expect("set priority on undated tasks");

    let payload = server
        .get_todays_tasks(Parameters(GetTodaysTasksArgs {
            limit_per_bucket: 1,
            offset: 0,
        }))
        .expect("get todays tasks");
    let value: Value = serde_json::from_str(&payload).expect("valid json");

    assert_eq!(value["limit_per_bucket"], 1);
    assert_eq!(value["overdue"].as_array().expect("overdue array").len(), 1);
    assert_eq!(
        value["today_tasks"]
            .as_array()
            .expect("due_today array")
            .len(),
        1
    );
    assert_eq!(
        value["high_priority_undated"]
            .as_array()
            .expect("high urgency array")
            .len(),
        1
    );
    assert_eq!(value["truncated"]["overdue"], true);
    assert_eq!(value["truncated"]["today_tasks"], true);
    assert_eq!(value["truncated"]["high_priority_undated"], true);
    assert_eq!(value["summary"]["overdue_count"], 2);
    assert_eq!(value["summary"]["today_pool_count"], 2);
    assert_eq!(value["summary"]["high_priority_undated_count"], 2);
    // #2750 — canonical names: `total_matching` = pool, `count` = returned.
    assert_eq!(value["summary"]["total_matching"], 6);
    assert_eq!(value["summary"]["count"], 3);
    // Legacy names must not resurface.
    assert!(value["summary"].get("total").is_none());
    assert!(value["summary"].get("total_returned").is_none());
}

/// #3403: the day-query enrichment helper re-selects each bucket's rows
/// via `WHERE id IN (?,...) ORDER BY CASE id WHEN ? THEN n ... END` to
/// preserve the repository's ordering. Without an explicit secondary
/// key, SQLite resolves any tie (and any unmatched CASE branch's
/// implicit `NULL`) in unspecified order — meaning two siblings with
/// identical priority + due_date could swap places between calls.
/// This test seeds two tasks with the same priority and due_date in
/// the today-pool bucket and asserts the returned order is the same
/// as the canonical `id ASC` tiebreaker the repos guarantee, both at
/// offset 0 and across an offset-1 page boundary.
#[test]
#[serial_test::serial(hlc)]
fn get_todays_tasks_today_pool_uses_id_asc_tiebreaker() {
    let server = make_server();
    let today = today_ymd_local_for_test();
    seed_list(&server, "list-tie");

    // Insert in reverse-id order so a non-deterministic order-by would be
    // observably wrong (would surface "today-z" before "today-a"). Both
    // rows share priority + due_date + due_time + created_at.
    seed_task(
        &server,
        "today-z",
        "Today Z",
        "open",
        Some("list-tie"),
        Some(&today),
        Some("09:00"),
        0,
    );
    seed_task(
        &server,
        "today-a",
        "Today A",
        "open",
        Some("list-tie"),
        Some(&today),
        Some("09:00"),
        0,
    );
    server
        .with_conn(|conn| {
            conn.execute(
                "UPDATE tasks SET priority = 2 WHERE id IN ('today-a', 'today-z')",
                [],
            )
            .map_err(crate::system::handler_support::to_error_message)?;
            Ok(())
        })
        .expect("set equal priority on tied today-pool tasks");

    let payload = server
        .get_todays_tasks(Parameters(GetTodaysTasksArgs {
            limit_per_bucket: 10,
            offset: 0,
        }))
        .expect("get todays tasks");
    let value: Value = serde_json::from_str(&payload).expect("valid json");
    let today_ids: Vec<&str> = value["today_tasks"]
        .as_array()
        .expect("today_tasks array")
        .iter()
        .map(|row| row["id"].as_str().expect("task id"))
        .collect();
    assert_eq!(today_ids, vec!["today-a", "today-z"]);

    // Cross a page boundary: with limit=1 + offset=1 we must land on the
    // strictly second row from the deterministic order, not flicker.
    let page2 = server
        .get_todays_tasks(Parameters(GetTodaysTasksArgs {
            limit_per_bucket: 1,
            offset: 1,
        }))
        .expect("get todays tasks page 2");
    let page2_value: Value = serde_json::from_str(&page2).expect("valid json");
    let page2_ids: Vec<&str> = page2_value["today_tasks"]
        .as_array()
        .expect("today_tasks array")
        .iter()
        .map(|row| row["id"].as_str().expect("task id"))
        .collect();
    assert_eq!(page2_ids, vec!["today-z"]);
}
