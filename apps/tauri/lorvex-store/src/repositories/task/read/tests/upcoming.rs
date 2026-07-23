//! Upcoming-bucket queries: `get_upcoming_tasks`. Tests cover the
//! inclusive-from / exclusive-to date window and the open-status
//! filter.

use super::support::{get_upcoming_tasks, insert_task, test_conn, Pagination, UpcomingPredicate};

#[test]
fn upcoming_returns_tasks_in_range() {
    let conn = test_conn();
    insert_task(
        &conn,
        "t1",
        "In range planned",
        "open",
        None,
        Some("2026-03-25"),
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "t2",
        "In range due",
        "open",
        Some("2026-03-26"),
        None,
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "t3",
        "Out of range",
        "open",
        Some("2026-04-05"),
        None,
        Some(1),
        None,
    );
    insert_task(
        &conn,
        "t4",
        "Before range",
        "open",
        Some("2026-03-22"),
        None,
        Some(1),
        None,
    );

    let pred = UpcomingPredicate {
        from_date: chrono::NaiveDate::from_ymd_opt(2026, 3, 23).unwrap(),
        days: 7,
    };
    let tasks = get_upcoming_tasks(&conn, &pred, Pagination::default()).unwrap();
    let ids: Vec<&str> = tasks.iter().map(|t| t.core.id.as_str()).collect();
    assert!(ids.contains(&"t1"), "planned_date in range");
    assert!(ids.contains(&"t2"), "due_date in range");
    assert!(!ids.contains(&"t3"), "out of range");
    assert!(!ids.contains(&"t4"), "before range");
}

#[test]
fn upcoming_excludes_non_open() {
    let conn = test_conn();
    insert_task(
        &conn,
        "t1",
        "Cancelled in range",
        "cancelled",
        Some("2026-03-25"),
        None,
        Some(1),
        None,
    );

    let pred = UpcomingPredicate {
        from_date: chrono::NaiveDate::from_ymd_opt(2026, 3, 23).unwrap(),
        days: 7,
    };
    let tasks = get_upcoming_tasks(&conn, &pred, Pagination::default()).unwrap();
    assert!(tasks.is_empty());
}
