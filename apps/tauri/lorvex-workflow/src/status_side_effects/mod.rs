//! Shared status transition side effects.
//!
//! When a task's status changes via `update_task`, the same side effects
//! that dedicated lifecycle ops (complete_task, cancel_task, reopen_task)
//! perform must also fire. This module provides a single entry point that
//! both MCP and Tauri call after their dynamic UPDATE.
//!
//! The caller handles: the dynamic SQL UPDATE (which may change multiple
//! fields including status), metadata column clearing (via
//! `status_transition_columns`), and adapter-specific concerns (audit,
//! sync enqueue, recurrence spawn, successor cancel).
//!
//! This module handles: reminder cancellation and dependency cleanup —
//! the two side effects that are purely data-layer concerns with no
//! adapter-specific behavior.

use lorvex_domain::{naming::TaskStatus, TaskId};
use rusqlite::Connection;

use lorvex_store::StoreError;

use super::lifecycle::{
    cancel_active_reminders, detach_task_dependency_edges, DeletedDependencyEdge,
};

/// Result of applying status transition side effects.
#[derive(Debug)]
pub struct StatusSideEffectResult {
    /// IDs of reminders that were cancelled (callers must sync these).
    pub cancelled_reminder_ids: Vec<String>,
    /// IDs of tasks whose dependency sets changed (callers must sync these).
    pub affected_dependent_ids: Vec<String>,
    /// Deleted dependency edges (callers must enqueue edge delete syncs).
    pub deleted_dependency_edges: Vec<DeletedDependencyEdge>,
}

/// Apply the data-layer side effects of a status transition.
///
/// Call this after the main UPDATE has already set the status column.
/// Returns IDs that the caller must enqueue for sync propagation.
///
/// - **→ completed**: cancel active reminders
/// - **→ cancelled**: cancel active reminders + remove from dependency graph
/// - **→ open**: no data-layer side effects (recurrence/successor handling
///   is adapter-specific due to different task type systems)
/// - **same status**: no-op
pub fn apply_status_transition_side_effects(
    conn: &Connection,
    task_id: &TaskId,
    old_status: TaskStatus,
    new_status: TaskStatus,
    now: &str,
    reminder_version: &str,
) -> Result<StatusSideEffectResult, StoreError> {
    let mut cancelled_reminder_ids = Vec::new();
    let mut affected_dependent_ids = Vec::new();
    let mut deleted_dependency_edges = Vec::new();

    let became_completed =
        new_status == TaskStatus::Completed && old_status != TaskStatus::Completed;
    let became_cancelled =
        new_status == TaskStatus::Cancelled && old_status != TaskStatus::Cancelled;

    // Cancel active reminders on completion or cancellation.
    if became_completed || became_cancelled {
        cancelled_reminder_ids = cancel_active_reminders(conn, task_id, now, reminder_version)?;
    }

    // Remove from dependency graph on cancellation.
    if became_cancelled {
        let (affected, deleted) = detach_task_dependency_edges(conn, task_id)?;
        affected_dependent_ids = affected;
        deleted_dependency_edges = deleted;
    }

    Ok(StatusSideEffectResult {
        cancelled_reminder_ids,
        affected_dependent_ids,
        deleted_dependency_edges,
    })
}

#[cfg(test)]
mod tests;
