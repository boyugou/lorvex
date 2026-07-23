//! Conversational "what changed this week?" briefing for the AI.
//!
//! Mirrors the snapshot's section selection but carries per-section
//! `total_matching` counts inside `WeeklyReviewBriefSectionMeta` so
//! the assistant can phrase coverage truthfully ("12 completed, 5
//! shown") instead of silently truncating. `overdue_count` ships as a
//! scalar rather than a list because the brief never surfaces the
//! overdue rows themselves — knowing the count is enough.

use lorvex_store::{
    deferred_open_count, overdue_open_count, someday_count, with_deferred_read_transaction,
    StoreError,
};
use rusqlite::{params, Connection};

use super::sections::{
    deferred_items_sql, load_stalled_lists, load_weekly_estimate_summary,
    load_weekly_review_task_items, query_count, COMPLETED_ITEMS_SQL, COMPLETED_THIS_WEEK_COUNT_SQL,
    CREATED_THIS_WEEK_COUNT_SQL, FREQUENTLY_DEFERRED_MIN_COUNT, SOMEDAY_ITEMS_SQL,
    STALLED_TOTAL_SQL,
};
use super::types::{
    WeeklyReviewBrief, WeeklyReviewBriefLimits, WeeklyReviewBriefSectionEntry,
    WeeklyReviewBriefSectionMeta,
};
use super::validation::validate_weekly_review_brief_limits;
use super::window::load_weekly_review_window;

const fn section_entry(
    limit: u32,
    total_matching: i64,
    returned: usize,
) -> WeeklyReviewBriefSectionEntry {
    WeeklyReviewBriefSectionEntry {
        limit,
        total_matching,
        returned,
        truncated: total_matching > returned as i64,
    }
}

pub fn load_weekly_review_brief(
    conn: &Connection,
    limits: WeeklyReviewBriefLimits,
) -> Result<WeeklyReviewBrief, StoreError> {
    validate_weekly_review_brief_limits(limits)?;

    with_deferred_read_transaction(conn, |conn| {
        let window = load_weekly_review_window(conn)?;
        let completed_total = query_count(
            conn,
            COMPLETED_THIS_WEEK_COUNT_SQL,
            params![window.start_utc, window.end_utc],
        )?;
        let completed_this_week = load_weekly_review_task_items(
            conn,
            COMPLETED_ITEMS_SQL,
            params![window.start_utc, window.end_utc, limits.completed_this_week],
        )?;
        let stalled_total = query_count(conn, STALLED_TOTAL_SQL, params![window.start_utc])?;
        let stalled_lists = load_stalled_lists(conn, &window.start_utc, limits.stalled_lists)?;
        let deferred_total = deferred_open_count(conn, FREQUENTLY_DEFERRED_MIN_COUNT)?;
        let frequently_deferred = load_weekly_review_task_items(
            conn,
            &deferred_items_sql(),
            params![FREQUENTLY_DEFERRED_MIN_COUNT, limits.frequently_deferred],
        )?;
        let overdue_count = overdue_open_count(conn, &window.to_day)?;
        let someday_total = someday_count(conn)?;
        let someday_items =
            load_weekly_review_task_items(conn, SOMEDAY_ITEMS_SQL, params![limits.someday_items])?;
        let created_this_week = query_count(
            conn,
            CREATED_THIS_WEEK_COUNT_SQL,
            params![window.start_utc, window.end_utc],
        )?;
        let estimate_summary =
            load_weekly_estimate_summary(conn, &window.start_utc, &window.end_utc)?;

        let completed_returned = completed_this_week.len();
        let stalled_returned = stalled_lists.len();
        let deferred_returned = frequently_deferred.len();
        let someday_returned = someday_items.len();

        Ok(WeeklyReviewBrief {
            window: window.model,
            completed_this_week,
            stalled_lists,
            frequently_deferred,
            overdue_count,
            someday_items,
            created_this_week,
            estimate_summary,
            section_meta: WeeklyReviewBriefSectionMeta {
                completed_this_week: section_entry(
                    limits.completed_this_week,
                    completed_total,
                    completed_returned,
                ),
                stalled_lists: section_entry(limits.stalled_lists, stalled_total, stalled_returned),
                frequently_deferred: section_entry(
                    limits.frequently_deferred,
                    deferred_total,
                    deferred_returned,
                ),
                someday_items: section_entry(limits.someday_items, someday_total, someday_returned),
            },
        })
    })
}
