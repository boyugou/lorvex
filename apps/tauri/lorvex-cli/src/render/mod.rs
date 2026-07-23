//! Output formatters for every CLI surface.
//!
//! Each per-domain submodule owns the text + JSON renderers for one
//! concept (tasks, lists, calendar, focus, review, habits, memory,
//! tags, sync). Shared formatting primitives live in
//! `format.rs`. Two test modules — `tests` (unit) and `snapshots`
//! (insta golden snapshots, see issue #2642) — sit alongside.
//!
//! The module path stays `lorvex::render::*` after the split so the
//! existing insta snapshot files in `lorvex-cli/src/snapshots/` continue
//! to match without renames.

mod calendar;
mod focus;
mod format;
mod habits;
mod lists;
mod memory;
mod review;
mod sync;
mod tags;
mod tasks;

#[cfg(test)]
mod snapshots;
#[cfg(test)]
mod tests;

pub(crate) use calendar::{render_calendar_event_detail, render_calendar_timeline};
pub(crate) use focus::{
    render_current_focus, render_focus_cleared, render_focus_schedule,
    render_focus_schedule_proposal,
};
pub(crate) use format::{style_next_action, yes_no};
pub(crate) use habits::{
    render_habit_collection, render_habit_complete_result, render_habit_stats,
};
pub(crate) use lists::{render_list_collection, render_list_detail, render_list_health_snapshot};
pub(crate) use memory::{render_memory_collection, render_memory_detail, render_memory_history};
pub(crate) use review::{
    render_daily_review, render_daily_review_history, render_weekly_review_brief,
    render_weekly_review_snapshot,
};
pub(crate) use sync::{render_ai_changelog, render_pending_outbox_entries, render_sync_status};
pub(crate) use tags::render_tag_collection;
pub(crate) use tasks::{
    render_deferred_tasks_snapshot, render_dependency_graph_snapshot, render_task_action_result,
    render_task_collection, render_task_detail, render_task_list_snapshot,
    render_task_reminder_snapshot, render_task_section, task_row_to_summary,
};
