//! Task-related render helpers, decomposed by surface.
//!
//! Each sibling owns one render concern: list/collection rendering
//! (`lists`), the dependency graph + ASCII tree (`dependency`), the
//! deferred-tasks browse view (`deferred`), the reminder snapshot
//! (`reminders`), the per-task detail card + post-action banner
//! (`detail`), and the `TaskRow → TaskSummary` projection
//! (`summary`) that feeds every JSON path. The empty-list hint
//! strings used across `lists` are colocated in `hints`.
//!
//! Public surface stays at `crate::render::tasks::*` via the re-exports
//! below — callers (and the parent `render::*` re-exports in
//! `render/mod.rs`) are unaffected.

mod deferred;
mod dependency;
mod detail;
mod hints;
mod lists;
mod reminders;
mod summary;

pub(crate) use deferred::render_deferred_tasks_snapshot;
pub(crate) use dependency::render_dependency_graph_snapshot;
pub(crate) use detail::{render_task_action_result, render_task_detail};
pub(crate) use lists::{render_task_collection, render_task_list_snapshot, render_task_section};
pub(crate) use reminders::render_task_reminder_snapshot;
pub(crate) use summary::task_row_to_summary;
