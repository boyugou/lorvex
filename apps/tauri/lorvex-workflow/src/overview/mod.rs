//! Shared overview read model for app and MCP surfaces.
//!
//! [`load_overview_snapshot`] composes the at-a-glance dashboard:
//! per-list open counts, top-priority open tasks, recently-completed
//! rows, the current_focus summary, habit activity,
//! and the day-buckets that feed Attention / Overdue / Today / Upcoming.
//! [`OverviewLimits`] picks the section caps per surface (full app
//! view, MCP full tool response, or MCP compact tool response).
//!
//! Section seams:
//!
//! - [`types`] — wire structs every entry point returns (snapshot,
//!   stats, list, focus/habit summaries) and the
//!   `OverviewLimits` cap presets.
//! - [`stats`] — [`load_overview_stats_for_bounds`], the SQL that
//!   produces every count the dashboard hero strip shows.
//! - [`sections`] — per-section loaders (lists, current focus,
//!   habits) feeding the snapshot's compact summaries.
//! - [`streak`] — the completion-streak query plus its global cache,
//!   keyed on `(today, timezone, local_change_seq)` so re-renders on
//!   the same day reuse the prior walk through 365 days of completions.

mod sections;
mod snapshot;
mod stats;
mod streak;
pub mod types;

pub use snapshot::load_overview_snapshot;
pub use stats::load_overview_stats_for_bounds;
pub use types::{
    OverviewCurrentFocusSummary, OverviewHabitSummary, OverviewLimits, OverviewList,
    OverviewSnapshot, OverviewStats,
};
