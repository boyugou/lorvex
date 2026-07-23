//! Section-level SQL constants + row mappers shared by the three
//! weekly-review entry points.
//!
//! Each `pub(super) fn load_*` returns one section's rows; the public
//! entry points (`read_model` / `snapshot` / `brief`) pick which
//! subset of sections to compose. The `*_SQL` constants and the
//! `FREQUENTLY_DEFERRED_MIN_COUNT` threshold are exposed at module
//! scope so the brief module — which also needs the unfiltered
//! `total_matching` counts — can run the same `WHERE` clauses through
//! [`query_count`] without duplicating SQL strings.

use lorvex_store::{
    deferred_open_count, load_task_estimate_summary, overdue_open_count, someday_count,
};
use lorvex_store::{StoreError, TASK_ORDER_BY};
use rusqlite::{params, Connection};

use super::types::{
    WeeklyReviewCounts, WeeklyReviewEstimateSummary, WeeklyReviewStalledList, WeeklyReviewTaskItem,
};
use super::window::WeeklyReviewQueryWindow;

pub(super) const FREQUENTLY_DEFERRED_MIN_COUNT: i64 = 3;

pub(super) const COMPLETED_THIS_WEEK_COUNT_SQL: &str = "SELECT COUNT(*) FROM tasks
     WHERE status = 'completed'
       AND tasks.archived_at IS NULL
       AND completed_at >= ?1
       AND completed_at < ?2";
pub(super) const CREATED_THIS_WEEK_COUNT_SQL: &str = "SELECT COUNT(*) FROM tasks
     WHERE tasks.archived_at IS NULL
       AND created_at >= ?1
       AND created_at < ?2";
pub(super) const COMPLETED_ITEMS_SQL: &str =
    "SELECT id, title, list_id, status, completed_at, due_date, defer_count
     FROM tasks
     WHERE status = 'completed'
       AND tasks.archived_at IS NULL
       AND completed_at >= ?1
       AND completed_at < ?2
     ORDER BY completed_at DESC, id ASC
     LIMIT ?3";
pub(super) const STALLED_LISTS_SQL: &str = "SELECT l.id, l.name, l.icon, l.color,
            COUNT(t.id) AS open_task_count,
            MAX(datetime(t.updated_at)) AS last_activity
     FROM lists l
     JOIN tasks t ON t.list_id = l.id AND t.status = 'open' AND t.archived_at IS NULL
     GROUP BY l.id
     HAVING last_activity < datetime(?1)
     ORDER BY open_task_count DESC, last_activity ASC, l.id ASC
     LIMIT ?2";
pub(super) const STALLED_TOTAL_SQL: &str = "SELECT COUNT(*) FROM (
        SELECT l.id
        FROM lists l
        JOIN tasks t ON t.list_id = l.id AND t.status = 'open' AND t.archived_at IS NULL
        GROUP BY l.id
        HAVING MAX(datetime(t.updated_at)) < datetime(?1)
    )";
pub(super) const OVERDUE_ITEMS_SQL: &str =
    "SELECT id, title, list_id, status, completed_at, due_date, defer_count
     FROM tasks
     WHERE status = 'open'
       AND due_date IS NOT NULL
       AND due_date < ?1
       AND tasks.archived_at IS NULL
     ORDER BY due_date ASC, priority_effective ASC, id ASC
     LIMIT ?2";
pub(super) const SOMEDAY_ITEMS_SQL: &str =
    "SELECT id, title, list_id, status, completed_at, due_date, defer_count
     FROM tasks
     WHERE status = 'someday' AND tasks.archived_at IS NULL
     ORDER BY created_at DESC, id ASC
     LIMIT ?1";

pub(super) fn deferred_items_sql() -> String {
    format!(
        "SELECT id, title, list_id, status, completed_at, due_date, defer_count
         FROM tasks
         WHERE status = 'open' AND tasks.archived_at IS NULL AND defer_count >= ?1
         ORDER BY defer_count DESC, {TASK_ORDER_BY}
         LIMIT ?2"
    )
}

pub(super) fn query_count(
    conn: &Connection,
    sql: &str,
    params: impl rusqlite::Params,
) -> Result<i64, StoreError> {
    Ok(conn.query_row(sql, params, |row| row.get(0))?)
}

fn task_item_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<WeeklyReviewTaskItem> {
    Ok(WeeklyReviewTaskItem {
        id: row.get(0)?,
        title: row.get(1)?,
        list_id: row.get(2)?,
        status: row.get(3)?,
        completed_at: row.get(4)?,
        due_date: row.get(5)?,
        defer_count: row.get(6)?,
    })
}

pub(super) fn load_weekly_review_task_items(
    conn: &Connection,
    sql: &str,
    params: impl rusqlite::Params,
) -> Result<Vec<WeeklyReviewTaskItem>, StoreError> {
    let mut stmt = conn.prepare_cached(sql)?;
    let rows = stmt
        .query_map(params, task_item_from_row)?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(rows)
}

pub(super) fn load_stalled_lists(
    conn: &Connection,
    start_utc: &str,
    limit: u32,
) -> Result<Vec<WeeklyReviewStalledList>, StoreError> {
    let mut stmt = conn.prepare_cached(STALLED_LISTS_SQL)?;
    let rows = stmt
        .query_map(params![start_utc, limit], |row| {
            Ok(WeeklyReviewStalledList {
                id: row.get(0)?,
                name: row.get(1)?,
                icon: row.get(2)?,
                color: row.get(3)?,
                open_task_count: row.get(4)?,
                last_activity: row.get(5)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(rows)
}

pub(super) fn load_weekly_estimate_summary(
    conn: &Connection,
    start_utc: &str,
    end_utc: &str,
) -> Result<WeeklyReviewEstimateSummary, StoreError> {
    let estimate_summary = load_task_estimate_summary(conn, start_utc, end_utc)?;
    Ok(WeeklyReviewEstimateSummary {
        completed_total: estimate_summary.completed_total,
        completed_with_estimate_count: estimate_summary.completed_with_estimate_count,
        estimate_coverage_ratio: estimate_summary.estimate_coverage_ratio,
    })
}

pub(super) fn load_counts(
    conn: &Connection,
    window: &WeeklyReviewQueryWindow,
) -> Result<WeeklyReviewCounts, StoreError> {
    Ok(WeeklyReviewCounts {
        completed_this_week: query_count(
            conn,
            COMPLETED_THIS_WEEK_COUNT_SQL,
            params![window.start_utc, window.end_utc],
        )?,
        created_this_week: query_count(
            conn,
            CREATED_THIS_WEEK_COUNT_SQL,
            params![window.start_utc, window.end_utc],
        )?,
        overdue_open: overdue_open_count(conn, &window.to_day)?,
        deferred_open: deferred_open_count(conn, FREQUENTLY_DEFERRED_MIN_COUNT)?,
        someday: someday_count(conn)?,
    })
}
