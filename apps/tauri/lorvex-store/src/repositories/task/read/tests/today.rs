//! Today-bucket queries: `get_today_tasks`, `get_exact_today_tasks`,
//! and the count companions. Tests verify planned/due-date selection,
//! status exclusion, deadline-overdue exclusion, and `id ASC`
//! tiebreaker stability under shared (priority, due_date).

use super::support::{
    count_exact_today_tasks, count_high_priority_undated_tasks, get_exact_today_tasks,
    get_high_priority_undated_tasks, get_today_tasks, insert_task, test_conn, Pagination,
    TodayPredicate,
};

#[test]
fn today_returns_planned_date_lte_today() {
    let conn = test_conn();
    insert_task(
        &conn,
        "t1",
        "Planned today",
        "open",
        None,
        Some("2026-03-23"),
        Some(2),
        None,
    );
    insert_task(
        &conn,
        "t2",
        "Planned yesterday",
        "open",
        None,
        Some("2026-03-22"),
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "t3",
        "Planned tomorrow",
        "open",
        None,
        Some("2026-03-24"),
        Some(1),
        None,
    );

    let pred = TodayPredicate {
        date: chrono::NaiveDate::from_ymd_opt(2026, 3, 23).unwrap(),
    };
    let tasks = get_today_tasks(&conn, &pred, Pagination::default()).unwrap();
    let ids: Vec<&str> = tasks.iter().map(|t| t.core.id.as_str()).collect();
    assert!(ids.contains(&"t1"), "planned today should appear");
    assert!(ids.contains(&"t2"), "planned yesterday should appear");
    assert!(!ids.contains(&"t3"), "planned tomorrow should not appear");
}

#[test]
fn today_returns_due_date_when_no_planned_date() {
    let conn = test_conn();
    insert_task(
        &conn,
        "t1",
        "Due today, no plan",
        "open",
        Some("2026-03-23"),
        None,
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "t2",
        "Due tomorrow, no plan",
        "open",
        Some("2026-03-24"),
        None,
        Some(1),
        None,
    );

    let pred = TodayPredicate {
        date: chrono::NaiveDate::from_ymd_opt(2026, 3, 23).unwrap(),
    };
    let tasks = get_today_tasks(&conn, &pred, Pagination::default()).unwrap();
    let ids: Vec<&str> = tasks.iter().map(|t| t.core.id.as_str()).collect();
    assert!(ids.contains(&"t1"), "due today with no plan should appear");
    assert!(
        !ids.contains(&"t2"),
        "due tomorrow with no plan should not appear"
    );
}

#[test]
fn today_excludes_completed_tasks() {
    let conn = test_conn();
    insert_task(
        &conn,
        "t1",
        "Completed task",
        "completed",
        Some("2026-03-23"),
        None,
        Some(1),
        None,
    );

    let pred = TodayPredicate {
        date: chrono::NaiveDate::from_ymd_opt(2026, 3, 23).unwrap(),
    };
    let tasks = get_today_tasks(&conn, &pred, Pagination::default()).unwrap();
    assert!(tasks.is_empty(), "completed tasks should not appear");
}

#[test]
fn today_excludes_deadline_overdue() {
    let conn = test_conn();
    insert_task(
        &conn,
        "t1",
        "Overdue task",
        "open",
        Some("2026-03-20"),
        None,
        Some(1),
        None,
    );

    let pred = TodayPredicate {
        date: chrono::NaiveDate::from_ymd_opt(2026, 3, 23).unwrap(),
    };
    let tasks = get_today_tasks(&conn, &pred, Pagination::default()).unwrap();
    assert!(
        tasks.is_empty(),
        "deadline-overdue work belongs in the overdue bucket"
    );
}

