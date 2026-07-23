//! Dedicated reopen surface — converges on the shared lifecycle
//! orchestrator's successor-cancel semantics.

use lorvex_domain::{naming::TaskStatus, TaskId};
use rusqlite::Connection;

use lorvex_store::StoreError;

use super::side_effects::{
    apply_lifecycle_side_effects, empty_lifecycle_result, LifecycleSideEffectsInput,
};
use super::snapshot::read_task_snapshot;
use super::status::reopen_task;
use super::types::ReopenLifecycleTransitionResult;

pub fn apply_reopen_transition(
    conn: &Connection,
    task_id: &TaskId,
    old_status: TaskStatus,
    now: &str,
    reminder_version: &str,
) -> Result<ReopenLifecycleTransitionResult, StoreError> {
    // this function performs a multi-step write —
    // (1) `reopen_task` (status + reminders), and
    // (2) `apply_lifecycle_side_effects` (cancel previously-spawned
    //     recurrence successors, undo dependency edge changes, etc.).
    // A panic or partial failure between (1) and (2) leaves
    // divergent state — task reopen visible while spawned successors
    // remain orphaned. Callers MUST wrap in
    // `with_immediate_transaction` so the whole transition commits
    // or rolls back atomically.
    debug_assert!(
        !conn.is_autocommit(),
        "apply_reopen_transition must run inside a transaction \
         (reopen_task + successor cancel cascade must commit atomically)"
    );

    let snapshot = read_task_snapshot(conn, task_id)?;
    let reopen = reopen_task(conn, task_id, now, reminder_version)?;
    let transition = if reopen.updated {
        // reopen_task already wrote status; only run side effects.
        apply_lifecycle_side_effects(
            conn,
            LifecycleSideEffectsInput {
                task_id,
                old_status,
                new_status: TaskStatus::Open,
                now,
                reminder_version,
                snapshot,
                pre_transition_active_reminder_times: &[],
            },
        )?
    } else {
        empty_lifecycle_result()
    };

    Ok(ReopenLifecycleTransitionResult {
        updated: reopen.updated,
        reopened_reminder_ids: reopen.reopened_reminder_ids,
        transition,
    })
}
