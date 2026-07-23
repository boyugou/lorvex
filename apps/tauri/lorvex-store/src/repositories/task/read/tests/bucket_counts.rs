//! Aggregate bucket-count queries: `count_open_task_day_buckets`,
//! `get_high_priority_undated_tasks`, and the count companion. These
//! drive the today-view bucket badges and the high-priority undated
//! sidebar.

use super::support::{
    count_high_priority_undated_tasks, count_open_task_day_buckets,
    get_high_priority_undated_tasks, insert_task, test_conn, OpenTaskDayBucketCounts,
};

#[test]
fn count_open_task_day_buckets_matches_canonical_bucket_queries() {
    let conn = test_conn();
    insert_task(
        &conn,
        "overdue",
        "Overdue",
        "open",
        Some("2026-03-20"),
        None,
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "past-planned",
        "Past planned",
        "open",
        Some("2026-03-26"),
        Some("2026-03-20"),
        Some(2),
        None,
    );
    insert_task(
        &conn,
        "due-today",
        "Due today",
        "open",
        Some("2026-03-23"),
        None,
        Some(3),
        None,
    );
    insert_task(
        &conn,
        "upcoming",
        "Upcoming",
        "open",
        Some("2026-03-27"),
        None,
        Some(1),
        None,
    );

    let counts = count_open_task_day_buckets(
        &conn,
        chrono::NaiveDate::from_ymd_opt(2026, 3, 23).unwrap(),
        7,
    )
    .unwrap();
    assert_eq!(
        counts,
        OpenTaskDayBucketCounts {
            overdue: 1,
            today_pool: 2,
            upcoming: 1,
        }
    );
}

#[test]
fn high_priority_undated_returns_p1_p2_without_dates() {
    let conn = test_conn();
    insert_task(
        &conn,
        "t1",
        "Priority 1 no due",
        "open",
        None,
        None,
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "t2",
        "Priority 2 no due",
        "open",
        None,
        None,
        Some(2),
        None,
    );
    insert_task(
        &conn,
        "t3",
        "Priority 3 no due",
        "open",
        None,
        None,
        Some(3),
        None,
    );
    insert_task(
        &conn,
        "t4",
        "Priority 1 with due",
        "open",
        Some("2026-03-25"),
        None,
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "t5",
        "No priority no due",
        "open",
        None,
        None,
        None,
        None,
    );

    let tasks = get_high_priority_undated_tasks(&conn, 100, 0).unwrap();
    let ids: Vec<&str> = tasks.iter().map(|t| t.core.id.as_str()).collect();
    assert!(ids.contains(&"t1"), "p1 no due or plan");
    assert!(ids.contains(&"t2"), "p2 no due or plan");
    assert!(!ids.contains(&"t3"), "p3 excluded");
    assert!(!ids.contains(&"t4"), "has due date");
    assert!(!ids.contains(&"t5"), "no priority");
}

#[test]
fn count_high_priority_undated_matches_query() {
    let conn = test_conn();
    insert_task(&conn, "t1", "P1", "open", None, None, Some(1), None);
    insert_task(&conn, "t2", "P2", "open", None, None, Some(2), None);
    insert_task(&conn, "t3", "P3", "open", None, None, Some(3), None);

    let count = count_high_priority_undated_tasks(&conn).unwrap();
    assert_eq!(count, 2);
}
