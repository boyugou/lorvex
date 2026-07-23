//! Today-view bucketed queries — the today pool, today-view overdue, and
//! the high-priority undated bucket the MCP `get_todays_tasks` tool surfaces.

use lorvex_domain::naming::STATUS_OPEN;
use lorvex_domain::query::*;
use rusqlite::{params, Connection};

use crate::error::StoreError;

use super::buckets::{overdue_bucket_predicate, today_pool_bucket_predicate};
use super::{count_overdue_tasks, task_from_row, TaskRow, TASK_COLUMNS, TASK_ORDER_BY};

/// Normalize an ISO date string to the canonical `YYYY-MM-DD` shape SQLite
/// uses for lexicographic date comparisons.
///
/// Issue #3324 (B2): `count_overdue_tasks_for_today` parsed + reformatted
/// `today` while sibling `get_overdue_tasks_for_today` passed the raw
/// string straight into the SQL. A caller that handed us `"2026-5-5"` or
/// `"2026-05-05T00:00:00Z"` would then produce a count/rows skew because
/// only one side of the pair was canonicalized before lex-comparison.
/// Every function in this file that takes a `today: &str` and uses it in
/// a SQL date comparison routes through this helper so the comparison
/// operand is always the same shape.
fn normalize_today(today: &str) -> Result<String, StoreError> {
    lorvex_domain::time::parse_iso_date(today)
        .map(|d| d.format("%Y-%m-%d").to_string())
        .map_err(|error| StoreError::Validation(format!("invalid today date {today:?}: {error}")))
}

/// Get tasks in the canonical today-pool bucket.
///
/// Returns open tasks where:
/// - `planned_date <= date` while not already deadline-overdue, or
/// - `planned_date IS NULL AND due_date = date`
///
/// Ordered by `priority_effective ASC, due_date ASC`.
pub fn get_today_tasks(
    conn: &Connection,
    pred: &TodayPredicate,
    page: Pagination,
) -> Result<Vec<TaskRow>, StoreError> {
    // the canonical `TASK_ORDER_BY` appends `id ASC`
    // as a deterministic tiebreaker so pagination never skips or
    // duplicates rows that share the same (priority_effective, due_date).
    // Without it, two tasks with identical sort keys can flicker between
    // pages.
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let date_str = pred.date.format("%Y-%m-%d").to_string();
    let sql = SQL.get_or_init(|| {
        let today_pool = today_pool_bucket_predicate("tasks", "?1");
        format!(
            "SELECT {TASK_COLUMNS} FROM tasks \
             WHERE status = '{STATUS_OPEN}' \
             AND tasks.archived_at IS NULL \
             AND {today_pool} \
             ORDER BY {TASK_ORDER_BY} \
             LIMIT ?2 OFFSET ?3"
        )
    });
    let mut stmt = conn.prepare_cached(sql)?;
    let rows = stmt
        .query_map(params![date_str, page.limit, page.offset], task_from_row)?
        .collect::<rusqlite::Result<_>>()?;
    Ok(rows)
}

/// Count tasks in the canonical today-pool bucket.
pub fn count_today_tasks(conn: &Connection, pred: &TodayPredicate) -> Result<i64, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let date_str = pred.date.format("%Y-%m-%d").to_string();
    let sql = SQL.get_or_init(|| {
        let today_pool = today_pool_bucket_predicate("tasks", "?1");
        format!(
            "SELECT COUNT(*) FROM tasks \
             WHERE status = '{STATUS_OPEN}' \
             AND tasks.archived_at IS NULL \
             AND {today_pool}"
        )
    });
    Ok(conn
        .prepare_cached(sql)?
        .query_row(params![date_str], |row| row.get(0))?)
}

/// Get overdue tasks for the today view.
///
/// Returns open tasks where the external due date is already overdue.
/// Ordered by `TASK_ORDER_BY` (priority_effective ASC, due_date ASC NULLS LAST, id ASC).
///
/// This is the canonical "overdue" bucket used by the MCP `get_todays_tasks` tool.
pub fn get_overdue_tasks_for_today(
    conn: &Connection,
    today: &str,
    limit: u32,
    offset: u32,
) -> Result<Vec<TaskRow>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    // #3324 B2: normalize before binding so the SQL operand matches the
    // shape `count_overdue_tasks_for_today` compares against.
    let today = normalize_today(today)?;
    let sql = SQL.get_or_init(|| {
        let overdue = overdue_bucket_predicate("tasks", "?1");
        format!(
            "SELECT {TASK_COLUMNS} FROM tasks \
             WHERE status = '{STATUS_OPEN}' AND tasks.archived_at IS NULL AND {overdue} \
             ORDER BY {TASK_ORDER_BY} \
             LIMIT ?2 OFFSET ?3"
        )
    });
    let mut stmt = conn.prepare_cached(sql)?;
    let rows = stmt
        .query_map(params![today, limit, offset], task_from_row)?
        .collect::<rusqlite::Result<_>>()?;
    Ok(rows)
}

/// Count overdue tasks for the today view.
pub fn count_overdue_tasks_for_today(conn: &Connection, today: &str) -> Result<i64, StoreError> {
    // #3324 B2: parse-and-reformat happens inside `count_overdue_tasks`
    // via the `NaiveDate` round-trip in `OverduePredicate`. The
    // sibling `get_overdue_tasks_for_today` was the asymmetric one and
    // is now normalized via `normalize_today` so the get/count pair
    // see the same canonical operand.
    let as_of_date = lorvex_domain::time::parse_iso_date(today).map_err(|error| {
        StoreError::Validation(format!("invalid today date {today:?}: {error}"))
    })?;
    count_overdue_tasks(conn, &OverduePredicate { as_of_date })
}

