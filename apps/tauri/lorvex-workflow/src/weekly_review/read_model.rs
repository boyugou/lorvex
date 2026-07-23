//! Full weekly-review read model surfaced by the desktop app.
//!
//! Composes every section the Weekly Review view needs:
//! `completed_this_week`, `stalled_lists`, `frequently_deferred`,
//! `overdue_tasks`, `someday_items`, plus the shared counts and
//! estimate-coverage summary. Each section's row cap is validated up
//! front; SQL only runs once every cap passes.

use lorvex_store::{with_deferred_read_transaction, StoreError};
use rusqlite::{params, Connection};

use super::sections::{
    deferred_items_sql, load_counts, load_stalled_lists, load_weekly_estimate_summary,
    load_weekly_review_task_items, COMPLETED_ITEMS_SQL, FREQUENTLY_DEFERRED_MIN_COUNT,
    OVERDUE_ITEMS_SQL, SOMEDAY_ITEMS_SQL,
};
use super::types::{WeeklyReviewLimits, WeeklyReviewReadModel};
use super::validation::validate_weekly_review_limits;
use super::window::load_weekly_review_window;

pub fn load_weekly_review(
    conn: &Connection,
    limits: WeeklyReviewLimits,
) -> Result<WeeklyReviewReadModel, StoreError> {
    validate_weekly_review_limits(limits)?;

    with_deferred_read_transaction(conn, |conn| {
        let window = load_weekly_review_window(conn)?;
        let counts = load_counts(conn, &window)?;
        let completed_this_week = load_weekly_review_task_items(
            conn,
            COMPLETED_ITEMS_SQL,
            params![window.start_utc, window.end_utc, limits.completed_this_week],
        )?;
        let stalled_lists = load_stalled_lists(conn, &window.start_utc, limits.stalled_lists)?;
        let frequently_deferred = load_weekly_review_task_items(
            conn,
            &deferred_items_sql(),
            params![FREQUENTLY_DEFERRED_MIN_COUNT, limits.frequently_deferred],
        )?;
        let overdue_tasks = load_weekly_review_task_items(
            conn,
            OVERDUE_ITEMS_SQL,
            params![window.to_day, limits.overdue_tasks],
        )?;
        let someday_items =
            load_weekly_review_task_items(conn, SOMEDAY_ITEMS_SQL, params![limits.someday_items])?;
        let estimate_summary =
            load_weekly_estimate_summary(conn, &window.start_utc, &window.end_utc)?;

        Ok(WeeklyReviewReadModel {
            window: window.model,
            counts,
            estimate_summary,
            completed_this_week,
            stalled_lists,
            frequently_deferred,
            overdue_tasks,
            someday_items,
            limits,
        })
    })
}
