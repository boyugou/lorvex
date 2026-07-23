//! Upcoming-task read paths backing the `UpcomingPredicate` query.

use lorvex_domain::naming::STATUS_OPEN;
use lorvex_domain::query::*;
use rusqlite::{params, Connection};

use crate::error::StoreError;

use super::buckets::upcoming_bucket_predicate;
use super::{task_from_row, TaskRow, TASK_COLUMNS};

/// Get upcoming tasks in a date range.
///
/// Returns open tasks whose effective action date (`planned_date` when present,
/// otherwise `due_date`) falls strictly after `from_date` and on or before
/// `from_date + days`, while excluding tasks that already belong to the
/// overdue or today-pool buckets.
/// Ordered by `COALESCE(planned_date, due_date) ASC, priority_effective ASC, due_time ASC NULLS LAST`.
pub fn get_upcoming_tasks(
    conn: &Connection,
    pred: &UpcomingPredicate,
    page: Pagination,
) -> Result<Vec<TaskRow>, StoreError> {
    let from = pred.from_date.format("%Y-%m-%d").to_string();
    // `id ASC` tiebreaker — two tasks written in the
    // same tx share `created_at` to the microsecond.
    //
    // #3319: this view's ORDER BY diverges from the canonical
    // `TASK_ORDER_BY` because the upcoming rail groups by action
    // date first (the calendar-day grouping the UI renders as
    // section headers), then by priority within the day, then by
    // time-of-day. Within a `(date, priority, due_time)` triple we
    // surface the most recently captured task first
    // (`created_at DESC`) so just-added items are visible without
    // scrolling. `id ASC` is the deterministic OFFSET-pagination
    // tiebreaker.
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let to = (pred.from_date + chrono::Duration::days(i64::from(pred.days)))
        .format("%Y-%m-%d")
        .to_string();
    let sql = SQL.get_or_init(|| {
        let upcoming = upcoming_bucket_predicate("tasks", "?1", "?2");
        format!(
            "SELECT {TASK_COLUMNS} FROM tasks \
             WHERE status = '{STATUS_OPEN}' \
             AND tasks.archived_at IS NULL \
             AND {upcoming} \
             ORDER BY COALESCE(planned_date, due_date) ASC, priority_effective ASC, due_time ASC NULLS LAST, created_at DESC, id ASC \
             LIMIT ?3 OFFSET ?4"
        )
    });
    let mut stmt = conn.prepare_cached(sql)?;
    let rows = stmt
        .query_map(params![from, to, page.limit, page.offset], task_from_row)?
        .collect::<rusqlite::Result<_>>()?;
    Ok(rows)
}

/// Count upcoming tasks matching the predicate (without fetching rows).
///
/// Same WHERE clause as `get_upcoming_tasks`, but returns only the count.
/// Useful when the caller needs a total before applying LIMIT/OFFSET.
pub fn count_upcoming_tasks(
    conn: &Connection,
    pred: &UpcomingPredicate,
) -> Result<i64, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let from = pred.from_date.format("%Y-%m-%d").to_string();
    let to = (pred.from_date + chrono::Duration::days(i64::from(pred.days)))
        .format("%Y-%m-%d")
        .to_string();
    let sql = SQL.get_or_init(|| {
        let upcoming = upcoming_bucket_predicate("tasks", "?1", "?2");
        format!(
            "SELECT COUNT(*) FROM tasks \
             WHERE status = '{STATUS_OPEN}' \
             AND tasks.archived_at IS NULL \
             AND {upcoming}"
        )
    });
    Ok(conn
        .prepare_cached(sql)?
        .query_row(params![from, to], |row| row.get(0))?)
}
