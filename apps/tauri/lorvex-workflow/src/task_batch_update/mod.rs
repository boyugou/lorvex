//! Batch task-update workflow operation.
//!
//! Mirrors MCP `batch_update_tasks`. Iterates over a vector of typed
//! [`BatchUpdateTaskPatchInput`] patches, dispatching each to the
//! shared per-row apply core
//! (`task_update::mutation::apply_single_update_in_savepoint`) the
//! single-item [`crate::task_update::update_task`] also uses, then
//! runs the cross-row dependency-cycle revalidation against the
//! final edge state.
//!
//! Keeping the per-row body in one place ensures the single-item and
//! batch surfaces stay bit-identical: any future change to the
//! per-row contract flows through both call sites automatically.
//!
//! Module layout:
//!
//! * [`input`] — wire-shape patch input + batch cap.
//! * [`sync_effects`] — re-exports of the per-row sync-effect
//!   accumulator under batch-named aliases.
//! * [`dependency_plan`] — cross-row id-list guards (UUID shape,
//!   duplicates, batch cap).
//! * [`summary`] — audit-summary builder.

mod dependency_plan;
mod input;
mod summary;
mod sync_effects;

pub use input::{BatchUpdateTaskPatchInput, BatchUpdateTasksInput};
pub use sync_effects::{
    BatchUpdateCancelledSuccessor, BatchUpdateFocusRewireAudit, BatchUpdateSpawnedSuccessor,
    BatchUpdateSyncEffects, TaskTagEdgeDelete,
};

use dependency_plan::validate_batch_ids;
use input::BATCH_UPDATE_TASKS_LIMIT;
use summary::build_batch_update_summary;

use lorvex_domain::hlc_session::HlcSession;
use lorvex_store::StoreError;
use rusqlite::Connection;
use serde_json::{json, Value};

use crate::task_response::load_enriched_tasks_json;
use crate::task_update::mutation::{
    apply_single_update_in_savepoint, revalidate_dependency_cycles, sanitize_input,
};

#[derive(Debug)]
pub struct BatchUpdateTasksResult {
    pub updated_ids: Vec<String>,
    pub before_tasks: Vec<Value>,
    pub updated_tasks: Vec<Value>,
    pub payload: Value,
    pub summary: String,
    pub sync_effects: BatchUpdateSyncEffects,
}

pub fn batch_update_tasks(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    input: BatchUpdateTasksInput,
) -> Result<BatchUpdateTasksResult, StoreError> {
    let mut updates = input.updates;
    if updates.is_empty() {
        return Err(StoreError::Validation(
            "updates must contain at least one item".to_string(),
        ));
    }
    if updates.len() > BATCH_UPDATE_TASKS_LIMIT {
        return Err(StoreError::Validation(format!(
            "batch_update_tasks supports at most {BATCH_UPDATE_TASKS_LIMIT} items, got {}",
            updates.len()
        )));
    }
    for patch in updates.iter_mut() {
        sanitize_input(patch);
    }
    let update_ids = updates
        .iter()
        .map(|update| update.id.clone())
        .collect::<Vec<_>>();
    validate_batch_ids(&update_ids, "batch_update_tasks")?;
    let before_tasks = load_enriched_tasks_json(conn, &update_ids)?;
    let mut before_by_id = std::collections::BTreeMap::new();
    for (id, task) in update_ids.iter().zip(before_tasks.iter()) {
        before_by_id.insert(id.clone(), task.clone());
    }

    let now = lorvex_domain::sync_timestamp_now();
    let mut sync_effects = BatchUpdateSyncEffects::default();
    let updated_ids = lorvex_store::with_savepoint_mapped(
        conn,
        "workflow_batch_update",
        StoreError::from,
        |conn| -> Result<Vec<String>, StoreError> {
            let mut updated_ids = Vec::with_capacity(updates.len());
            let mut dep_changed_ids = Vec::new();
            for update in &updates {
                let before = before_by_id
                    .get(&update.id)
                    .ok_or_else(|| StoreError::NotFound {
                        entity: lorvex_domain::naming::ENTITY_TASK,
                        id: update.id.clone(),
                    })?;
                let before_status =
                    before
                        .get("status")
                        .and_then(Value::as_str)
                        .ok_or_else(|| {
                            StoreError::Invariant(
                                "batch_update_tasks before-task: missing string field `status`"
                                    .to_string(),
                            )
                        })?;
                apply_single_update_in_savepoint(
                    conn,
                    hlc,
                    update,
                    before,
                    before_status,
                    &now,
                    &mut sync_effects,
                    &mut dep_changed_ids,
                )?;
                updated_ids.push(update.id.clone());
            }
            revalidate_dependency_cycles(conn, &dep_changed_ids, "batch_update_tasks")?;
            Ok(updated_ids)
        },
    )?;

    let updated_tasks = load_enriched_tasks_json(conn, &updated_ids)?;
    let summary = build_batch_update_summary(&updated_tasks)?;
    let payload = json!({
        "updated_count": updated_tasks.len(),
        "tasks": updated_tasks,
        "undo_token": Value::Null,
    });

    Ok(BatchUpdateTasksResult {
        updated_ids,
        before_tasks,
        updated_tasks: payload["tasks"].as_array().cloned().unwrap_or_default(),
        payload,
        summary,
        sync_effects,
    })
}
