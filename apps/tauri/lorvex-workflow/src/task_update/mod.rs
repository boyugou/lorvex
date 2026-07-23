//! Single-item `update_task` workflow operation.
//!
//! Mirrors the MCP server's update flow (see
//! `mcp-server/src/tasks/mutations/update`) at the cross-surface
//! layer: every consumer surface (MCP, Tauri, CLI) routes its
//! `update_task` mutation through this module so the SQL writes,
//! lifecycle transitions, recurrence + due_date co-application, edge
//! diffing, and per-row sync-effect accumulation all live in one
//! place.
//!
//! Bit-identical to `task_batch_update::batch_update_tasks` for a
//! single-row patch — both delegate to the shared
//! [`mutation::apply_single_update_in_savepoint`] core.

mod effects;
mod flush;
mod input;
pub(crate) mod mutation;

#[cfg(test)]
mod tests;

pub use flush::{
    flush_with_backend, MutationFlushBackend, TaskUpdateBackendError, TaskUpdateFlushBackend,
};
pub use input::TaskUpdateInput;
pub use mutation::{
    TaskTagEdgeDelete, TaskUpdateSyncEffects, UpdateTaskCancelledSuccessor,
    UpdateTaskFocusRewireAudit, UpdateTaskSpawnedSuccessor,
};

use lorvex_domain::hlc_session::HlcSession;
use lorvex_store::StoreError;
use rusqlite::Connection;
use serde_json::{json, Value};

use crate::task_response::{load_enriched_task_json, load_enriched_tasks_json};

/// Result of [`update_task`]: the enriched task JSON before and after
/// the patch, the per-task sync-effect set every surface adapter
/// flushes to its outbox, and a human-readable summary for the
/// changelog.
#[derive(Debug)]
pub struct UpdatedTaskOutcome {
    pub task_id: String,
    pub before_task: Value,
    pub updated_task: Value,
    pub payload: Value,
    pub summary: String,
    pub sync_effects: TaskUpdateSyncEffects,
}

/// Apply a single typed task update.
///
/// Opens its own savepoint, runs the shared per-row apply, re-runs the
/// dependency-cycle validator over the final edge state, and reloads
/// the enriched task JSON for the response. The caller drives the HLC
/// session and is responsible for flushing
/// [`TaskUpdateSyncEffects`] to the outbox + writing the audit row +
/// bumping `local_change_seq`.
pub fn update_task(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    input: TaskUpdateInput,
) -> Result<UpdatedTaskOutcome, StoreError> {
    let mut input = input;
    mutation::sanitize_input(&mut input);
    mutation::validate_task_id_shape(&input.id, "id")?;
    let task_id = input.id.clone();
    let before_task =
        load_enriched_task_json(conn, &lorvex_domain::TaskId::from_trusted(task_id.clone()))?;
    let before_status = before_task
        .get("status")
        .and_then(Value::as_str)
        .ok_or_else(|| {
            StoreError::Invariant(
                "update_task before-task: missing string field `status`".to_string(),
            )
        })?
        .to_string();
    let now = lorvex_domain::sync_timestamp_now();

    let mut sync_effects = TaskUpdateSyncEffects::default();
    lorvex_store::with_savepoint_mapped(
        conn,
        "workflow_update_task",
        StoreError::from,
        |conn| -> Result<(), StoreError> {
            let mut dep_changed_ids = Vec::new();
            mutation::apply_single_update_in_savepoint(
                conn,
                hlc,
                &input,
                &before_task,
                &before_status,
                &now,
                &mut sync_effects,
                &mut dep_changed_ids,
            )?;
            mutation::revalidate_dependency_cycles(conn, &dep_changed_ids, "update_task")?;
            Ok(())
        },
    )?;

    let updated_tasks = load_enriched_tasks_json(conn, std::slice::from_ref(&task_id))?;
    let updated_task = updated_tasks
        .into_iter()
        .next()
        .ok_or_else(|| StoreError::Invariant("update_task after-task: row vanished".to_string()))?;
    let title = updated_task
        .get("title")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let summary = format!("Updated task '{title}'");
    let payload = json!({
        "task": updated_task,
        "undo_token": Value::Null,
    });

    Ok(UpdatedTaskOutcome {
        task_id,
        before_task,
        updated_task: payload["task"].clone(),
        payload,
        summary,
        sync_effects,
    })
}
