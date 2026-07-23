//! Single-SQL aggregate that produces every count in
//! [`OverviewStats`] except the streak (which lives in
//! [`super::streak`] because it needs a multi-row walk).
//!
//! The five `SUM(CASE …)` branches and the `count_open_task_day_buckets`
//! call share one prepared-statement cache slot via `OnceLock<String>`
//! so the same statement handle services every dashboard refresh.

use lorvex_domain::naming::{STATUS_COMPLETED, STATUS_OPEN, STATUS_SOMEDAY};
use lorvex_store::repositories::task::read;
use lorvex_store::StoreError;
use rusqlite::{params, Connection};

use super::types::OverviewStats;

pub fn load_overview_stats_for_bounds(
    conn: &Connection,
    today: &str,
    today_start_utc: &str,
    today_end_utc: &str,
    review_window_start_utc: &str,
    review_window_end_utc: &str,
    prev_week_start_utc: &str,
) -> Result<OverviewStats, StoreError> {
    let today_date = lorvex_domain::time::parse_iso_date(today)
        .map_err(|_| StoreError::Validation(format!("invalid overview day '{today}'")))?;

    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let (
        open_count,
        completed_today,
        completed_this_week,
        completed_last_week,
        someday_count,
    ): (i64, i64, i64, i64, i64) = conn
        .prepare_cached(SQL.get_or_init(|| {
            format!(
                "SELECT \
                 SUM(CASE WHEN status = '{STATUS_OPEN}' THEN 1 ELSE 0 END), \
                 SUM(CASE WHEN status = '{STATUS_COMPLETED}' AND completed_at >= ?1 AND completed_at < ?2 THEN 1 ELSE 0 END), \
                 SUM(CASE WHEN status = '{STATUS_COMPLETED}' AND completed_at >= ?3 AND completed_at < ?4 THEN 1 ELSE 0 END), \
                 SUM(CASE WHEN status = '{STATUS_COMPLETED}' AND completed_at >= ?5 AND completed_at < ?3 THEN 1 ELSE 0 END), \
                 SUM(CASE WHEN status = '{STATUS_SOMEDAY}' THEN 1 ELSE 0 END) \
                 FROM tasks WHERE archived_at IS NULL"
            )
        }))?
        .query_row(
            params![
                today_start_utc,
                today_end_utc,
                review_window_start_utc,
                review_window_end_utc,
                prev_week_start_utc
            ],
            |row| {
                Ok((
                    row.get::<_, Option<i64>>(0)?.unwrap_or(0),
                    row.get::<_, Option<i64>>(1)?.unwrap_or(0),
                    row.get::<_, Option<i64>>(2)?.unwrap_or(0),
                    row.get::<_, Option<i64>>(3)?.unwrap_or(0),
                    row.get::<_, Option<i64>>(4)?.unwrap_or(0),
                ))
            },
        )?;

    let day_buckets = read::count_open_task_day_buckets(conn, today_date, 7)?;

    Ok(OverviewStats {
        open_count,
        overdue_count: day_buckets.overdue,
        today_pool_count: day_buckets.today_pool,
        attention_count: day_buckets.overdue + day_buckets.today_pool,
        upcoming_week_count: day_buckets.upcoming,
        completed_today,
        completed_this_week,
        completed_last_week,
        someday_count,
        completion_streak: 0,
        streak_active_today: false,
    })
}
