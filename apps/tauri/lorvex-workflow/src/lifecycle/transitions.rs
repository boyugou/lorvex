//! Generic `update_task(status=...)` lifecycle orchestrator.
//!
//! Owns the status row mutation (callers MUST NOT write status via the
//! generic patch) and runs the full side-effect pipeline:
//! 0. Status row + transition metadata columns
//! 1. Data-layer side effects (reminders, deps) via status_side_effects
//! 2. Recurrence spawn on → completed (or → cancelled, skip-cancel)
//! 3. Successor cancel on → open (from completed, recurring)
//!
//! Callers handle: non-status field patches (before calling this),
//! audit logging, sync outbox enqueue for the task itself and for
//! spawned/cancelled successors, and response formatting.

use lorvex_domain::{naming::TaskStatus, TaskId};
use rusqlite::Connection;

use lorvex_store::StoreError;

use super::side_effects::{apply_lifecycle_side_effects, LifecycleSideEffectsInput};
use super::snapshot::{read_active_task_reminder_times, read_task_snapshot};
use super::status::reject_terminal_to_terminal;
use super::types::LifecycleTransitionResult;
use super::write_status::write_status_and_metadata;

pub fn apply_lifecycle_transition(
    conn: &Connection,
    task_id: &TaskId,
    old_status: TaskStatus,
    new_status: TaskStatus,
    now: &str,
    reminder_version: &str,
) -> Result<LifecycleTransitionResult, StoreError> {
    // this function performs a multi-step write —
    // (0) `write_status_and_metadata`, (1) cancel-active-reminders,
    // (2) `spawn_recurrence_successor` (insert successor + copy
    // children), (3) cancel-spawned-successors. A panic or partial
    // failure between step 0 and step 3 leaves divergent state:
    // the task row's status flipped but its children not cascaded,
    // or a successor inserted with no link to the parent. Callers
    // must wrap in `with_immediate_transaction` so the whole
    // transition commits or rolls back atomically. The
    // debug_assert catches misuse in tests and dev builds; in
    // production the writer mutex serializes calls but a non-txn
    // call would still bypass the rollback discipline.
    debug_assert!(
        !conn.is_autocommit(),
        "apply_lifecycle_transition must run inside a transaction \
         (write_status + cascade side-effects + recurrence spawn must \
         commit atomically)"
    );

    reject_terminal_to_terminal(task_id, old_status, new_status)?;

    let snapshot = read_task_snapshot(conn, task_id)?;
    let active_reminder_times = if (new_status == TaskStatus::Completed
        && old_status != TaskStatus::Completed)
        || (new_status == TaskStatus::Cancelled && old_status != TaskStatus::Cancelled)
    {
        read_active_task_reminder_times(conn, task_id)?
    } else {
        Vec::new()
    };

    // 0. Write the status column + transition metadata.
    let rows =
        write_status_and_metadata(conn, task_id, old_status, new_status, now, reminder_version)?;
    if rows == 0 {
        // The status writer is LWW-gated. A zero-row
        // result here means the caller's version stamp is not
        // strictly newer than the row's current version — surface as
        // StaleVersion so the boundary layer (Tauri / MCP / CLI) can
        // re-stamp HLC and retry instead of running side-effects
        // (reminder cancellation, recurrence spawn) against a row
        // whose status never actually flipped.
        return Err(StoreError::StaleVersion {
            entity: "task",
            id: task_id.as_str().to_string(),
        });
    }

    // 1–3. Side effects, recurrence spawn, successor cancel.
    apply_lifecycle_side_effects(
        conn,
        LifecycleSideEffectsInput {
            task_id,
            old_status,
            new_status,
            now,
            reminder_version,
            snapshot,
            pre_transition_active_reminder_times: &active_reminder_times,
        },
    )
}
