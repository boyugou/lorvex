use rusqlite::Connection;

use crate::models::{WeeklyReviewBrief, WeeklyReviewSnapshot};

pub(crate) fn get_weekly_review_snapshot_with_conn(
    conn: &Connection,
    completed_limit: u32,
    stalled_lists_limit: u32,
    deferred_limit: u32,
    someday_limit: u32,
) -> Result<WeeklyReviewSnapshot, crate::error::CliError> {
    Ok(lorvex_workflow::weekly_review::load_weekly_review_snapshot(
        conn,
        lorvex_workflow::weekly_review::WeeklyReviewSnapshotLimits {
            top_completed: completed_limit,
            stalled_lists: stalled_lists_limit,
            frequently_deferred: deferred_limit,
            someday_items: someday_limit,
        },
    )?)
}

/// CLI mirror of MCP `get_weekly_review_brief`.
///
/// The shared workflow read model owns the SQL, limits, counts, and ordering;
/// the CLI layer only supplies user-requested limits and renders the result.
pub(crate) fn get_weekly_review_brief_with_conn(
    conn: &Connection,
    completed_limit: u32,
    stalled_lists_limit: u32,
    deferred_limit: u32,
    someday_limit: u32,
) -> Result<WeeklyReviewBrief, crate::error::CliError> {
    Ok(lorvex_workflow::weekly_review::load_weekly_review_brief(
        conn,
        lorvex_workflow::weekly_review::WeeklyReviewBriefLimits {
            completed_this_week: completed_limit,
            stalled_lists: stalled_lists_limit,
            frequently_deferred: deferred_limit,
            someday_items: someday_limit,
        },
    )?)
}
