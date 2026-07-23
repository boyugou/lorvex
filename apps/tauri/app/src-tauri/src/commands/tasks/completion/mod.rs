use std::cell::RefCell;

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, OP_UPSERT};
use lorvex_store::StoreError;
use lorvex_workflow::lifecycle::{
    effects as workflow_effects, CompletionLifecycleTransitionResult,
};
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::Value;

use super::undo::{build_undo_token, compute_undo_expiry, LifecycleAction, TaskWithUndo};
use super::{
    enqueue_lifecycle_sync_plan, enqueue_task_upsert, fetch_task_by_id, get_conn,
    with_immediate_transaction, AppError,
};
use crate::commands::shared::effects::execute_ipc_mutation_with_finalizer;

/// Result of the internal completion helper.
///
/// Contains task IDs that need Spotlight reindexing after the transaction
/// commits.
pub(crate) struct CompleteTaskResult {
    pub spotlight_reindex_ids: Vec<String>,
}

/// `Mutation` descriptor for the task-completion transition.
///
/// `apply` runs the workflow's `run_completion` against the borrowed
/// [`HlcSession`] (so the recurrence-spawn reminder/successor stamps
/// share the surrounding session) and stashes the resulting
/// [`CompletionLifecycleTransitionResult`] in `result` so the surface
/// finalizer can build the `LifecycleSyncPlan` without re-running any
/// SQL. The descriptor borrows the typed id and the `now` timestamp so
/// the surface owns their lifetime.
struct CompleteTaskMutation<'a> {
    id: &'a lorvex_domain::TaskId,
    now: &'a str,
    /// Captured inside `apply`; consumed by the surrounding finalizer
    /// closure to drive `enqueue_lifecycle_sync_plan{,_held}`.
    result: RefCell<Option<CompletionLifecycleTransitionResult>>,
}

impl<'a> Mutation for CompleteTaskMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }
    fn operation(&self) -> &'static str {
        OP_UPSERT
    }
    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        // The Tauri surface has no audit funnel that consumes
        // `before_json`, so skip the read on the hot path.
        Ok(None)
    }
    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let outcome = workflow_effects::run_completion(conn, self.id, self.now, hlc)?;
        let summary = format!("Completed task '{}'", self.id.as_str());
        let after = serde_json::json!({ "id": self.id.as_str() });
        *self.result.borrow_mut() = Some(outcome);
        Ok(MutationOutput::new(after, summary))
    }
}

