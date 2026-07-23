use std::cell::RefCell;

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, OP_UPSERT, STATUS_CANCELLED, STATUS_COMPLETED};
use lorvex_store::StoreError;
use lorvex_workflow::lifecycle::{
    effects as workflow_effects, CompletionLifecycleTransitionResult,
};
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::Value;

use crate::commands::fetch_task_row_unenriched;
use crate::commands::shared::effects::execute_ipc_mutation_with_finalizer;

use super::super::undo::{build_undo_token, compute_undo_expiry, LifecycleAction};
use super::super::*;
use super::shared::validate_batch_task_ids;

#[derive(Debug, serde::Serialize)]
pub struct BatchCompleteResult {
    pub completed_count: usize,
    pub completed: Vec<Task>,
    pub undo_tokens: Vec<String>,
    pub skipped: Vec<String>,
}

#[tauri::command]
pub fn batch_complete_tasks(task_ids: Vec<String>) -> Result<BatchCompleteResult, String> {
    batch_complete_tasks_inner(task_ids).map_err(String::from)
}

fn batch_complete_tasks_inner(task_ids: Vec<String>) -> Result<BatchCompleteResult, AppError> {
    let conn = get_conn()?;
    let (result, spotlight_ids) = batch_complete_tasks_with_conn_inner(&conn, task_ids)?;

    // event_bus emit is handled by the per-row executor.

    if !spotlight_ids.is_empty() {
        crate::platform::spotlight::apply_actions(
            &conn,
            &[crate::platform::spotlight::SpotlightAction::ReindexTaskIds(
                spotlight_ids,
            )],
        );
    }
    Ok(result)
}

/// `Mutation` descriptor for one task's completion transition inside
/// a `batch_complete_tasks` loop. Mirrors the single-task
/// `CompleteTaskMutation` in `completion/mod.rs`.
struct BatchCompleteTaskMutation<'a> {
    id: &'a lorvex_domain::TaskId,
    now: &'a str,
    result: RefCell<Option<CompletionLifecycleTransitionResult>>,
}

impl<'a> Mutation for BatchCompleteTaskMutation<'a> {
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
        let outcome = workflow_effects::run_completion(conn, self.id, self.now, hlc)?;
        let summary = format!("Batch-completed task '{}'", self.id.as_str());
        let after = serde_json::json!({ "id": self.id.as_str() });
        *self.result.borrow_mut() = Some(outcome);
        Ok(MutationOutput::new(after, summary))
    }
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
/// Transactional body of `batch_complete_tasks` against a
/// caller-supplied connection. Returns `(BatchCompleteResult,
/// spotlight_reindex_ids)` so the outer wrapper can drive the Spotlight
/// removal.
pub(crate) fn batch_complete_tasks_with_conn_inner(
    conn: &rusqlite::Connection,
    task_ids: Vec<String>,
) -> Result<(BatchCompleteResult, Vec<String>), AppError> {
    let task_ids = validate_batch_task_ids(&task_ids)?;
    with_immediate_transaction(conn, |conn| {
        let now = sync_timestamp_now();
        let expires_at = compute_undo_expiry();

        let mut completed_ids = Vec::with_capacity(task_ids.len());
        let mut undo_tokens = Vec::with_capacity(task_ids.len());
        let mut skipped = Vec::with_capacity(task_ids.len());
        let mut spotlight_ids = Vec::with_capacity(task_ids.len());

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

            let pre_task = task.clone();

            let task_id_typed = lorvex_domain::TaskId::from_trusted(id.clone());
            let mutation = BatchCompleteTaskMutation {
                id: &task_id_typed,
                now: &now,
                result: RefCell::new(None),
            };

            let mut captured: Option<CompletionLifecycleTransitionResult> = None;
            execute_ipc_mutation_with_finalizer(conn, &mutation, |conn, _execution| {
                let result =
                    mutation.result.borrow_mut().take().expect(
                        "batch complete mutation must populate transition result inside apply",
                    );
                enqueue_lifecycle_sync_plan(
                    conn,
                    lorvex_workflow::lifecycle::LifecycleSyncPlan::from_completion(&result),
                )?;
                if let Some(ref successor_id) = result.spawned_successor_id {
                    spotlight_ids.push(successor_id.clone());
                }

                // Unenriched read — `enqueue_task_upsert_*` strips
                // derived child fields anyway, so per-row enrichment
                // is wasted work inside the batch hot path.
                let updated = fetch_task_row_unenriched(conn, id)?;
                enqueue_task_upsert(conn, &updated)?;
                captured = Some(result);
                Ok(())
            })?;

            let result = captured
                .expect("batch complete finalizer must populate captured transition result");

            let undo_token = build_undo_token(
                &pre_task,
                LifecycleAction::Complete,
                false,
                result.spawned_successor_id.clone(),
                result.cancelled_reminder_ids.clone(),
                vec![],
                vec![],
                &expires_at,
            )?;

            crate::commands::diagnostics::undo_token_cache::register(id, &undo_token, &expires_at);

            undo_tokens.push(undo_token);
            completed_ids.push(id.clone());
            spotlight_ids.push(id.clone());
        }

        let completed = fetch_ordered_tasks_by_ids(conn, &completed_ids, "batch complete")?;

        Ok((
            BatchCompleteResult {
                completed_count: completed.len(),
                completed,
                undo_tokens,
                skipped,
            },
            spotlight_ids,
        ))
    })
}
