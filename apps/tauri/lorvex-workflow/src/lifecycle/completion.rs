//! Dedicated completion surface — converges on the shared recurrence
//! spawn semantics used by the generic `update_task(status='completed')`
//! path.
//!
//! Owns: status mutation → completed, reminder cancellation,
//! recurrence spawn. Does NOT re-run `status_side_effects`
//! (`complete_task` already handles reminders; completion does not
//! remove dependency edges the way cancellation does).

use lorvex_domain::TaskId;
use rusqlite::Connection;

use lorvex_store::StoreError;

use super::snapshot::{read_active_task_reminder_times, read_task_snapshot};
use super::spawn_successor::spawn_recurrence_successor;
use super::status::complete_task;
use super::types::CompletionLifecycleTransitionResult;

pub fn apply_completion_transition(
    conn: &Connection,
    task_id: &TaskId,
    now: &str,
    reminder_version: &str,
) -> Result<CompletionLifecycleTransitionResult, StoreError> {
    // this function performs a multi-step write —
    // (1) `complete_task` (status + reminders),
    // (2) `spawn_recurrence_successor` on a recurring parent
    //     (insert successor + copy children + rewire focus plan).
    // A panic or partial failure between (1) and (2) leaves
    // divergent state: completion visible without the next
    // occurrence spawned. Callers MUST wrap in
    // `with_immediate_transaction` so the whole transition commits
    // or rolls back atomically.
    debug_assert!(
        !conn.is_autocommit(),
        "apply_completion_transition must run inside a transaction \
         (complete_task + recurrence spawn must commit atomically)"
    );

    let snapshot = read_task_snapshot(conn, task_id)?;
    let active_reminder_times = read_active_task_reminder_times(conn, task_id)?;

    // 1. Core completion mutation (status + reminders).
    let completion = complete_task(conn, task_id, now, reminder_version)?;

    // 2. If actually transitioned, spawn recurrence successor.
    let mut spawned_successor_id = None;
    let mut spawned_tag_edges = Vec::new();
    let mut spawned_checklist_item_ids = Vec::new();
    let mut spawned_reminder_ids = Vec::new();
    let mut rewired_focus_schedule_dates = Vec::new();
    let mut rewired_current_focus_dates = Vec::new();

    if completion.updated {
        if let Some(ref snap) = snapshot {
            if let Some(ref rule) = snap.recurrence {
                if !rule.is_empty() {
                    if let Some(spawn) = spawn_recurrence_successor(
                        conn,
                        task_id,
                        snap,
                        &active_reminder_times,
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

    Ok(CompletionLifecycleTransitionResult {
        updated: completion.updated,
        cancelled_reminder_ids: completion.cancelled_reminder_ids,
        spawned_successor_id,
        spawned_successor_tag_edges: spawned_tag_edges,
        spawned_successor_checklist_item_ids: spawned_checklist_item_ids,
        spawned_successor_reminder_ids: spawned_reminder_ids,
        rewired_focus_schedule_dates,
        rewired_current_focus_dates,
    })
}
