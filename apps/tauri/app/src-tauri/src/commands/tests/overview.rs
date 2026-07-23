use super::*;

/// Insert a task for overview tests with control over status, due_date, completed_at, and planned_date.
fn insert_overview_task(
    conn: &Connection,
    id: &str,
    status: &str,
    due_date: Option<&str>,
    completed_at: Option<&str>,
    planned_date: Option<&str>,
) {
    conn.execute(
        "INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at)
         VALUES ('list-overview', 'Overview', ?1, '2026-03-01T00:00:00.000Z', '2026-03-01T00:00:00.000Z')",
        params![TEST_VERSION],
    )
    .expect("insert overview list");
    // lift to canonical TaskBuilder.
    let title = format!("Task {id}");
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title(&title)
        .status(status)
        .version(TEST_VERSION)
        .created_at("2026-03-01T08:00:00Z")
        .list_id(Some("list-overview"))
        .due_date(due_date)
        .planned_date(planned_date)
        .priority(Some(3))
        .completed_at(completed_at)
        .insert(conn);
}

// ---------------------------------------------------------------------------
// query_overview_stats — empty database
// ---------------------------------------------------------------------------

#[test]
fn get_overview_empty_database_returns_all_zeros() {
    let conn = setup_sync_test_conn();

    let stats = lorvex_workflow::overview::load_overview_stats_for_bounds(
        &conn,
        "2026-03-15",
        "2026-03-14T07:00:00Z",
        "2026-03-15T07:00:00Z",
        "2026-03-08T07:00:00Z",
        "2026-03-15T07:00:00Z",
        "2026-03-01T07:00:00Z",
    )
    .expect("overview stats on empty db");

    assert_eq!(stats.open_count, 0);
    assert_eq!(stats.overdue_count, 0);
    assert_eq!(stats.today_pool_count, 0);
    assert_eq!(stats.completed_today, 0);
    assert_eq!(stats.completed_this_week, 0);
    assert_eq!(stats.completed_last_week, 0);
    assert_eq!(stats.someday_count, 0);
    assert_eq!(stats.upcoming_week_count, 0);
}

// ---------------------------------------------------------------------------
// query_overview_stats — counts
// ---------------------------------------------------------------------------

