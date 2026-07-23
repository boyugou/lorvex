//! Public result types returned by lifecycle primitives and the
//! transition orchestrator.
//!
//! Each type carries the side-effect inventory the caller (MCP, Tauri,
//! or CLI) needs to enqueue sync envelopes / format API responses /
//! drive UI invalidation. Neither the primitives nor the orchestrator
//! enqueue sync events themselves — they return the *what changed*
//! and let each surface translate that into its own outbound contract.

use crate::status_side_effects::StatusSideEffectResult;

// -----------------------------------------------------------------------
// Primitive result types — returned by the low-level mutators in
// `super::status` (complete_task / cancel_task / reopen_task).
// -----------------------------------------------------------------------

/// Result of a task completion operation.
#[derive(Debug)]
pub struct CompleteTaskResult {
    /// Whether the task was actually updated (false if already completed).
    pub updated: bool,
    /// IDs of reminders whose cancelled_at was set. Callers must enqueue
    /// sync upserts for these to propagate cancellation cross-device.
    pub cancelled_reminder_ids: Vec<String>,
}

/// A deleted dependency edge identity for sync.
///
/// carries the row's full pre-delete state
/// (`created_at`, `version`) so the cascade tombstone can ship a
/// payload-bearing `enqueue_payload_delete` instead of an empty `{}`
/// `enqueue_entity_delete`. Peers that missed the upsert envelope can
/// then reconstruct the row from the tombstone for restore-from-trash
/// flows. Same loss class as / /-H1.
#[derive(Debug)]
pub struct DeletedDependencyEdge {
    /// The task that depended on the cancelled task (incoming edge).
    /// Or the cancelled task itself (outgoing edge).
    pub task_id: String,
    /// The task that was depended on.
    pub depends_on_task_id: String,
    /// The edge's `created_at` timestamp (so the cascade tombstone
    /// payload mirrors the pre-delete row shape).
    pub created_at: String,
    /// The edge's HLC version at the moment of deletion (so the
    /// tombstone payload's `version` field matches the row that was
    /// removed).
    pub version: String,
}

/// Result of a task cancellation operation.
#[derive(Debug)]
pub struct CancelTaskResult {
    /// Whether the task was actually updated.
    pub updated: bool,
    /// IDs of tasks whose dependency sets were affected by this cancellation.
    pub affected_dependent_ids: Vec<String>,
    /// IDs of reminders whose cancelled_at was set. Callers must enqueue
    /// sync upserts for these to propagate cancellation cross-device.
    pub cancelled_reminder_ids: Vec<String>,
    /// Deleted dependency edges. Callers must enqueue EDGE_TASK_DEPENDENCY
    /// delete syncs for each to propagate edge removal cross-device.
    pub deleted_dependency_edges: Vec<DeletedDependencyEdge>,
}

/// Result of a task reopen operation.
#[derive(Debug)]
pub struct ReopenTaskResult {
    /// Whether the task was actually updated (false if already open).
    pub updated: bool,
    /// IDs of reminders whose `cancelled_at` was cleared. Callers must enqueue
    /// sync upserts for these to propagate the un-cancellation cross-device.
    pub reopened_reminder_ids: Vec<String>,
}

// -----------------------------------------------------------------------
// Transition result types — returned by the orchestrators in
// `super::transitions`, `super::completion`, `super::cancel`,
// `super::reopen`.
// -----------------------------------------------------------------------

/// Aggregated sync side effects from cancelling one or more successor tasks.
/// Callers must enqueue sync events for all fields.
#[derive(Debug)]
pub struct SuccessorCancelSideEffects {
    /// Reminders cancelled on successor tasks.
    pub cancelled_reminder_ids: Vec<String>,
    /// Dependency edges deleted from successor tasks.
    pub deleted_dependency_edges: Vec<DeletedDependencyEdge>,
    /// Tasks whose dependency sets changed due to successor removal.
    pub affected_dependent_ids: Vec<String>,
}

/// A tag edge copied from parent to spawned successor.
#[derive(Debug)]
pub struct CopiedTagEdge {
    pub task_id: String,
    pub tag_id: String,
    pub version: String,
    pub created_at: String,
}

