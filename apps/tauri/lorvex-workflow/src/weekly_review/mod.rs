//! Weekly-review read models shared by the Tauri app and the MCP server.
//!
//! Three public entry points compose the same underlying signals into
//! different consumer-facing shapes:
//!
//! - [`load_weekly_review`] — the desktop app's full read model. Returns
//!   every cap-limited section the user sees in the Weekly Review view.
//! - [`load_weekly_review_snapshot`] — a compact slice the MCP server
//!   surfaces as a "current weekly snapshot" tool response. Drops the
//!   overdue list and the brief's section totals; everything else stays.
//! - [`load_weekly_review_brief`] — the conversational "what changed
//!   this week?" briefing. Carries per-section `total_matching` so the
//!   AI assistant can phrase coverage ("12 completed, 5 shown").
//!
//! The three entry points share the same window math, count queries,
//! and row mappers; only the section composition differs. Each lives
//! in its own sibling module here.
//!
//! Section seams:
//!
//! - [`types`] — read-model structs (the wire types every entry point
//!   returns) plus the shared cap constant.
//! - [`window`] — trailing-day window math + the private
//!   `WeeklyReviewQueryWindow` carrier.
//! - [`sections`] — SQL constants and the shared row-loading helpers
//!   (counts, task items, stalled lists, estimate summary).
//! - [`validation`] — per-limit validators that all three entry points
//!   call before touching SQL.
//! - [`read_model`] / [`snapshot`] / [`brief`] — one module per public
//!   entry point. Each composes the same primitives into its
//!   consumer-shaped output.

mod brief;
mod read_model;
mod sections;
mod snapshot;
pub mod types;
mod validation;
mod window;

pub use brief::load_weekly_review_brief;
pub use read_model::load_weekly_review;
pub use snapshot::load_weekly_review_snapshot;
pub use types::{
    WeeklyReviewBrief, WeeklyReviewBriefLimits, WeeklyReviewBriefSectionEntry,
    WeeklyReviewBriefSectionMeta, WeeklyReviewCounts, WeeklyReviewEstimateSummary,
    WeeklyReviewLimits, WeeklyReviewReadModel, WeeklyReviewSnapshot, WeeklyReviewSnapshotLimits,
    WeeklyReviewStalledList, WeeklyReviewTaskItem, WeeklyReviewWindow, WEEKLY_REVIEW_DAYS,
    WEEKLY_REVIEW_LIMIT_CAP,
};

#[cfg(test)]
mod tests;
