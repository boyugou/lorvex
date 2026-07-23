//! Per-limit validators every entry point runs before touching SQL.
//!
//! Each entry point's `*Limits` struct goes through its matching
//! validator, which checks every field against the
//! `1..=WEEKLY_REVIEW_LIMIT_CAP` window. A failed validation aborts
//! the entry point before any row scan runs.

use lorvex_store::StoreError;

use super::types::{
    WeeklyReviewBriefLimits, WeeklyReviewLimits, WeeklyReviewSnapshotLimits,
    WEEKLY_REVIEW_LIMIT_CAP,
};

fn validate_weekly_review_limit(name: &str, value: u32) -> Result<(), StoreError> {
    if value == 0 || value > WEEKLY_REVIEW_LIMIT_CAP {
        return Err(StoreError::Validation(format!(
            "{name} must be between 1 and {WEEKLY_REVIEW_LIMIT_CAP}"
        )));
    }
    Ok(())
}

pub(super) fn validate_weekly_review_limits(limits: WeeklyReviewLimits) -> Result<(), StoreError> {
    validate_weekly_review_limit("completed_this_week", limits.completed_this_week)?;
    validate_weekly_review_limit("stalled_lists", limits.stalled_lists)?;
    validate_weekly_review_limit("frequently_deferred", limits.frequently_deferred)?;
    validate_weekly_review_limit("overdue_tasks", limits.overdue_tasks)?;
    validate_weekly_review_limit("someday_items", limits.someday_items)?;
    Ok(())
}

pub(super) fn validate_weekly_review_snapshot_limits(
    limits: WeeklyReviewSnapshotLimits,
) -> Result<(), StoreError> {
    validate_weekly_review_limit("top_completed", limits.top_completed)?;
    validate_weekly_review_limit("stalled_lists", limits.stalled_lists)?;
    validate_weekly_review_limit("frequently_deferred", limits.frequently_deferred)?;
    validate_weekly_review_limit("someday_items", limits.someday_items)?;
    Ok(())
}

pub(super) fn validate_weekly_review_brief_limits(
    limits: WeeklyReviewBriefLimits,
) -> Result<(), StoreError> {
    validate_weekly_review_limit("completed_this_week", limits.completed_this_week)?;
    validate_weekly_review_limit("stalled_lists", limits.stalled_lists)?;
    validate_weekly_review_limit("frequently_deferred", limits.frequently_deferred)?;
    validate_weekly_review_limit("someday_items", limits.someday_items)?;
    Ok(())
}
