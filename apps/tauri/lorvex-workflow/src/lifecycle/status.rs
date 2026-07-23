//! Low-level status state-machine primitives.
//!
//! These talk directly to the `tasks` table to flip a single row's
//! `status` column (plus the metadata columns the
//! [`status_transition_columns`] rules dictate) and run the bounded
//! per-row side effects:
//! - [`complete_task`]: cancel active reminders.
//! - [`cancel_task`]: cancel active reminders + remove dependency edges.
//! - [`reopen_task`]: restore reminders that were cancelled by the prior
//!   `complete_task` / `cancel_task` side effect.
//!
//! For the higher-level orchestrators that ALSO spawn recurrence
//! successors, cancel sibling successors, and emit changelog rows, see
//! [`super::transitions`] (generic) and the dedicated [`super::cancel`],
//! [`super::completion`], [`super::reopen`] surfaces.
//!
//! [`status_transition_columns`]: lorvex_domain::status_transition::status_transition_columns

use lorvex_domain::{naming::TaskStatus, TaskId};
use rusqlite::{params, Connection, OptionalExtension};

use lorvex_store::StoreError;

use super::dependencies::remove_task_dependency_edges;
use super::reminders::{cancel_active_reminders, uncancel_task_reminders};
use super::types::{CancelTaskResult, CompleteTaskResult, ReopenTaskResult};
use super::write_status::write_status_and_metadata;

pub(super) fn reject_terminal_to_terminal(
    task_id: &TaskId,
    old_status: TaskStatus,
    new_status: TaskStatus,
) -> Result<(), StoreError> {
    if old_status != new_status && old_status.is_terminal() && new_status.is_terminal() {
        return Err(StoreError::Validation(format!(
            "Cannot transition task {task_id} from {old_status} to {new_status}; reopen it first"
        )));
    }
    Ok(())
}

fn invalid_persisted_task_status(task_id: &TaskId, raw: &str) -> StoreError {
    StoreError::Invariant(format!(
        "task {task_id} has invalid persisted status {raw:?}; expected one of: open, completed, cancelled, someday"
    ))
}

pub(super) fn parse_persisted_task_status(
    task_id: &TaskId,
    raw: &str,
) -> Result<TaskStatus, StoreError> {
    TaskStatus::parse(raw).ok_or_else(|| invalid_persisted_task_status(task_id, raw))
}

/// Read the current status of a task. Returns `None` when the task row
/// is missing — callers treat that as "nothing to update."
fn read_task_status(conn: &Connection, task_id: &TaskId) -> Result<Option<TaskStatus>, StoreError> {
    conn.query_row(
        "SELECT status FROM tasks WHERE id = ?1",
        params![task_id],
        |row| row.get::<_, String>(0),
    )
    .optional()?
    .map(|raw| parse_persisted_task_status(task_id, &raw))
    .transpose()
}

/// Complete a task: set status to completed, apply transition metadata
/// columns from `lorvex_domain::status_transition_columns`, and cancel
/// active reminders.
///
/// Routes through the same `write_status_and_metadata` helper that
/// `apply_lifecycle_transition` uses, so any future change to the
/// status-transition column rules (e.g. clearing more deferral state on
/// completion) flows through every status-mutation entry point at once
/// without drifting between paths.
///
/// `reminder_version` is stamped on the task row AND on cancelled
/// reminder rows; the outbox stamper will overwrite the task's version
/// on the subsequent enqueue, so the value here is a placeholder for
/// the period between the UPDATE and the enqueue.
///
/// Callers are responsible for: outbox enqueue, audit logging.
pub fn complete_task(
    conn: &Connection,
    task_id: &TaskId,
    now: &str,
    reminder_version: &str,
) -> Result<CompleteTaskResult, StoreError> {
    let Some(old_status) = read_task_status(conn, task_id)? else {
        return Ok(CompleteTaskResult {
            updated: false,
            cancelled_reminder_ids: vec![],
        });
    };
    reject_terminal_to_terminal(task_id, old_status, TaskStatus::Completed)?;
    if old_status == TaskStatus::Completed {
        return Ok(CompleteTaskResult {
            updated: false,
            cancelled_reminder_ids: vec![],
        });
    }

    let rows = write_status_and_metadata(
        conn,
        task_id,
        old_status,
        TaskStatus::Completed,
        now,
        reminder_version,
    )?;
    if rows == 0 {
        // The status writer is LWW-gated: zero rows here
        // means the row exists (we already read its old_status above)
        // but the caller's `reminder_version` lost the comparison
        // against `tasks.version`. Surface as `StaleVersion` so the
        // boundary layer can re-stamp HLC and retry instead of
        // treating the silent no-op as success.
        return Err(StoreError::StaleVersion {
            entity: "task",
            id: task_id.as_str().to_string(),
        });
    }

    let cancelled_reminder_ids = cancel_active_reminders(conn, task_id, now, reminder_version)?;

    Ok(CompleteTaskResult {
        updated: true,
        cancelled_reminder_ids,
    })
}

