//! Test-only reopen path. Issue #2940-H1 removed the renderer-facing
//! `batch_reopen_tasks` Tauri command (no UI caller surfaced); the
//! transactional helper survives so the regression suite keeps
//! pinning the multi-task reopen semantics (terminal → open
//! transitions, validation, sync enqueue ordering).

#![cfg(test)]

use std::cell::RefCell;

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, OP_UPSERT, STATUS_OPEN};
use lorvex_store::StoreError;
use lorvex_workflow::lifecycle::{effects as workflow_effects, ReopenLifecycleTransitionResult};
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::Value;

use crate::commands::fetch_task_row_unenriched;
use crate::commands::shared::effects::execute_ipc_mutation_with_finalizer;

use super::super::*;
use super::shared::validate_batch_task_ids;

#[derive(Debug, serde::Serialize)]
pub struct BatchReopenResult {
    pub reopened_count: usize,
    pub reopened: Vec<Task>,
    pub skipped: Vec<String>,
}

/// `Mutation` descriptor for one task's reopen transition inside a
/// `batch_reopen_tasks` loop. Stashes the resulting
/// [`ReopenLifecycleTransitionResult`] so the surface finalizer can
/// build the `LifecycleSyncPlan` without re-running any SQL.
struct BatchReopenTaskMutation<'a> {
    id: &'a lorvex_domain::TaskId,
    before_status: lorvex_domain::naming::TaskStatus,
    now: &'a str,
    result: RefCell<Option<ReopenLifecycleTransitionResult>>,
}

impl<'a> Mutation for BatchReopenTaskMutation<'a> {
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
            workflow_effects::run_reopen(conn, self.id, self.before_status, self.now, hlc)?;
        let summary = format!("Batch-reopened task '{}'", self.id.as_str());
        let after = serde_json::json!({ "id": self.id.as_str() });
        *self.result.borrow_mut() = Some(outcome);
        Ok(MutationOutput::new(after, summary))
    }
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
/// Transactional body of `batch_reopen_tasks` against a caller-supplied
/// connection, returning the rich `BatchReopenResult`.
pub(crate) fn batch_reopen_tasks_with_conn(
    conn: &rusqlite::Connection,
    task_ids: Vec<String>,
) -> Result<BatchReopenResult, AppError> {
    let task_ids = validate_batch_task_ids(&task_ids)?;
    with_immediate_transaction(conn, |conn| {
        let now = sync_timestamp_now();
        let mut reopened_ids = Vec::with_capacity(task_ids.len());
        let mut skipped = Vec::with_capacity(task_ids.len());

        // Pre-fetch status for all tasks in one batch.
        let pre_map = fetch_tasks_by_ids(conn, &task_ids)?;

        for id in &task_ids {
            let Some(task) = pre_map.get(id) else {
                skipped.push(id.clone());
                continue;
            };
            if task.status == STATUS_OPEN {
                skipped.push(id.clone());
                continue;
            }

            let task_id_typed = lorvex_domain::TaskId::from_trusted(id.clone());
            let before_status =
                lorvex_store::repositories::task::write::parse_task_status_for_update(
                    id,
                    &task.status,
                )?;
            let mutation = BatchReopenTaskMutation {
                id: &task_id_typed,
                before_status,
                now: &now,
                result: RefCell::new(None),
            };

            execute_ipc_mutation_with_finalizer(conn, &mutation, |conn, _execution| {
                let result =
                    mutation.result.borrow_mut().take().expect(
                        "batch reopen mutation must populate transition result inside apply",
                    );
                enqueue_lifecycle_sync_plan(
                    conn,
                    lorvex_workflow::lifecycle::LifecycleSyncPlan::from_reopen(&result),
                )?;

                // Unenriched — `enqueue_task_upsert` strips derived
                // child fields anyway.
                let updated = fetch_task_row_unenriched(conn, id)?;
                enqueue_task_upsert(conn, &updated)?;
                Ok(())
            })?;

            reopened_ids.push(id.clone());
        }

        // Batch re-fetch for post-stamp versions.
        let reopened = fetch_ordered_tasks_by_ids(conn, &reopened_ids, "batch reopen")?;

        Ok(BatchReopenResult {
            reopened_count: reopened.len(),
            reopened,
            skipped,
        })
    })
}
