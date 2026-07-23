//! Shared lifecycle subsystem for task status mutations.
//!
//! Two layers live here:
//!
//! 1. **Primitives** — the low-level mutators that touch a single
//!    aggregate ([`complete_task`], [`cancel_task`], [`reopen_task`] in
//!    [`status`]; [`append_to_task_body`] in [`body`];
//!    [`cancel_active_reminders`] / [`uncancel_task_reminders`] in
//!    [`reminders`]; [`detach_task_dependency_edges`]). These talk
//!    straight to SQL with caller-provided HLC version strings.
//!
//! 2. **Transition orchestrators** ([`apply_lifecycle_transition`],
//!    [`apply_completion_transition`], [`apply_cancel_transition`],
//!    [`apply_reopen_transition`]) — the higher-level surfaces that
//!    wrap a primitive mutator with recurrence spawn, successor
//!    cancel, dependency unlock, and changelog snapshotting. Both
//!    MCP and Tauri call these; they own the cross-cutting
//!    semantics that every status change must respect.
//!
//! Both layers live under a single import path
//! (`lorvex_workflow::lifecycle::*`), so the file structure
//! mirrors the conceptual layering and the "which one do I call?"
//! question is answered by the rustdoc index at the top of this
//! module.

mod body;
mod cancel;
mod cancel_successors;
mod completion;
mod dependencies;
pub mod effects;
mod reminders;
mod reopen;
mod side_effects;
mod snapshot;
mod spawn_successor;
mod status;
mod sync_plan;
mod transitions;
mod types;
mod write_status;

#[cfg(test)]
mod tests;

pub use body::append_to_task_body;
pub use cancel::apply_cancel_transition;
pub use completion::apply_completion_transition;
pub use reminders::{cancel_active_reminders, uncancel_task_reminders};
pub use reopen::apply_reopen_transition;
pub use status::{cancel_task, complete_task, reopen_task};
pub use sync_plan::{LifecycleSyncPlan, StatusSideEffectSyncPlan};
pub use transitions::apply_lifecycle_transition;
pub use types::{
    CancelLifecycleTransitionResult, CancelTaskResult, CompleteTaskResult,
    CompletionLifecycleTransitionResult, CopiedTagEdge, DeletedDependencyEdge,
    LifecycleTransitionResult, ReopenLifecycleTransitionResult, ReopenTaskResult,
    SuccessorCancelSideEffects,
};

/// Remove every dependency edge touching `task_id`, returning the task ids
/// unblocked by incoming-edge deletion plus full edge snapshots for sync
/// tombstones.
pub fn detach_task_dependency_edges(
    conn: &rusqlite::Connection,
    task_id: &lorvex_domain::TaskId,
) -> Result<(Vec<String>, Vec<DeletedDependencyEdge>), lorvex_store::StoreError> {
    dependencies::remove_task_dependency_edges(conn, task_id)
}