/// Cancel a task: set status to cancelled, apply transition metadata
/// columns from `status_transition_columns`, cancel active reminders,
/// remove from dependency graphs. See `complete_task` for the rationale
/// behind routing through `write_status_and_metadata`.
pub fn cancel_task(
    conn: &Connection,
    task_id: &TaskId,
    now: &str,
    reminder_version: &str,
) -> Result<CancelTaskResult, StoreError> {
    let Some(old_status) = read_task_status(conn, task_id)? else {
        return Ok(CancelTaskResult {
            updated: false,
            affected_dependent_ids: vec![],
            cancelled_reminder_ids: vec![],
            deleted_dependency_edges: vec![],
        });
    };
    reject_terminal_to_terminal(task_id, old_status, TaskStatus::Cancelled)?;
    if old_status == TaskStatus::Cancelled {
        return Ok(CancelTaskResult {
            updated: false,
            affected_dependent_ids: vec![],
            cancelled_reminder_ids: vec![],
            deleted_dependency_edges: vec![],
        });
    }

    let rows = write_status_and_metadata(
        conn,
        task_id,
        old_status,
        TaskStatus::Cancelled,
        now,
        reminder_version,
    )?;
    if rows == 0 {
        // The LWW-gate rejected the cancel — the caller's
        // version stamp is not strictly newer than the row's current
        // version. Treat as a stale-version error so the caller
        // re-stamps HLC and retries.
        return Err(StoreError::StaleVersion {
            entity: "task",
            id: task_id.as_str().to_string(),
        });
    }

    // Cancel active reminders.
    let cancelled_reminder_ids = cancel_active_reminders(conn, task_id, now, reminder_version)?;

    // Remove this task from other tasks' dependency sets.
    let (affected_ids, deleted_edges) = remove_task_dependency_edges(conn, task_id)?;

    Ok(CancelTaskResult {
        updated: true,
        affected_dependent_ids: affected_ids,
        cancelled_reminder_ids,
        deleted_dependency_edges: deleted_edges,
    })
}

/// Reopen a completed/cancelled/deferred task: set status to open, clear
/// completion and deferral metadata, and un-cancel any reminders that
/// the prior complete/cancel side effect had cancelled.
///
/// Reminders that were cancelled as part of the original completion/cancellation
/// are restored (`cancelled_at = NULL`, new `version`), and their
/// `task_reminder_delivery_state` rows are cleared so they can re-fire.
///
/// Callers are responsible for: recurring-successor cancellation, dependency
/// graph restoration, HLC version stamping, outbox enqueue, audit logging.
/// Callers must also enqueue sync upserts for each ID in
/// `reopened_reminder_ids` so the un-cancel propagates cross-device.
pub fn reopen_task(
    conn: &Connection,
    task_id: &TaskId,
    now: &str,
    reminder_version: &str,
) -> Result<ReopenTaskResult, StoreError> {
    let Some(old_status) = read_task_status(conn, task_id)? else {
        return Ok(ReopenTaskResult {
            updated: false,
            reopened_reminder_ids: vec![],
        });
    };
    if old_status == TaskStatus::Open {
        return Ok(ReopenTaskResult {
            updated: false,
            reopened_reminder_ids: vec![],
        });
    }

    let rows = write_status_and_metadata(
        conn,
        task_id,
        old_status,
        TaskStatus::Open,
        now,
        reminder_version,
    )?;
    if rows == 0 {
        // Stale version lost the LWW gate. Bubble up
        // typed so the boundary can re-stamp HLC and retry.
        return Err(StoreError::StaleVersion {
            entity: "task",
            id: task_id.as_str().to_string(),
        });
    }

    let reopened_reminder_ids = uncancel_task_reminders(conn, task_id, reminder_version)?;

    Ok(ReopenTaskResult {
        updated: true,
        reopened_reminder_ids,
    })
}
