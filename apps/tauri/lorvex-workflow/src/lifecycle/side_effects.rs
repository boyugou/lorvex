//! Lifecycle side-effect orchestration: data-layer changes
//! (reminders / deps), recurrence spawn on completion or cancellation,
//! and successor cancellation on reopen-from-completed.
//!
//! Internal workhorse shared by `apply_lifecycle_transition` (which
//! writes the status column first) and the dedicated transition
//! wrappers (`apply_reopen_transition`, etc.) that own their own
//! status mutations.

use lorvex_domain::{naming::TaskStatus, TaskId};
use rusqlite::Connection;

use crate::status_side_effects::{apply_status_transition_side_effects, StatusSideEffectResult};
use lorvex_store::StoreError;

use super::cancel_successors::cancel_recurring_successors;
use super::snapshot::TaskSnapshot;
use super::spawn_successor::spawn_recurrence_successor;
use super::types::{CopiedTagEdge, LifecycleTransitionResult, SuccessorCancelSideEffects};

pub(super) struct LifecycleSideEffectsInput<'a> {
    pub(super) task_id: &'a TaskId,
    pub(super) old_status: TaskStatus,
    pub(super) new_status: TaskStatus,
    pub(super) now: &'a str,
    pub(super) reminder_version: &'a str,
    pub(super) snapshot: Option<TaskSnapshot>,
    pub(super) pre_transition_active_reminder_times: &'a [String],
}

/// Apply lifecycle side effects WITHOUT writing the status column.
pub(super) fn apply_lifecycle_side_effects(
    conn: &Connection,
    input: LifecycleSideEffectsInput<'_>,
) -> Result<LifecycleTransitionResult, StoreError> {
    let LifecycleSideEffectsInput {
        task_id,
        old_status,
        new_status,
        now,
        reminder_version,
        snapshot,
        pre_transition_active_reminder_times,
    } = input;

    // 1. Data-layer side effects.
    let side_effects = apply_status_transition_side_effects(
        conn,
        task_id,
        old_status,
        new_status,
        now,
        reminder_version,
    )?;

    let mut spawned_successor_id = None;
    let mut spawned_tag_edges: Vec<CopiedTagEdge> = Vec::new();
    let mut spawned_checklist_item_ids: Vec<String> = Vec::new();
    let mut spawned_reminder_ids: Vec<String> = Vec::new();
    let mut rewired_focus_schedule_dates: Vec<String> = Vec::new();
    let mut rewired_current_focus_dates: Vec<String> = Vec::new();
    let mut cancelled_successor_ids = Vec::new();
    let mut successor_cancel_side_effects = SuccessorCancelSideEffects {
        cancelled_reminder_ids: Vec::new(),
        deleted_dependency_edges: Vec::new(),
        affected_dependent_ids: Vec::new(),
    };

    // 2. Recurrence spawn on completion or cancellation (skip-cancel).
    // When a recurring task transitions to completed or cancelled, spawn the
    // next occurrence so the series continues (default skip behavior).
    if (new_status == TaskStatus::Completed && old_status != TaskStatus::Completed)
        || (new_status == TaskStatus::Cancelled && old_status != TaskStatus::Cancelled)
    {
        if let Some(ref snap) = snapshot {
            if let Some(ref rule) = snap.recurrence {
                if !rule.is_empty() {
                    if let Some(spawn) = spawn_recurrence_successor(
                        conn,
                        task_id,
                        snap,
                        pre_transition_active_reminder_times,
                        now,
                        reminder_version,
                    )? {
                        spawned_successor_id = Some(spawn.successor_id);
                        spawned_tag_edges = spawn.copied_tag_edges;
                        spawned_checklist_item_ids = spawn.copied_checklist_item_ids;
                        spawned_reminder_ids = spawn.copied_reminder_ids;
                        rewired_focus_schedule_dates = spawn.rewired_focus_schedule_dates;
                        rewired_current_focus_dates = spawn.rewired_current_focus_dates;
                    }
                }
            }
        }
    }

    // 3. Successor cancel on reopen from completed.
    if new_status == TaskStatus::Open && old_status == TaskStatus::Completed {
        if let Some(ref snap) = snapshot {
            if snap.recurrence.is_some() {
                let result =
                    cancel_recurring_successors(conn, task_id, snap, now, reminder_version)?;
                cancelled_successor_ids = result.ids;
                successor_cancel_side_effects = result.side_effects;
            }
        }
    }

    Ok(LifecycleTransitionResult {
        side_effects,
        spawned_successor_id,
        spawned_successor_tag_edges: spawned_tag_edges,
        spawned_successor_checklist_item_ids: spawned_checklist_item_ids,
        spawned_successor_reminder_ids: spawned_reminder_ids,
        cancelled_successor_ids,
        successor_cancel_side_effects,
        rewired_focus_schedule_dates,
        rewired_current_focus_dates,
    })
}

pub(super) const fn empty_lifecycle_result() -> LifecycleTransitionResult {
    LifecycleTransitionResult {
        side_effects: StatusSideEffectResult {
            cancelled_reminder_ids: Vec::new(),
            affected_dependent_ids: Vec::new(),
            deleted_dependency_edges: Vec::new(),
        },
        spawned_successor_id: None,
        spawned_successor_tag_edges: Vec::new(),
        spawned_successor_checklist_item_ids: Vec::new(),
        spawned_successor_reminder_ids: Vec::new(),
        cancelled_successor_ids: Vec::new(),
        successor_cancel_side_effects: SuccessorCancelSideEffects {
            cancelled_reminder_ids: Vec::new(),
            deleted_dependency_edges: Vec::new(),
            affected_dependent_ids: Vec::new(),
        },
        rewired_focus_schedule_dates: Vec::new(),
        rewired_current_focus_dates: Vec::new(),
    }
}