#[test]
fn get_overview_returns_correct_counts() {
    let conn = setup_sync_test_conn();

    let today = "2026-03-15";
    // today window: 2026-03-14T07:00:00Z .. 2026-03-15T07:00:00Z (PDT-like)
    let today_start = "2026-03-14T07:00:00Z";
    let today_end = "2026-03-15T07:00:00Z";
    // this-week window: 2026-03-08T07:00:00Z .. 2026-03-15T07:00:00Z
    let week_start = "2026-03-08T07:00:00Z";
    let week_end = "2026-03-15T07:00:00Z";
    // prev-week window start: 2026-03-01T07:00:00Z
    let prev_week_start = "2026-03-01T07:00:00Z";

    // Open tasks (2 open, 1 overdue, 1 in today pool via due_date, 1 upcoming)
    insert_overview_task(&conn, "t-open1", "open", Some("2026-03-15"), None, None);
    insert_overview_task(&conn, "t-open2", "open", Some("2026-03-20"), None, None);
    insert_overview_task(&conn, "t-overdue", "open", Some("2026-03-10"), None, None);
    // Upcoming: due within next 7 days after today (2026-03-16 through 2026-03-22)
    insert_overview_task(&conn, "t-upcoming", "open", Some("2026-03-18"), None, None);
    // Today pool via planned_date
    insert_overview_task(
        &conn,
        "t-planned-today",
        "open",
        Some("2026-03-25"),
        None,
        Some("2026-03-15"),
    );

    // Completed today (completed_at within today window, with due_date or planned_date <= today)
    insert_overview_task(
        &conn,
        "t-done-today",
        "completed",
        Some("2026-03-15"),
        Some("2026-03-14T12:00:00Z"),
        None,
    );
    // Completed this week but not today
    insert_overview_task(
        &conn,
        "t-done-week",
        "completed",
        Some("2026-03-10"),
        Some("2026-03-10T12:00:00Z"),
        None,
    );
    // Completed last week (between prev_week_start and week_start)
    insert_overview_task(
        &conn,
        "t-done-lastweek",
        "completed",
        Some("2026-03-05"),
        Some("2026-03-05T12:00:00Z"),
        None,
    );

    // Someday task
    insert_overview_task(&conn, "t-someday", "someday", None, None, None);

    // Cancelled task (should not appear in any count)
    insert_overview_task(
        &conn,
        "t-cancelled",
        "cancelled",
        Some("2026-03-15"),
        None,
        None,
    );

    let stats = lorvex_workflow::overview::load_overview_stats_for_bounds(
        &conn,
        today,
        today_start,
        today_end,
        week_start,
        week_end,
        prev_week_start,
    )
    .expect("overview stats with data");

    // open: t-open1, t-open2, t-overdue, t-upcoming, t-planned-today = 5
    assert_eq!(stats.open_count, 5, "open_count");
    // overdue: t-overdue (due_date 2026-03-10 < 2026-03-15) = 1
    assert_eq!(stats.overdue_count, 1, "overdue_count");
    // today pool: canonical today bucket excludes deadline-overdue work.
    //   t-open1: planned_date=NULL, due_date=2026-03-15 == today -> yes
    //   t-overdue: due_date=2026-03-10 < today -> overdue bucket, not today pool
    //   t-planned-today: planned_date=2026-03-15 <= today and due_date not overdue -> yes
    //   t-open2 / t-upcoming: future action dates -> no
    assert_eq!(stats.today_pool_count, 2, "today_pool_count");
    // completed_today: t-done-today (completed_at 2026-03-14T12:00:00Z is within today window AND
    //   due_date 2026-03-15 <= today) = 1
    assert_eq!(stats.completed_today, 1, "completed_today");
    // completed_this_week: t-done-today + t-done-week (both completed_at within week window) = 2
    assert_eq!(stats.completed_this_week, 2, "completed_this_week");
    // completed_last_week: t-done-lastweek (completed_at 2026-03-05T12:00:00Z is between prev_week_start and week_start) = 1
    assert_eq!(stats.completed_last_week, 1, "completed_last_week");
    // someday: t-someday = 1
    assert_eq!(stats.someday_count, 1, "someday_count");
    // upcoming_week: open tasks with due_date > today AND due_date <= today + 7 days (2026-03-22)
    //   t-upcoming: due_date 2026-03-18 is in range -> yes
    //   t-open2: due_date 2026-03-20 is in range -> yes
    assert_eq!(stats.upcoming_week_count, 2, "upcoming_week_count");
}

// ---------------------------------------------------------------------------
// query_overview_stats — only completed tasks, no open
// ---------------------------------------------------------------------------

#[test]
fn get_overview_no_open_tasks() {
    let conn = setup_sync_test_conn();

    insert_overview_task(
        &conn,
        "t-done",
        "completed",
        Some("2026-03-14"),
        Some("2026-03-14T10:00:00Z"),
        None,
    );

    let stats = lorvex_workflow::overview::load_overview_stats_for_bounds(
        &conn,
        "2026-03-15",
        "2026-03-14T07:00:00Z",
        "2026-03-15T07:00:00Z",
        "2026-03-08T07:00:00Z",
        "2026-03-15T07:00:00Z",
        "2026-03-01T07:00:00Z",
    )
    .expect("overview stats with no open tasks");

    assert_eq!(stats.open_count, 0);
    assert_eq!(stats.overdue_count, 0);
    assert_eq!(stats.today_pool_count, 0);
    // t-done completed_at is in both today window and this week window.
    assert_eq!(stats.completed_today, 1);
    assert_eq!(stats.completed_this_week, 1);
    assert_eq!(stats.completed_last_week, 0);
    assert_eq!(stats.someday_count, 0);
    assert_eq!(stats.upcoming_week_count, 0);
}
