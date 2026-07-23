//! Status transition metadata rules for tasks.
//!
//! When a task's status changes, certain metadata columns must be cleared
//! or set. This module defines those rules as a pure function so both
//! MCP and Tauri use the same transition logic.
//!
//! The rule body switches on the typed [`TaskStatus`] enum rather
//! than `&str` so an unknown wire-format status surfaces at the parse
//! boundary instead of silently falling through every guard.

use crate::naming::TaskStatus;

/// A column assignment to apply during a status transition.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ColumnAction {
    /// Set column to the given string value.
    SetText(&'static str, String),
    /// Set column to NULL.
    SetNull(&'static str),
    /// Set column to an integer value.
    SetInt(&'static str, i64),
}

/// Compute the column assignments needed for a task status transition.
///
/// Returns the metadata columns that must be changed when transitioning
/// from `old_status` to `new_status`. The `now` timestamp is used for
/// `completed_at` when transitioning to completed.
///
/// Callers fold these into their UPDATE statement (MCP adds to SET clauses;
/// Tauri can run a follow-up UPDATE).
///
/// The status pair is typed by the caller before entering this
/// function. That keeps invalid persisted/input statuses out of the
/// transition rule engine entirely.
pub fn status_transition_columns(
    old_status: TaskStatus,
    new_status: TaskStatus,
    now: &str,
) -> Vec<ColumnAction> {
    let mut actions = Vec::new();

    if new_status == TaskStatus::Completed && old_status != TaskStatus::Completed {
        actions.push(ColumnAction::SetText("completed_at", now.to_string()));
        actions.push(ColumnAction::SetNull("last_deferred_at"));
        actions.push(ColumnAction::SetNull("last_defer_reason"));
    }
    if new_status != TaskStatus::Completed && old_status == TaskStatus::Completed {
        actions.push(ColumnAction::SetNull("completed_at"));
    }
    if new_status == TaskStatus::Cancelled && old_status != TaskStatus::Cancelled {
        actions.push(ColumnAction::SetNull("completed_at"));
        actions.push(ColumnAction::SetNull("last_deferred_at"));
        actions.push(ColumnAction::SetNull("last_defer_reason"));
    }
    if new_status == TaskStatus::Open && old_status != TaskStatus::Open {
        actions.push(ColumnAction::SetNull("completed_at"));
        actions.push(ColumnAction::SetNull("planned_date"));
        actions.push(ColumnAction::SetNull("last_deferred_at"));
        actions.push(ColumnAction::SetNull("last_defer_reason"));
        actions.push(ColumnAction::SetInt("defer_count", 0));
    }

    actions
}

#[cfg(test)]
mod tests;
