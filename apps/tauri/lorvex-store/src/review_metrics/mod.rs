use crate::StoreError;
use lorvex_domain::naming::{STATUS_OPEN, STATUS_SOMEDAY};
use rusqlite::{params, Connection};

/// Open + non-archived tasks whose `due_date` lex-order precedes
/// `today_ymd` (canonical `YYYY-MM-DD`). Single canonical
/// implementation shared by every weekly-review surface — Tauri,
/// CLI, MCP brief, MCP snapshot — so the overdue count never drifts
/// across the four read paths.
///
/// `today_ymd` MUST be in the user's local timezone YMD (computed via
/// `today_ymd_for_conn`) — passing a UTC YMD on a tz-shifted device
/// gives off-by-one results at the day boundary.
pub fn overdue_open_count(conn: &Connection, today_ymd: &str) -> Result<i64, StoreError> {
    let count: i64 = conn
        .prepare_cached(
            "SELECT COUNT(*) FROM tasks \
             WHERE status = ?1 \
               AND archived_at IS NULL \
               AND due_date IS NOT NULL \
               AND due_date < ?2",
        )?
        .query_row(params![STATUS_OPEN, today_ymd], |row| row.get(0))?;
    Ok(count)
}

/// Open + non-archived tasks deferred at least `min_count` times.
/// Used as the "frequently deferred" callout in the weekly review;
/// the threshold is fixed at 3 in the call sites today, but the
/// helper takes it as a param so a future tune doesn't fork the SQL.
pub fn deferred_open_count(conn: &Connection, min_count: i64) -> Result<i64, StoreError> {
    let count: i64 = conn
        .prepare_cached(
            "SELECT COUNT(*) FROM tasks \
             WHERE status = ?1 \
               AND archived_at IS NULL \
               AND defer_count >= ?2",
        )?
        .query_row(params![STATUS_OPEN, min_count], |row| row.get(0))?;
    Ok(count)
}

/// Non-archived tasks parked in the someday bucket. The someday
/// status is the AI's "active backlog" channel; the count is read by
/// the weekly-review surfaces as part of the orientation block.
pub fn someday_count(conn: &Connection) -> Result<i64, StoreError> {
    let count: i64 = conn
        .prepare_cached("SELECT COUNT(*) FROM tasks WHERE status = ?1 AND archived_at IS NULL")?
        .query_row(params![STATUS_SOMEDAY], |row| row.get(0))?;
    Ok(count)
}

#[derive(Debug, Clone, PartialEq)]
pub struct TaskEstimateSummary {
    pub completed_total: i64,
    pub completed_with_estimate_count: i64,
    pub estimate_coverage_ratio: Option<f64>,
}

pub fn load_task_estimate_summary(
    conn: &Connection,
    window_start_utc: &str,
    window_end_utc: &str,
) -> Result<TaskEstimateSummary, StoreError> {
    let (completed_total, completed_with_estimate_count): (i64, i64) = conn.query_row(
        "
        SELECT
          COUNT(*) AS completed_total,
          COALESCE(SUM(CASE
            WHEN estimated_minutes IS NOT NULL AND estimated_minutes > 0 THEN 1
            ELSE 0
          END), 0) AS completed_with_estimate_count
        FROM tasks
        WHERE status = 'completed'
          AND archived_at IS NULL
          AND completed_at IS NOT NULL
          -- drop datetime wrappers so
          -- idx_tasks_completed_at can serve this scan. completed_at
          -- is canonical RFC3339 millisecond-Z (lex order = chronological).
          AND completed_at >= ?1
          AND completed_at < ?2
        ",
        params![window_start_utc, window_end_utc],
        |row| Ok((row.get(0)?, row.get(1)?)),
    )?;

    let estimate_coverage_ratio = (completed_total > 0)
        .then(|| completed_with_estimate_count as f64 / completed_total as f64);

    Ok(TaskEstimateSummary {
        completed_total,
        completed_with_estimate_count,
        estimate_coverage_ratio,
    })
}

#[cfg(test)]
mod tests;
