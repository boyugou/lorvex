pub(super) use crate::error::StoreError;
pub(super) use crate::repositories::task::read::{
    count_exact_today_tasks, count_high_priority_undated_tasks, count_open_task_day_buckets,
    count_overdue_tasks_for_today, get_exact_today_tasks, get_high_priority_undated_tasks,
    get_list_tasks_with_recent_completed, get_overdue_tasks, get_overdue_tasks_for_today, get_task,
    get_today_tasks, get_upcoming_tasks, list_tasks, search_tasks, search_tasks_with_fallback,
    BlockingFilter, DateFilter, ListTasksQuery, OpenTaskDayBucketCounts, SortDirection,
    TaskListSortBy, TaskScheduling, TaskSchedulingFields, TaskStatusListFilter, TASK_ORDER_BY,
};
pub(super) use crate::test_support::test_conn;
pub(super) use lorvex_domain::query::{
    OverduePredicate, Pagination, SearchPredicate, TodayPredicate, UpcomingPredicate,
};
pub(super) use rusqlite::{params, Connection};

/// Insert a minimal task for testing.
#[allow(clippy::too_many_arguments)]
pub(super) fn insert_task(
    conn: &Connection,
    id: &str,
    title: &str,
    status: &str,
    due_date: Option<&str>,
    planned_date: Option<&str>,
    priority: Option<i64>,
    list_id: Option<&str>,
) {
    let resolved_list_id = list_id.unwrap_or_else(|| {
        insert_list(conn, "default-list", "Default");
        "default-list"
    });
    conn.execute(
        "INSERT INTO tasks (id, title, status, due_date, planned_date, priority, list_id, \
         version, created_at, updated_at, defer_count) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, \
         '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', 0)",
        params![
            id,
            title,
            status,
            due_date,
            planned_date,
            priority,
            resolved_list_id
        ],
    )
    .expect("insert task");
}

/// Helper: insert a list for testing.
pub(super) fn insert_list(conn: &Connection, id: &str, name: &str) {
    conn.execute(
        "INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) \
         VALUES (?1, ?2, '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')",
        params![id, name],
    )
    .expect("insert list");
}

/// Helper: insert a task with completed_at for retention tests.
pub(super) fn insert_task_with_completed(
    conn: &Connection,
    id: &str,
    title: &str,
    status: &str,
    list_id: &str,
    completed_at: Option<&str>,
) {
    conn.execute(
        "INSERT INTO tasks (id, title, status, list_id, completed_at, \
         version, created_at, updated_at, defer_count) \
         VALUES (?1, ?2, ?3, ?4, ?5, \
         '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', 0)",
        params![id, title, status, list_id, completed_at],
    )
    .expect("insert task with completed_at");
}
