//! Snapshot composition for [`super::types::OverviewSnapshot`].
//!
//! Wraps the per-section loaders, the stats aggregate, and the streak
//! cache into a single deferred read transaction so every count and
//! list reflects the same database snapshot.

use lorvex_store::repositories::task::read;
use lorvex_store::{with_deferred_read_transaction, StoreError};
use rusqlite::Connection;

use crate::timezone;

use super::sections::{load_current_focus_summary, load_habit_summary, load_overview_lists};
use super::stats::load_overview_stats_for_bounds;
use super::streak::query_completion_streak;
use super::types::{OverviewLimits, OverviewSnapshot};

pub fn load_overview_snapshot(
    conn: &Connection,
    limits: OverviewLimits,
) -> Result<OverviewSnapshot, StoreError> {
    with_deferred_read_transaction(conn, |conn| {
        let today = timezone::today_ymd_for_conn(conn)?;
        let today_window = timezone::trailing_day_window_utc_bounds_for_conn(conn, 1)?;
        let review_window = timezone::trailing_day_window_utc_bounds_for_conn(conn, 7)?;
        let prev_week_window = timezone::trailing_day_window_utc_bounds_for_conn(conn, 14)?;
        let timezone_name = timezone::active_timezone_name(conn)?;

        let mut stats = load_overview_stats_for_bounds(
            conn,
            &today,
            &today_window.start_utc,
            &today_window.end_utc,
            &review_window.start_utc,
            &review_window.end_utc,
            &prev_week_window.start_utc,
        )?;
        let streak = query_completion_streak(conn, &today, timezone_name.as_deref())?;
        stats.completion_streak = streak.count;
        stats.streak_active_today = streak.active_today;

        let lists_page = load_overview_lists(conn, limits.lists)?;
        let top_by_priority = read::get_open_tasks_by_priority(conn, limits.top_tasks)?;
        let recently_completed =
            read::get_recently_completed_tasks(conn, limits.recently_completed)?;
        let current_focus = load_current_focus_summary(conn, &today)?;
        let habits = load_habit_summary(conn, &today)?;

        Ok(OverviewSnapshot {
            date: today,
            stats,
            lists_truncated: lists_page.truncated,
            lists_total: lists_page.total,
            lists: lists_page.rows,
            top_by_priority,
            recently_completed,
            current_focus,
            habits,
        })
    })
}
