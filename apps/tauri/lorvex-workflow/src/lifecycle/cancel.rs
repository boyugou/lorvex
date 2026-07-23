//! Dedicated cancel surface — converges on the shared recurrence-handling
//! semantics used by the generic `update_task(status='cancelled')` path.
//!
//! Behavior:
//! - `cancel_series = false` (default): Cancel this task. If recurring,
//!   spawn the next occurrence (skip this one, series continues).
//! - `cancel_series = true`: Cancel this task. If recurring, clear all
//!   recurrence fields (`recurrence`, `recurrence_group_id`,
//!   `canonical_occurrence_date`, `recurrence_exceptions`,
//!   `recurrence_instance_key`) and do NOT spawn (stop the entire series).
//! - For non-recurring tasks: `cancel_series` is ignored.
//!
//! Owns: status mutation → cancelled, reminder cancellation, dependency
//! edge removal, recurrence spawn or series stop.
//! Callers handle: audit logging, sync outbox, response formatting.

use lorvex_domain::TaskId;
use rusqlite::{params, Connection};

use lorvex_store::StoreError;

use super::snapshot::{read_active_task_reminder_times, read_task_snapshot};
use super::spawn_successor::spawn_recurrence_successor;
use super::status::cancel_task;
use super::types::{CancelLifecycleTransitionResult, CopiedTagEdge};

pub fn apply_cancel_transition(
    conn: &Connection,
    task_id: &TaskId,
    now: &str,
    reminder_version: &str,
    cancel_series: bool,
    series_clear_version: Option<&str>,
) -> Result<CancelLifecycleTransitionResult, StoreError> {
    // this function performs a multi-step write —
    // (1) `cancel_task` (status + reminders + dep edges),
    // (2) the `cancel_series ? clear-recurrence : spawn_recurrence_successor`
    // branch (insert successor + copy children + rewire focus plan).
    // A panic or partial failure between (1) and (2) leaves
    // divergent state: cancellation visible without the next
    // occurrence spawned, or a successor inserted with no link to
    // the cancelled parent. Callers MUST wrap in
    // `with_immediate_transaction` so the whole transition commits
    // or rolls back atomically.
    debug_assert!(
        !conn.is_autocommit(),
        "apply_cancel_transition must run inside a transaction \
         (cancel_task + recurrence spawn/clear must commit atomically)"
    );

    let snapshot = read_task_snapshot(conn, task_id)?;
    let active_reminder_times = read_active_task_reminder_times(conn, task_id)?;

    // 1. Core cancel mutation (status + reminders + dep edges).
    let cancel = cancel_task(conn, task_id, now, reminder_version)?;

    if !cancel.updated {
        return Ok(CancelLifecycleTransitionResult {
            updated: false,
            cancelled_reminder_ids: vec![],
            affected_dependent_ids: vec![],
            deleted_dependency_edges: vec![],
            spawned_successor_id: None,
            spawned_successor_tag_edges: vec![],
            spawned_successor_checklist_item_ids: vec![],
            spawned_successor_reminder_ids: vec![],
            rewired_focus_schedule_dates: vec![],
            rewired_current_focus_dates: vec![],
        });
    }

    let mut spawned_successor_id = None;
    let mut spawned_tag_edges: Vec<CopiedTagEdge> = Vec::new();
    let mut spawned_checklist_item_ids: Vec<String> = Vec::new();
    let mut spawned_reminder_ids: Vec<String> = Vec::new();
    let mut rewired_focus_schedule_dates: Vec<String> = Vec::new();
    let mut rewired_current_focus_dates: Vec<String> = Vec::new();

    // 2. Recurrence handling — read the snapshot AFTER cancel (fields still present).
    if let Some(ref snap) = snapshot {
        if let Some(ref rule) = snap.recurrence {
            if !rule.is_empty() {
                if cancel_series {
                    // Stop the entire series: clear recurrence fields on the cancelled task.
                    let series_clear_version = series_clear_version.ok_or_else(|| {
                        StoreError::Invariant(
                            "apply_cancel_transition: cancel_series recurrence clear \
                             requires a caller-supplied HLC version"
                                .to_string(),
                        )
                    })?;
                    let rows = conn.execute(
                        "UPDATE tasks SET recurrence = NULL, recurrence_group_id = NULL, \
                         canonical_occurrence_date = NULL, \
                         recurrence_instance_key = NULL, \
                         version = ?3, updated_at = ?2 \
                         WHERE id = ?1 AND ?3 > version",
                        params![task_id, now, series_clear_version],
                    )?;
                    // EXDATE list moved to the
                    // `task_recurrence_exceptions` child table.
                    // Drop every row for this task in the same
                    // transaction so the series-clear is atomic with
                    // the parent-row reset; the cascade only fires on
                    // task deletion, not on this in-place reset.
                    if rows != 0 {
                        lorvex_store::recurrence_exceptions::replace_task_exceptions(
                            conn,
                            task_id.as_str(),
                            &[],
                        )?;
                    }
                    if rows == 0 {
                        // Lost the LWW gate: a peer envelope landed a
                        // strictly-newer version between the
                        // `cancel_task` write and this one. Surface as
                        // StaleVersion so the boundary layer re-stamps
                        // HLC and retries the whole cancel-series
                        // transition.
                        return Err(StoreError::StaleVersion {
                            entity: "task",
                            id: task_id.as_str().to_string(),
                        });
                    }
                } else {
                    // Skip this occurrence: spawn the next one (series continues).
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

    Ok(CancelLifecycleTransitionResult {
        updated: true,
        cancelled_reminder_ids: cancel.cancelled_reminder_ids,
        affected_dependent_ids: cancel.affected_dependent_ids,
        deleted_dependency_edges: cancel.deleted_dependency_edges,
        spawned_successor_id,
        spawned_successor_tag_edges: spawned_tag_edges,
        spawned_successor_checklist_item_ids: spawned_checklist_item_ids,
        spawned_successor_reminder_ids: spawned_reminder_ids,
        rewired_focus_schedule_dates,
        rewired_current_focus_dates,
    })
}
