use super::*;

#[tokio::test]
async fn get_weekly_review_brief_returns_bounded_sections_with_truncation_metadata() {
    let server = make_server();
    seed_list(&server, "list-review-brief");
    let yesterday = crate::time::date_plus_days_ymd_local_for_test(-1);

    for index in 0..6 {
        seed_task(
            &server,
            &format!("review-deferred-{index}"),
            &format!("Deferred task {index}"),
            "open",
            Some("list-review-brief"),
            (index < 2).then_some(&yesterday),
            None,
            3 + i64::from(index),
        );
    }

    for index in 0..7 {
        seed_task(
            &server,
            &format!("review-completed-{index}"),
            &format!("Completed task {index}"),
            "completed",
            Some("list-review-brief"),
            None,
            None,
            0,
        );
    }

    for index in 0..4 {
        seed_task(
            &server,
            &format!("review-someday-{index}"),
            &format!("Someday task {index}"),
            "someday",
            Some("list-review-brief"),
            None,
            None,
            0,
        );
    }

    server
        .with_conn(|conn| {
            conn.execute(
                "UPDATE tasks SET updated_at = datetime('now', '-10 days') WHERE list_id = 'list-review-brief' AND status = 'open'",
                [],
            )
            .map_err(to_error_message)?;
            conn.execute(
                "UPDATE tasks SET completed_at = datetime('now', '-1 days') WHERE id LIKE 'review-completed-%'",
                [],
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed weekly review temporal fields");

    let payload = server
        .get_weekly_review_brief(
            Parameters(GetWeeklyReviewBriefArgs {
                completed_limit: 3,
                stalled_lists_limit: 1,
                deferred_limit: 2,
                someday_limit: 2,
            }),
            tokio_util::sync::CancellationToken::new(),
        )
        .await
        .expect("weekly review brief should succeed");
    let value: Value = serde_json::from_str(&payload).expect("valid json");

    assert_eq!(
        value["completed_this_week"]
            .as_array()
            .expect("completed array")
            .len(),
        3
    );
    assert_eq!(
        value["stalled_lists"]
            .as_array()
            .expect("stalled array")
            .len(),
        1
    );
    assert_eq!(
        value["frequently_deferred"]
            .as_array()
            .expect("deferred array")
            .len(),
        2
    );
    assert_eq!(
        value["someday_items"]
            .as_array()
            .expect("someday array")
            .len(),
        2
    );
    assert_eq!(value["overdue_count"], 2);

    assert_eq!(value["section_meta"]["completed_this_week"]["limit"], 3);
    assert_eq!(
        value["section_meta"]["completed_this_week"]["total_matching"],
        7
    );
    assert_eq!(
        value["section_meta"]["completed_this_week"]["truncated"],
        true
    );
    assert_eq!(value["section_meta"]["stalled_lists"]["limit"], 1);
    assert_eq!(value["section_meta"]["stalled_lists"]["total_matching"], 1);
    assert_eq!(value["section_meta"]["stalled_lists"]["truncated"], false);
    assert_eq!(value["section_meta"]["frequently_deferred"]["limit"], 2);
    assert_eq!(
        value["section_meta"]["frequently_deferred"]["total_matching"],
        6
    );
    assert_eq!(
        value["section_meta"]["frequently_deferred"]["truncated"],
        true
    );
    assert_eq!(value["section_meta"]["someday_items"]["limit"], 2);
    assert_eq!(value["section_meta"]["someday_items"]["total_matching"], 4);
    assert_eq!(value["section_meta"]["someday_items"]["truncated"], true);
}

#[tokio::test]
async fn get_weekly_review_brief_includes_estimate_metrics() {
    let server = make_server();
    seed_list(&server, "list-review-estimates");

    seed_task(
        &server,
        "review-estimate-1",
        "Estimated task",
        "completed",
        Some("list-review-estimates"),
        None,
        None,
        0,
    );
    seed_task(
        &server,
        "review-estimate-2",
        "Estimated task 2",
        "completed",
        Some("list-review-estimates"),
        None,
        None,
        0,
    );
    seed_task(
        &server,
        "review-estimate-3",
        "Unsized task",
        "completed",
        Some("list-review-estimates"),
        None,
        None,
        0,
    );

    server
        .with_conn(|conn| {
            conn.execute(
                "UPDATE tasks
                 SET estimated_minutes = 30, completed_at = datetime('now', '-1 day')
                 WHERE id = 'review-estimate-1'",
                [],
            )
            .map_err(to_error_message)?;
            conn.execute(
                "UPDATE tasks
                 SET estimated_minutes = 60, completed_at = datetime('now', '-2 days')
                 WHERE id = 'review-estimate-2'",
                [],
            )
            .map_err(to_error_message)?;
            conn.execute(
                "UPDATE tasks
                 SET completed_at = datetime('now', '-3 days')
                 WHERE id = 'review-estimate-3'",
                [],
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed estimate metrics");

    let payload = server
        .get_weekly_review_brief(
            Parameters(GetWeeklyReviewBriefArgs {
                completed_limit: 10,
                stalled_lists_limit: 5,
                deferred_limit: 5,
                someday_limit: 5,
            }),
            tokio_util::sync::CancellationToken::new(),
        )
        .await
        .expect("weekly review brief should succeed");
    let value: Value = serde_json::from_str(&payload).expect("valid json");

    assert_eq!(value["estimate_summary"]["completed_total"], 3);
    assert_eq!(
        value["estimate_summary"]["completed_with_estimate_count"],
        2
    );
    let coverage = value["estimate_summary"]["estimate_coverage_ratio"]
        .as_f64()
        .expect("coverage rate");
    assert!((coverage - (2.0 / 3.0)).abs() < 0.0001);
}
