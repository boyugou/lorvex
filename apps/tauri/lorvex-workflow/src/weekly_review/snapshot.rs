//! Compact weekly-review snapshot surfaced by the MCP server.
//!
//! Drops the overdue list and the brief module's section totals; keeps
//! the four signal-bearing sections (`top_completed`, `stalled_lists`,
//! `frequently_deferred`, `someday_items`) plus the shared counts and
//! estimate summary so an AI assistant can answer "what did I get done
//! this week?" in a single tool call.

use lorvex_store::{with_deferred_read_transaction, StoreError};
use rusqlite::{params, Connection};

use super::sections::{
    deferred_items_sql, load_counts, load_stalled_lists, load_weekly_estimate_summary,
    load_weekly_review_task_items, COMPLETED_ITEMS_SQL, FREQUENTLY_DEFERRED_MIN_COUNT,
    SOMEDAY_ITEMS_SQL,
};
use super::types::{WeeklyReviewSnapshot, WeeklyReviewSnapshotLimits};
use super::validation::validate_weekly_review_snapshot_limits;
use super::window::load_weekly_review_window;

pub fn load_weekly_review_snapshot(
    conn: &Connection,
    limits: WeeklyReviewSnapshotLimits,
) -> Result<WeeklyReviewSnapshot, StoreError> {
    validate_weekly_review_snapshot_limits(limits)?;

    with_deferred_read_transaction(conn, |conn| {
        let window = load_weekly_review_window(conn)?;
        let counts = load_counts(conn, &window)?;
        let top_completed = load_weekly_review_task_items(
            conn,
            COMPLETED_ITEMS_SQL,
            params![window.start_utc, window.end_utc, limits.top_completed],
        )?;
        let stalled_lists = load_stalled_lists(conn, &window.start_utc, limits.stalled_lists)?;
        let frequently_deferred = load_weekly_review_task_items(
            conn,
            &deferred_items_sql(),
            params![FREQUENTLY_DEFERRED_MIN_COUNT, limits.frequently_deferred],
        )?;
        let someday_items =
            load_weekly_review_task_items(conn, SOMEDAY_ITEMS_SQL, params![limits.someday_items])?;
        let estimate_summary =
            load_weekly_estimate_summary(conn, &window.start_utc, &window.end_utc)?;

        Ok(WeeklyReviewSnapshot {
            window: window.model,
            counts,
            estimate_summary,
            top_completed,
            stalled_lists,
            frequently_deferred,
            someday_items,
            limits,
        })
    })
}