/// Result of a full lifecycle transition.
#[derive(Debug)]
pub struct LifecycleTransitionResult {
    /// Side effects from status_side_effects (reminders, deps, edges).
    pub side_effects: StatusSideEffectResult,
    /// ID of a spawned recurrence successor (if completion triggered spawn).
    pub spawned_successor_id: Option<String>,
    /// Tag edges copied to the spawned successor. Callers must enqueue
    /// EDGE_TASK_TAG upsert syncs for each to propagate tag inheritance.
    pub spawned_successor_tag_edges: Vec<CopiedTagEdge>,
    /// IDs of checklist items copied to the spawned successor.
    /// Callers must enqueue ENTITY_TASK_CHECKLIST_ITEM upsert syncs for each.
    pub spawned_successor_checklist_item_ids: Vec<String>,
    /// IDs of reminders copied to the spawned successor.
    /// Callers must enqueue ENTITY_TASK_REMINDER upsert syncs for each.
    pub spawned_successor_reminder_ids: Vec<String>,
    /// IDs of cancelled recurring successors (if reopen triggered cancel).
    pub cancelled_successor_ids: Vec<String>,
    /// Aggregated sync side effects from all cancelled successors.
    pub successor_cancel_side_effects: SuccessorCancelSideEffects,
    /// dates whose `focus_schedule_blocks` rows were
    /// rewired from the completed/cancelled parent to the spawned
    /// successor. Callers must enqueue an `ENTITY_FOCUS_SCHEDULE`
    /// upsert envelope per date so peers see the rewire.
    pub rewired_focus_schedule_dates: Vec<String>,
    /// dates whose `current_focus_items` rows were
    /// rewired. Callers must enqueue an `ENTITY_CURRENT_FOCUS` upsert
    /// envelope per date.
    pub rewired_current_focus_dates: Vec<String>,
}

/// Result of the dedicated reopen surface converged through the shared
/// lifecycle transition orchestrator.
#[derive(Debug)]
pub struct ReopenLifecycleTransitionResult {
    /// Whether the task row was actually reopened.
    pub updated: bool,
    /// IDs of reminders whose `cancelled_at` was cleared as part of the
    /// reopen. Callers must enqueue sync upserts for each so the un-cancel
    /// propagates cross-device.
    pub reopened_reminder_ids: Vec<String>,
    /// Shared lifecycle transition output for successor cancellation.
    pub transition: LifecycleTransitionResult,
}

/// Result of the dedicated completion surface converged through the shared
/// lifecycle transition orchestrator.
#[derive(Debug)]
pub struct CompletionLifecycleTransitionResult {
    /// Whether the task row was actually completed.
    pub updated: bool,
    /// Cancelled reminder IDs from the completion itself.
    pub cancelled_reminder_ids: Vec<String>,
    /// ID of a spawned recurrence successor (if completion triggered spawn).
    pub spawned_successor_id: Option<String>,
    /// Tag edges copied to the spawned successor.
    pub spawned_successor_tag_edges: Vec<CopiedTagEdge>,
    /// IDs of checklist items copied to the spawned successor.
    /// Callers must enqueue ENTITY_TASK_CHECKLIST_ITEM upsert syncs for each.
    pub spawned_successor_checklist_item_ids: Vec<String>,
    /// IDs of reminders copied to the spawned successor.
    /// Callers must enqueue ENTITY_TASK_REMINDER upsert syncs for each.
    pub spawned_successor_reminder_ids: Vec<String>,
    /// dates whose `focus_schedule_blocks` rows were
    /// rewired from the completed parent to the spawned successor.
    /// Callers must enqueue an `ENTITY_FOCUS_SCHEDULE` upsert envelope
    /// per date.
    pub rewired_focus_schedule_dates: Vec<String>,
    /// dates whose `current_focus_items` rows were
    /// rewired. Callers must enqueue an `ENTITY_CURRENT_FOCUS` upsert
    /// envelope per date.
    pub rewired_current_focus_dates: Vec<String>,
}

/// Result of the dedicated cancel surface converged through the shared
/// lifecycle transition orchestrator.
#[derive(Debug)]
pub struct CancelLifecycleTransitionResult {
    /// Whether the task row was actually cancelled.
    pub updated: bool,
    /// Cancelled reminder IDs from the cancellation itself.
    pub cancelled_reminder_ids: Vec<String>,
    /// Tasks whose dependency sets were affected by this cancellation.
    pub affected_dependent_ids: Vec<String>,
    /// Deleted dependency edges. Callers must enqueue EDGE_TASK_DEPENDENCY
    /// delete syncs for each to propagate edge removal cross-device.
    pub deleted_dependency_edges: Vec<DeletedDependencyEdge>,
    /// ID of a spawned recurrence successor (if cancel_series=false on a recurring task).
    pub spawned_successor_id: Option<String>,
    /// Tag edges copied to the spawned successor.
    pub spawned_successor_tag_edges: Vec<CopiedTagEdge>,
    /// IDs of checklist items copied to the spawned successor.
    /// Callers must enqueue ENTITY_TASK_CHECKLIST_ITEM upsert syncs for each.
    pub spawned_successor_checklist_item_ids: Vec<String>,
    /// IDs of reminders copied to the spawned successor.
    /// Callers must enqueue ENTITY_TASK_REMINDER upsert syncs for each.
    pub spawned_successor_reminder_ids: Vec<String>,
    /// dates whose `focus_schedule_blocks` rows were
    /// rewired from the cancelled parent to the spawned successor.
    /// Callers must enqueue an `ENTITY_FOCUS_SCHEDULE` upsert envelope
    /// per date.
    pub rewired_focus_schedule_dates: Vec<String>,
    /// dates whose `current_focus_items` rows were
    /// rewired. Callers must enqueue an `ENTITY_CURRENT_FOCUS` upsert
    /// envelope per date.
    pub rewired_current_focus_dates: Vec<String>,
}
