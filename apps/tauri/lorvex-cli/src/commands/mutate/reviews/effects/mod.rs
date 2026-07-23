//! Daily and weekly review surfaces.
//!
//! Daily reviews are the user's structured journal of what they
//! finished, what blocked them, and the lessons. Each one lives at
//! `daily_reviews(date)` plus task/list link tables, with a sync
//! payload that bundles the linked ids so peers see one coherent
//! row. Weekly reviews are a derived snapshot — no row is written;
//! `get_weekly_review_snapshot_with_conn` aggregates the trailing
//! 7-day window directly from `tasks`, `lists`, and the estimate
//! summary.
//!
//! Validation here is the strictest in the CLI surface: scales
//! constrained to 1..=5, free-text capped at 50 KiB, link sets capped
//! at 500 ids, dates anchored to the user's timezone via
//! `today_ymd_for_conn`. Future-dated reviews are tolerated only one
//! day ahead so a user reviewing late at night doesn't get rejected
//! when they cross midnight in their tz.
//!
//! This module is split per concern:
//!   * `validation`        — scale / text / link-id validators
//!   * `links_validation`  — task/list link FK checks + child readers
//!   * `daily_view`        — daily review read paths (single + history)
//!   * `sync_outbox`       — outbox payload enqueue helper
//!   * `daily`             — `add_daily_review` / `amend_daily_review` entry points
//!   * `weekly`            — derived weekly snapshot + brief

mod daily;
mod daily_view;
mod links_validation;
mod sync_outbox;
mod validation;
mod weekly;

pub(crate) use daily::{
    add_daily_review_with_conn, amend_daily_review_with_conn, DailyReviewAddFields,
    DailyReviewAmendFields,
};
pub(crate) use daily_view::{get_daily_review_history_with_conn, get_daily_review_with_conn};
pub(crate) use weekly::{get_weekly_review_brief_with_conn, get_weekly_review_snapshot_with_conn};

#[cfg(test)]
mod tests;