/// Regression: three tasks with identical (priority, due_date) must be
/// returned in `id ASC` order, matching the canonical `TASK_ORDER_BY`.
/// Without the `id ASC` tiebreaker, OFFSET pagination over a shared
/// sort key can duplicate or skip rows as HLC-advanced `created_at`
/// values drift on sync-apply re-writes.
#[test]
fn today_orders_by_id_asc_when_priority_and_due_date_tie() {
    let conn = test_conn();
    // Insert in reverse-id order to catch insertion-order leakage.
    insert_task(
        &conn,
        "task-charlie",
        "C",
        "open",
        Some("2026-03-23"),
        None,
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "task-bravo",
        "B",
        "open",
        Some("2026-03-23"),
        None,
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "task-alpha",
        "A",
        "open",
        Some("2026-03-23"),
        None,
        Some(1),
        None,
    );

    let pred = TodayPredicate {
        date: chrono::NaiveDate::from_ymd_opt(2026, 3, 23).unwrap(),
    };
    let tasks = get_today_tasks(&conn, &pred, Pagination::default()).unwrap();
    let ids: Vec<&str> = tasks.iter().map(|t| t.core.id.as_str()).collect();
    assert_eq!(
        ids,
        vec!["task-alpha", "task-bravo", "task-charlie"],
        "identical (priority, due_date) tasks must return in id ASC"
    );
}

#[test]
fn exact_today_returns_planned_or_due_today() {
    let conn = test_conn();
    insert_task(
        &conn,
        "t1",
        "Planned today",
        "open",
        None,
        Some("2026-03-23"),
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "t2",
        "Due today no plan",
        "open",
        Some("2026-03-23"),
        None,
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "t3",
        "Due today with plan tomorrow",
        "open",
        Some("2026-03-23"),
        Some("2026-03-24"),
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "t4",
        "Due tomorrow",
        "open",
        Some("2026-03-24"),
        None,
        Some(1),
        None,
    );

    let tasks = get_exact_today_tasks(&conn, "2026-03-23", 100, 0).unwrap();
    let ids: Vec<&str> = tasks.iter().map(|t| t.core.id.as_str()).collect();
    assert!(ids.contains(&"t1"), "planned_date = today");
    assert!(ids.contains(&"t2"), "due_date = today, no planned_date");
    assert!(!ids.contains(&"t3"), "planned_date is tomorrow, not today");
    assert!(!ids.contains(&"t4"), "due tomorrow");
}

#[test]
fn count_exact_today_matches_query() {
    let conn = test_conn();
    insert_task(
        &conn,
        "t1",
        "Planned today",
        "open",
        None,
        Some("2026-03-23"),
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

    let count = count_exact_today_tasks(&conn, "2026-03-23").unwrap();
    assert_eq!(count, 2);
}

#[test]
fn high_priority_undated_excludes_planned_tasks_and_matches_count() {
    let conn = test_conn();
    insert_task(
        &conn,
        "undated-p1",
        "High priority no dates",
        "open",
        None,
        None,
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "planned-today-p1",
        "Planned today with no due date",
        "open",
        None,
        Some("2026-03-23"),
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "planned-future-p1",
        "Planned future with no due date",
        "open",
        None,
        Some("2026-03-24"),
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "undated-p3",
        "Low priority no dates",
        "open",
        None,
        None,
        Some(3),
        None,
    );

    let high_priority_undated =
        get_high_priority_undated_tasks(&conn, 100, 0).expect("high priority undated");
    let ids: Vec<&str> = high_priority_undated
        .iter()
        .map(|task| task.core.id.as_str())
        .collect();

    assert_eq!(
        ids,
        vec!["undated-p1"],
        "only priority 1/2 tasks with no due_date and no planned_date belong in high-priority undated"
    );
    assert_eq!(
        count_high_priority_undated_tasks(&conn).expect("count high priority undated"),
        ids.len() as i64,
        "count and list paths must share the same high-priority undated predicate"
    );

    let today_ids: Vec<String> = get_exact_today_tasks(&conn, "2026-03-23", 100, 0)
        .expect("today tasks")
        .into_iter()
        .map(|task| task.core.id)
        .collect();
    assert!(
        today_ids.iter().any(|id| id == "planned-today-p1"),
        "planned-today no-due work belongs in the today bucket"
    );
    assert!(
        !ids.contains(&"planned-today-p1"),
        "planned-today no-due work must not duplicate into high-priority undated"
    );
    assert!(
        !ids.contains(&"planned-future-p1"),
        "future-planned no-due work must not appear in today's high-priority undated bucket"
    );
}
