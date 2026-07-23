//! `cancel_task` IPC command + the testable `_with_conn` shim that
//! drives the actual transactional body. Cancelling a task is the
//! soft-stop transition: it records the cancellation, spawns a
//! recurrence successor when applicable, and routes every cascaded
//! child write through the typed `DeleteEnvelope` / upsert pipeline
//! so peers see consistent state on the other side.

use std::cell::RefCell;

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, OP_UPSERT, STATUS_CANCELLED, STATUS_COMPLETED};
use lorvex_store::StoreError;
use lorvex_workflow::lifecycle::{effects as workflow_effects, CancelLifecycleTransitionResult};
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::Value;

use super::super::super::undo::{
    build_undo_token, compute_undo_expiry, LifecycleAction, TaskWithUndo,
};
use super::super::super::*;
use crate::commands::shared::effects::execute_ipc_mutation_with_finalizer;

/// `Mutation` descriptor for the task-cancellation transition.
///
/// `apply` runs the workflow's `run_cancel` against the borrowed
/// [`HlcSession`] (so reminder/series-clear/recurrence-successor
/// stamps share the surrounding session) and stashes the resulting
/// [`CancelLifecycleTransitionResult`] in `result` so the surface
/// finalizer can build the `LifecycleSyncPlan` without re-running any
/// SQL.
struct CancelTaskMutation<'a> {
    id: &'a lorvex_domain::TaskId,
    now: &'a str,
    cancel_series: bool,
    result: RefCell<Option<CancelLifecycleTransitionResult>>,
}

impl<'a> Mutation for CancelTaskMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }
    fn operation(&self) -> &'static str {
        OP_UPSERT
    }
    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }
    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let outcome =
            workflow_effects::run_cancel(conn, self.id, self.now, self.cancel_series, hlc)?;
        let summary = format!("Cancelled task '{}'", self.id.as_str());
        let after = serde_json::json!({ "id": self.id.as_str() });
        *self.result.borrow_mut() = Some(outcome);
        Ok(MutationOutput::new(after, summary))
    }
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn cancel_task(id: String, cancel_series: Option<bool>) -> Result<TaskWithUndo, String> {
    // task ids are UUIDv7 — shape-check at the IPC
    // boundary so the cancel transition (which can spawn a recurrence
    // successor) never sees a malformed id.
    let id = crate::commands::shared::validate_uuid_id(&id, "id")?;
    cancel_task_inner(id, cancel_series.unwrap_or(false)).map_err(String::from)
}

pub(in crate::commands::tasks) fn cancel_task_inner(
    id: String,
    cancel_series: bool,
) -> Result<TaskWithUndo, AppError> {
    let conn = get_conn()?;
    let result = cancel_task_with_conn(&conn, &id, cancel_series)?;

    // event_bus emit is handled by the executor.

    // Post-commit: remove cancelled task from Spotlight index.
    crate::platform::spotlight::apply_actions(
        &conn,
        &[crate::platform::spotlight::SpotlightAction::RemoveTaskIds(
            vec![id],
        )],
    );
    Ok(result)
}

/// Transactional body of `cancel_task` against a caller-supplied
/// connection, returning the rich `TaskWithUndo`.
pub(crate) fn cancel_task_with_conn(
    conn: &rusqlite::Connection,
    id: &str,
    cancel_series: bool,
) -> Result<TaskWithUndo, AppError> {
    with_immediate_transaction(conn, |conn| {
        // Capture pre-mutation state for undo.
        let pre_task = fetch_task_by_id(conn, id)?;
        if pre_task.status == STATUS_CANCELLED {
            return Err(AppError::Validation(format!(
                "Task '{id}' is already cancelled"
            )));
        }
        if pre_task.status == STATUS_COMPLETED {
            return Err(AppError::Validation(format!(
                "Cannot transition task '{id}' from completed to cancelled; reopen it first"
            )));
        }

        let expires_at = compute_undo_expiry();
        let now = sync_timestamp_now();

        let task_id_typed = lorvex_domain::TaskId::from_trusted(id.to_string());
        let mutation = CancelTaskMutation {
            id: &task_id_typed,
            now: &now,
            cancel_series,
            result: RefCell::new(None),
        };

        let mut captured_result: Option<CancelLifecycleTransitionResult> = None;

        execute_ipc_mutation_with_finalizer(conn, &mutation, |conn, _execution| {
            let result = mutation
                .result
                .borrow_mut()
                .take()
                .expect("cancel mutation must populate transition result inside apply");
            if !result.updated {
                return Err(AppError::Internal(format!(
                    "Task '{id}' could not be cancelled"
                )));
            }
            enqueue_lifecycle_sync_plan(
                conn,
                lorvex_workflow::lifecycle::LifecycleSyncPlan::from_cancel(&result),
            )?;
            let task_for_summary = fetch_task_by_id(conn, id)?;
            enqueue_task_upsert(conn, &task_for_summary)?;
            captured_result = Some(result);
            Ok(())
        })?;

        let result =
            captured_result.expect("cancel finalizer must populate captured transition result");

        let deleted_dep_edges: Vec<(String, String)> = result
            .deleted_dependency_edges
            .iter()
            .map(|edge| (edge.task_id.clone(), edge.depends_on_task_id.clone()))
            .collect();

        // Re-fetch AFTER enqueue to get the post-stamp version.
        let task = fetch_task_by_id(conn, id)?;

        // Build undo token.
        let undo_token = build_undo_token(
            &pre_task,
            LifecycleAction::Cancel,
            cancel_series,
            result.spawned_successor_id.clone(),
            result.cancelled_reminder_ids.clone(),
            deleted_dep_edges,
            result.affected_dependent_ids,
            &expires_at,
        )?;

        // cache the serialized undo token for the undo window so the
        // Changelog view can surface an Undo affordance for this row.
        crate::commands::diagnostics::undo_token_cache::register(id, &undo_token, &expires_at);

        Ok(TaskWithUndo { task, undo_token })
    })
}
