use std::cell::RefCell;

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, OP_UPSERT, STATUS_CANCELLED, STATUS_COMPLETED};
use lorvex_store::StoreError;
use lorvex_workflow::lifecycle::{effects as workflow_effects, CancelLifecycleTransitionResult};
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::Value;

use crate::commands::fetch_task_row_unenriched;
use crate::commands::shared::effects::execute_ipc_mutation_with_finalizer;

use super::super::undo::{build_undo_token, compute_undo_expiry, LifecycleAction};
use super::super::*;
use super::shared::validate_batch_task_ids;

#[derive(Debug, serde::Serialize)]
pub struct BatchCancelResult {
    pub cancelled_count: usize,
    pub cancelled: Vec<Task>,
    /// One undo token per successfully cancelled task. Each token
    /// encapsulates the full cancel-side-effect set — including any
    /// recurrence successor spawned by `cancel_series=false` and all
    /// deleted dependency edges — so the UI can reverse the entire
    /// batch via `undo_task_lifecycle_batch`.
    pub undo_tokens: Vec<String>,
    pub skipped: Vec<String>,
}

#[tauri::command]
pub fn batch_cancel_tasks(
    task_ids: Vec<String>,
    cancel_series: Option<bool>,
) -> Result<BatchCancelResult, String> {
    batch_cancel_tasks_inner(task_ids, cancel_series.unwrap_or(false)).map_err(String::from)
}

fn batch_cancel_tasks_inner(
    task_ids: Vec<String>,
    cancel_series: bool,
) -> Result<BatchCancelResult, AppError> {
    let conn = get_conn()?;
    let result = batch_cancel_tasks_with_conn(&conn, task_ids, cancel_series)?;

    // event_bus emit is handled by the per-row executor.

    // Post-commit: remove cancelled tasks from Spotlight index.
    if !result.cancelled.is_empty() {
        let cancelled_ids: Vec<String> = result.cancelled.iter().map(|t| t.id.clone()).collect();
        crate::platform::spotlight::apply_actions(
            &conn,
            &[crate::platform::spotlight::SpotlightAction::RemoveTaskIds(
                cancelled_ids,
            )],
        );
    }
    Ok(result)
}

/// `Mutation` descriptor for one task's cancel transition inside a
/// `batch_cancel_tasks` loop. Mirrors the single-task
/// `CancelTaskMutation` in `lifecycle/removal/cancel.rs`: `apply`
/// runs `workflow_effects::run_cancel` against the per-mutation
/// `HlcSession` and stashes the transition result so the surface
/// finalizer can build the held `LifecycleSyncPlan` without
/// re-running any SQL.
struct BatchCancelTaskMutation<'a> {
    id: &'a lorvex_domain::TaskId,
    now: &'a str,
    cancel_series: bool,
    result: RefCell<Option<CancelLifecycleTransitionResult>>,
}

impl<'a> Mutation for BatchCancelTaskMutation<'a> {
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
        let summary = format!("Batch-cancelled task '{}'", self.id.as_str());
        let after = serde_json::json!({ "id": self.id.as_str() });
        *self.result.borrow_mut() = Some(outcome);
        Ok(MutationOutput::new(after, summary))
    }
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
/// Transactional body of `batch_cancel_tasks` against a caller-supplied
/// connection, returning the rich `BatchCancelResult`.
pub(crate) fn batch_cancel_tasks_with_conn(
    conn: &rusqlite::Connection,
    task_ids: Vec<String>,
    cancel_series: bool,
) -> Result<BatchCancelResult, AppError> {
    let task_ids = validate_batch_task_ids(&task_ids)?;
    with_immediate_transaction(conn, |conn| {
        let now = sync_timestamp_now();
        // One shared expiry across the batch: every per-task undo token
        // minted below closes at the same instant.
        let expires_at = compute_undo_expiry();

        let mut cancelled_ids: Vec<String> = Vec::new();
        let mut undo_tokens: Vec<String> = Vec::new();
        let mut skipped: Vec<String> = Vec::new();

        // Pre-fetch status + title for all tasks in one pass to avoid
        // per-task fetch_task_by_id (which runs 3 queries each).
        let pre_map = fetch_tasks_by_ids(conn, &task_ids)?;

        for id in &task_ids {
            let Some(task) = pre_map.get(id) else {
                skipped.push(id.clone());
                continue;
            };
            if task.status == STATUS_COMPLETED || task.status == STATUS_CANCELLED {
                skipped.push(id.clone());
                continue;
            }

            // Mirror the single `cancel_task` undo pipeline: each
            // cancelled task gets its own undo token so a row-level
            // undo reverses only that task.
            let pre_task = task.clone();

            let task_id_typed = lorvex_domain::TaskId::from_trusted(id.clone());
            let mutation = BatchCancelTaskMutation {
                id: &task_id_typed,
                now: &now,
                cancel_series,
                result: RefCell::new(None),
            };

            let mut captured: Option<CancelLifecycleTransitionResult> = None;
            execute_ipc_mutation_with_finalizer(conn, &mutation, |conn, _execution| {
                let result =
                    mutation.result.borrow_mut().take().expect(
                        "batch cancel mutation must populate transition result inside apply",
                    );
                enqueue_lifecycle_sync_plan(
                    conn,
                    lorvex_workflow::lifecycle::LifecycleSyncPlan::from_cancel(&result),
                )?;

                // Unenriched read — `enqueue_task_upsert_*` strips
                // derived child fields anyway via
                // `lorvex_sync::task_payload::strip_derived_task_fields`,
                // so per-row enrichment is wasted work inside the
                // batch hot path. The user-visible response
                // re-fetches enriched rows once via
                // `fetch_ordered_tasks_by_ids` after the loop.
                let updated = fetch_task_row_unenriched(conn, id)?;
                enqueue_task_upsert(conn, &updated)?;
                captured = Some(result);
                Ok(())
            })?;

            let result =
                captured.expect("batch cancel finalizer must populate captured transition result");

            let deleted_dep_edges: Vec<(String, String)> = result
                .deleted_dependency_edges
                .iter()
                .map(|edge| (edge.task_id.clone(), edge.depends_on_task_id.clone()))
                .collect();

            let undo_token = build_undo_token(
                &pre_task,
                LifecycleAction::Cancel,
                cancel_series,
                result.spawned_successor_id.clone(),
                result.cancelled_reminder_ids.clone(),
                deleted_dep_edges,
                result.affected_dependent_ids.clone(),
                &expires_at,
            )?;

            // Cache each serialized undo token so the Changelog view
            // can surface per-row Undo affordances for batch-cancelled
            // tasks while the undo window is still open.
            crate::commands::diagnostics::undo_token_cache::register(id, &undo_token, &expires_at);

            undo_tokens.push(undo_token);
            cancelled_ids.push(id.clone());
        }

        // Batch re-fetch after all enqueues to get post-stamp versions.
        let cancelled = fetch_ordered_tasks_by_ids(conn, &cancelled_ids, "batch cancel")?;

        Ok(BatchCancelResult {
            cancelled_count: cancelled.len(),
            cancelled,
            undo_tokens,
            skipped,
        })
    })
}