/// Get tasks in the canonical today-pool bucket.
///
/// Returns open tasks where `planned_date <= today` while not already
/// deadline-overdue, or (`planned_date IS NULL` and `due_date = today`).
/// Ordered by `priority_effective ASC, due_time ASC NULLS LAST, created_at DESC, id ASC`.
///
/// This is the canonical "today pool" bucket used by the MCP `get_todays_tasks` tool.
///
/// appends `id ASC` as the deterministic tiebreaker.
/// HLC re-stamps from `apply_task_update` overwrite `created_at` only
/// when the row's status flips through transition columns; everything
/// else (priority bumps, body edits, defer counts) leaves `created_at`
/// alone but advances `version`. Two siblings sharing the same
/// (priority_effective, due_time, created_at) — common after a bulk
/// import or assistant batch — would otherwise flicker between LIMIT
/// pages depending on rowid hashing. Same hazard `TASK_ORDER_BY` was
/// retro-fitted to defeat in #2343 / #2742.
pub fn get_exact_today_tasks(
    conn: &Connection,
    today: &str,
    limit: u32,
    offset: u32,
) -> Result<Vec<TaskRow>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    // #3324 B2: normalize before binding so the SQL operand matches the
    // shape `count_exact_today_tasks` compares against (which routes
    // through `parse_iso_date` + `format`).
    let today = normalize_today(today)?;
    let sql = SQL.get_or_init(|| {
        let today_pool = today_pool_bucket_predicate("tasks", "?1");
        // #3319: today-view subsort diverges from the canonical
        // `TASK_ORDER_BY` (priority_effective, due_date, id) on
        // purpose. Every row in this bucket already shares the same
        // calendar day by construction (the today-pool predicate
        // gates on planned_date/due_date == today), so the canonical
        // `due_date` axis is degenerate here. We instead substitute
        // `due_time` so deadline-bearing tasks bubble up by time-of-
        // day, then `created_at DESC` so the most recently captured
        // task lands above older equal-priority siblings — the user
        // expectation when planning the day. `id ASC` remains the
        // deterministic tiebreaker (#2343 / #2742) for stable
        // OFFSET pagination.
        format!(
            "SELECT {TASK_COLUMNS} FROM tasks \
             WHERE status = '{STATUS_OPEN}' \
               AND tasks.archived_at IS NULL \
               AND {today_pool} \
             ORDER BY priority_effective ASC, due_time ASC NULLS LAST, created_at DESC, id ASC \
             LIMIT ?2 OFFSET ?3"
        )
    });
    let mut stmt = conn.prepare_cached(sql)?;
    let rows = stmt
        .query_map(params![today, limit, offset], task_from_row)?
        .collect::<rusqlite::Result<_>>()?;
    Ok(rows)
}

/// Count tasks in the canonical today-pool bucket.
pub fn count_exact_today_tasks(conn: &Connection, today: &str) -> Result<i64, StoreError> {
    let date = lorvex_domain::time::parse_iso_date(today).map_err(|error| {
        StoreError::Validation(format!("invalid today date {today:?}: {error}"))
    })?;
    count_today_tasks(conn, &TodayPredicate { date })
}

/// Get high-priority undated tasks.
///
/// Returns open tasks with `due_date IS NULL`, `planned_date IS NULL`,
/// `priority IS NOT NULL`, and `priority <= 2`.
/// Ordered by `priority_effective ASC, created_at DESC, id ASC`.
///
/// This is the canonical "high priority undated" bucket used by the MCP
/// `get_todays_tasks` tool.
///
/// `id ASC` tiebreaker for the same reason as
/// `get_exact_today_tasks` above — two priority-1 undated tasks
/// captured in the same second would otherwise flicker between LIMIT
/// pages.
pub fn get_high_priority_undated_tasks(
    conn: &Connection,
    limit: u32,
    offset: u32,
) -> Result<Vec<TaskRow>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        // #3319: this bucket diverges from the canonical
        // `TASK_ORDER_BY`. Every row gates on `due_date IS NULL` and
        // `planned_date IS NULL`, so the canonical `due_date ASC NULLS
        // LAST` axis is degenerate and dropped. We substitute
        // `created_at DESC` so a freshly captured P1/P2 idea surfaces
        // above older equal-priority siblings — the user expectation
        // for the "high priority undated" rail in the today view.
        // `id ASC` remains the
        // deterministic tiebreaker.
        format!(
            "SELECT {TASK_COLUMNS} FROM tasks \
             WHERE status = '{STATUS_OPEN}' \
               AND tasks.archived_at IS NULL \
               AND due_date IS NULL AND planned_date IS NULL \
               AND priority IS NOT NULL AND priority <= 2 \
             ORDER BY priority_effective ASC, created_at DESC, id ASC \
             LIMIT ?1 OFFSET ?2"
        )
    });
    let mut stmt = conn.prepare_cached(sql)?;
    let rows = stmt
        .query_map(params![limit, offset], task_from_row)?
        .collect::<rusqlite::Result<_>>()?;
    Ok(rows)
}

/// Count high-priority undated tasks.
pub fn count_high_priority_undated_tasks(conn: &Connection) -> Result<i64, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!(
            "SELECT COUNT(*) FROM tasks \
             WHERE status = '{STATUS_OPEN}' \
               AND tasks.archived_at IS NULL \
               AND due_date IS NULL AND planned_date IS NULL \
               AND priority IS NOT NULL AND priority <= 2"
        )
    });
    Ok(conn.prepare_cached(sql)?.query_row([], |row| row.get(0))?)
}
