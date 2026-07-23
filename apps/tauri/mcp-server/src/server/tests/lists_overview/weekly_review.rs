use super::*;

#[test]
#[serial_test::serial(hlc)]
fn get_weekly_review_snapshot_is_bounded_and_high_signal() {
    let server = make_server();
    let long_title = "D".repeat(500);
    let long_list_name = "Project".repeat(30);
    seed_list(&server, "list-review");
    let yesterday = crate::time::date_plus_days_ymd_local_for_test(-1);

    for index in 0..8 {
        seed_task(
            &server,
            &format!("deferred-{index}"),
            &format!("{long_title} deferred {index}"),
            "open",
            Some("list-review"),
            (index < 2).then_some(&yesterday),
            None,
            3 + i64::from(index),
        );
    }

    for index in 0..3 {
        seed_task(
            &server,
            &format!("completed-{index}"),
            &format!("{long_title} completed {index}"),
            "completed",
            Some("list-review"),
            None,
            None,
            0,
        );
    }

    for index in 0..2 {
        seed_task(
            &server,
            &format!("someday-{index}"),
            &format!("Someday {index}"),
            "someday",
            Some("list-review"),
            None,
            None,
            0,
        );
    }

    server
        .with_conn(|conn| {
            conn.execute(
                "UPDATE lists SET name = ? WHERE id = ?",
                (long_list_name.clone(), "list-review"),
            )
            .map_err(to_error_message)?;
            conn.execute(
                "UPDATE tasks SET updated_at = datetime('now', '-10 days') WHERE list_id = 'list-review' AND status = 'open'",
                [],
            )
            .map_err(to_error_message)?;
            conn.execute(
                "UPDATE tasks SET completed_at = datetime('now', '-1 days') WHERE id LIKE 'completed-%'",
                [],
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed review snapshot temporal fields");

    let payload = server
        .get_weekly_review_snapshot()
        .expect("weekly review snapshot should succeed");
    let value: Value = serde_json::from_str(&payload).expect("valid json");

    assert_eq!(value["counts"]["deferred_open"], 8);
    assert_eq!(value["counts"]["overdue_open"], 2);
    assert_eq!(value["counts"]["someday"], 2);
    assert_eq!(value["counts"]["completed_with_estimate_count"], 0);
    assert_eq!(
        value["counts"]["estimate_coverage_ratio"].as_f64(),
        Some(0.0)
    );
    assert_eq!(value["limits"]["top_deferred"], 5);
    assert_eq!(value["limits"]["title_max_chars"], 120);
    assert_eq!(value["limits"]["list_name_max_chars"], 80);
    assert_eq!(
        value["top_deferred"]
            .as_array()
            .expect("top_deferred array")
            .len(),
        5
    );
    let top_deferred = value["top_deferred"]
        .as_array()
        .expect("top_deferred array");
    assert!(top_deferred.iter().all(|row| {
        row["title"]
            .as_str()
            .is_some_and(|title| title.chars().count() <= 123)
    }));
    assert!(top_deferred[0]["title"]
        .as_str()
        .expect("top deferred title")
        .ends_with("..."));

    let top_completed = value["top_completed"]
        .as_array()
        .expect("top completed array");
    assert!(!top_completed.is_empty());
    assert!(top_completed.iter().all(|row| {
        row["title"]
            .as_str()
            .is_some_and(|title| title.chars().count() <= 123)
    }));

    let top_stalled = value["top_stalled_lists"]
        .as_array()
        .expect("top stalled lists array");
    assert!(!top_stalled.is_empty());
    assert!(top_stalled.iter().all(|row| {
        row["name"]
            .as_str()
            .is_some_and(|name| name.chars().count() <= 83)
    }));
    assert!(top_stalled[0]["name"]
        .as_str()
        .expect("stalled list name")
        .ends_with("..."));
    assert!(payload.len() <= 8_000);
}
