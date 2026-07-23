//! Overdue-bucket queries: `get_overdue_tasks`,
//! `get_overdue_tasks_for_today`, the count companions, and the shared
//! pagination contract on the overdue path.

use super::support::{
    count_overdue_tasks_for_today, get_overdue_tasks, get_overdue_tasks_for_today, insert_task,
    test_conn, OverduePredicate, Pagination,
};

/// Same `id ASC` tiebreaker invariant as `today_orders_by_id_asc_...`,
/// pinned for the overdue bucket.
#[test]
fn overdue_orders_by_id_asc_when_priority_and_due_date_tie() {
    let conn = test_conn();
    insert_task(
        &conn,
        "task-z",
        "Z",
        "open",
        Some("2026-03-20"),
        None,
        Some(2),
        None,
    );
    insert_task(
        &conn,
        "task-m",
        "M",
        "open",
        Some("2026-03-20"),
        None,
        Some(2),
        None,
    );
    insert_task(
        &conn,
        "task-a",
        "A",
        "open",
        Some("2026-03-20"),
        None,
        Some(2),
        None,
    );

    let pred = OverduePredicate {
        as_of_date: chrono::NaiveDate::from_ymd_opt(2026, 3, 23).unwrap(),
    };
    let tasks = get_overdue_tasks(&conn, &pred, Pagination::default()).unwrap();
    let ids: Vec<&str> = tasks.iter().map(|t| t.core.id.as_str()).collect();
    assert_eq!(
        ids,
        vec!["task-a", "task-m", "task-z"],
        "identical (priority, due_date) tasks must return in id ASC"
    );
}

#[test]
fn overdue_returns_past_due_open_tasks() {
    let conn = test_conn();
    insert_task(
        &conn,
        "t1",
        "Overdue",
        "open",
        Some("2026-03-20"),
        None,
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "t2",
        "Due today",
        "open",
        Some("2026-03-23"),
        None,
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "t3",
        "Overdue completed",
        "completed",
        Some("2026-03-20"),
        None,
        Some(1),
        None,
    );

    let pred = OverduePredicate {
        as_of_date: chrono::NaiveDate::from_ymd_opt(2026, 3, 23).unwrap(),
    };
    let tasks = get_overdue_tasks(&conn, &pred, Pagination::default()).unwrap();
    assert_eq!(tasks.len(), 1, "only open overdue tasks");
    assert_eq!(tasks[0].core.id, "t1");
}

#[test]
fn overdue_excludes_today() {
    let conn = test_conn();
    insert_task(
        &conn,
        "t1",
        "Due today",
        "open",
        Some("2026-03-23"),
        None,
        Some(1),
        None,
    );

    let pred = OverduePredicate {
        as_of_date: chrono::NaiveDate::from_ymd_opt(2026, 3, 23).unwrap(),
    };
    let tasks = get_overdue_tasks(&conn, &pred, Pagination::default()).unwrap();
    assert!(tasks.is_empty(), "due today is not overdue");
}

#[test]
fn overdue_for_today_includes_deadline_overdue_only() {
    let conn = test_conn();
    insert_task(
        &conn,
        "t1",
        "Past due",
        "open",
        Some("2026-03-20"),
        None,
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "t2",
        "Past planned",
        "open",
        None,
        Some("2026-03-20"),
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "t3",
        "Due today",
        "open",
        Some("2026-03-23"),
        None,
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "t4",
        "Completed overdue",
        "completed",
        Some("2026-03-20"),
        None,
        Some(1),
        None,
    );

    let tasks = get_overdue_tasks_for_today(&conn, "2026-03-23", 100, 0).unwrap();
    let ids: Vec<&str> = tasks.iter().map(|t| t.core.id.as_str()).collect();
    assert!(ids.contains(&"t1"), "past due should appear");
    assert!(
        !ids.contains(&"t2"),
        "past planned belongs in the today bucket, not overdue"
    );
    assert!(
        !ids.contains(&"t3"),
        "due today should not appear in overdue"
    );
    assert!(!ids.contains(&"t4"), "completed should not appear");
}

#[test]
fn count_overdue_for_today_matches_query() {
    let conn = test_conn();
    insert_task(
        &conn,
        "t1",
        "Past due",
        "open",
        Some("2026-03-20"),
        None,
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "t2",
        "Past planned",
        "open",
        None,
        Some("2026-03-20"),
        Some(1),
        None,
    );

    let count = count_overdue_tasks_for_today(&conn, "2026-03-23").unwrap();
    assert_eq!(count, 1);
}

#[test]
fn pagination_limits_results() {
    let conn = test_conn();
    for i in 0..5 {
        insert_task(
            &conn,
            &format!("t{i}"),
            &format!("Task {i}"),
            "open",
            Some("2026-03-20"),
            None,
            Some(1),
            None,
        );
    }

    let pred = OverduePredicate {
        as_of_date: chrono::NaiveDate::from_ymd_opt(2026, 3, 23).unwrap(),
    };
    let page = Pagination {
        limit: 2,
        offset: 0,
    };
    let tasks = get_overdue_tasks(&conn, &pred, page).unwrap();
    assert_eq!(tasks.len(), 2);

    let page2 = Pagination {
        limit: 2,
        offset: 2,
    };
    let tasks2 = get_overdue_tasks(&conn, &pred, page2).unwrap();
    assert_eq!(tasks2.len(), 2);

    let page3 = Pagination {
        limit: 2,
        offset: 4,
    };
    let tasks3 = get_overdue_tasks(&conn, &pred, page3).unwrap();
    assert_eq!(tasks3.len(), 1);
}