/// Core completion logic shared between the `#[tauri::command]` wrapper and
/// notification action handler.
///
/// Performs the completion transition, syncs cancelled reminders and spawned
/// recurrence successors, and logs the change.
///
/// Does **not** mint an undo token — callers that need undo support should
/// use the full `complete_task` command instead.
///
/// Must be called inside an IMMEDIATE transaction. Callers emit data-changed
/// events only after the surrounding transaction commits.
pub(crate) fn complete_task_internal(
    conn: &Connection,
    id: &str,
) -> Result<CompleteTaskResult, AppError> {
    let now = super::sync_timestamp_now();

    let before = fetch_task_by_id(conn, id)?;
    if before.status == lorvex_domain::naming::STATUS_COMPLETED {
        return Err(AppError::Validation(format!(
            "Task '{id}' is already completed"
        )));
    }

    let mut spotlight_ids = vec![id.to_string()];

    let task_id_typed = lorvex_domain::TaskId::from_trusted(id.to_string());
    let mutation = CompleteTaskMutation {
        id: &task_id_typed,
        now: &now,
        result: RefCell::new(None),
    };

    execute_ipc_mutation_with_finalizer(conn, &mutation, |conn, _execution| {
        let result = mutation
            .result
            .borrow_mut()
            .take()
            .expect("completion mutation must populate transition result inside apply");
        enqueue_lifecycle_sync_plan(
            conn,
            lorvex_workflow::lifecycle::LifecycleSyncPlan::from_completion(&result),
        )?;
        if let Some(ref successor_id) = result.spawned_successor_id {
            spotlight_ids.push(successor_id.clone());
        }
        let task = fetch_task_by_id(conn, id)?;
        enqueue_task_upsert(conn, &task)?;
        Ok(())
    })?;

    Ok(CompleteTaskResult {
        spotlight_reindex_ids: spotlight_ids,
    })
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn complete_task(id: String) -> Result<TaskWithUndo, String> {
    // task ids are UUIDv7 — shape-check at the IPC
    // boundary so the completion writer (which can spawn a recurrence
    // successor) never sees a malformed id.
    let id = crate::commands::shared::validate_uuid_id(&id, "id")?;
    complete_task_inner(id).map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
pub(super) fn complete_task_inner(id: String) -> Result<TaskWithUndo, AppError> {
    let conn = get_conn()?;
    let (result, spotlight_ids) = complete_task_with_conn_inner(&conn, &id)?;

    // event_bus emit is handled by the executor; no explicit emit needed here.

    // Post-commit Spotlight dispatch.
    crate::platform::spotlight::apply_actions(
        &conn,
        &[crate::platform::spotlight::SpotlightAction::ReindexTaskIds(
            spotlight_ids,
        )],
    );

    Ok(result)
}

/// Transactional body of `complete_task` against a caller-supplied
/// connection. Returns `(TaskWithUndo, spotlight_reindex_ids)` so the
/// outer wrapper can drive the Spotlight removal.
pub(crate) fn complete_task_with_conn_inner(
    conn: &rusqlite::Connection,
    id: &str,
) -> Result<(TaskWithUndo, Vec<String>), AppError> {
    let now = super::sync_timestamp_now();

    with_immediate_transaction(conn, |conn| {
        // Capture pre-mutation state for undo.
        let pre_task = fetch_task_by_id(conn, id)?;
        if pre_task.status == lorvex_domain::naming::STATUS_COMPLETED {
            return Err(AppError::Validation(format!(
                "Task '{id}' is already completed"
            )));
        }
        if pre_task.status == lorvex_domain::naming::STATUS_CANCELLED {
            return Err(AppError::Validation(format!(
                "Cannot transition task '{id}' from cancelled to completed; reopen it first"
            )));
        }

        let expires_at = compute_undo_expiry();

        let task_id_typed = lorvex_domain::TaskId::from_trusted(id.to_string());
        let mutation = CompleteTaskMutation {
            id: &task_id_typed,
            now: &now,
            result: RefCell::new(None),
        };

        let mut spotlight_ids = vec![id.to_string()];
        let mut captured_result: Option<CompletionLifecycleTransitionResult> = None;

        execute_ipc_mutation_with_finalizer(conn, &mutation, |conn, _execution| {
            let result = mutation
                .result
                .borrow_mut()
                .take()
                .expect("completion mutation must populate transition result inside apply");
            enqueue_lifecycle_sync_plan(
                conn,
                lorvex_workflow::lifecycle::LifecycleSyncPlan::from_completion(&result),
            )?;
            let task_for_summary = fetch_task_by_id(conn, id)?;
            enqueue_task_upsert(conn, &task_for_summary)?;
            if let Some(ref sid) = result.spawned_successor_id {
                spotlight_ids.push(sid.clone());
            }
            captured_result = Some(result);
            Ok(())
        })?;

        let result =
            captured_result.expect("completion finalizer must populate captured transition result");

        // Re-fetch AFTER enqueue to get the post-stamp version.
        let task = fetch_task_by_id(conn, id)?;

        // Build undo token. Completion does not delete dep edges.
        let undo_token = build_undo_token(
            &pre_task,
            LifecycleAction::Complete,
            false,
            result.spawned_successor_id,
            result.cancelled_reminder_ids,
            vec![], // no dep edge deletion on completion
            vec![], // no affected dependents on completion
            &expires_at,
        )?;

        // cache the serialized undo token for the undo window so the
        // Changelog view can surface an Undo affordance for this row
        // even after the success toast has timed out.
        crate::commands::diagnostics::undo_token_cache::register(id, &undo_token, &expires_at);

        Ok((TaskWithUndo { task, undo_token }, spotlight_ids))
    })
}

#[cfg(test)]
mod tests;
