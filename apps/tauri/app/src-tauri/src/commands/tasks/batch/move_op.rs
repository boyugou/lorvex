//! UI bulk "Move to list" runs `batch_move_tasks` as one writer
//! transaction with a per-task `Mutation<M>` descriptor routed through
//! [`execute_ipc_mutation_with_finalizer`]. Per-task skip semantics
//! cover cancelled rows, no-op moves, and LWW-rejected stamps; a
//! Spotlight reindex runs for every mutated row after the transaction
//! commits. (File renamed to `move_op` because `move` is a reserved
//! Rust keyword.)

use std::cell::RefCell;

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, OP_UPSERT, STATUS_CANCELLED};
use lorvex_domain::Patch;
use lorvex_store::repositories::task::write::{self, TaskUpdatePatch};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::Value;

use crate::commands::fetch_task_row_unenriched;
use crate::commands::shared::effects::execute_ipc_mutation_with_finalizer;

use super::super::*;
use super::shared::validate_batch_task_ids;

#[derive(Debug, serde::Serialize)]
pub struct BatchMoveResult {
    pub moved_count: usize,
    pub moved: Vec<Task>,
    pub skipped: Vec<String>,
}

#[tauri::command]
pub fn batch_move_tasks(
    task_ids: Vec<String>,
    target_list_id: Option<String>,
) -> Result<BatchMoveResult, String> {
    batch_move_tasks_inner(task_ids, target_list_id).map_err(String::from)
}

fn batch_move_tasks_inner(
    task_ids: Vec<String>,
    target_list_id: Option<String>,
) -> Result<BatchMoveResult, AppError> {
    let conn = get_conn()?;
    let result = batch_move_tasks_with_conn(&conn, task_ids, target_list_id)?;

    // event_bus emit is handled by the per-row executor.

    // Post-commit Spotlight dispatch: re-index moved tasks so their
    // `list_name` field reflects the new parent list in search results.
    if !result.moved.is_empty() {
        let moved_ids: Vec<String> = result.moved.iter().map(|t| t.id.clone()).collect();
        crate::platform::spotlight::apply_actions(
            &conn,
            &[crate::platform::spotlight::SpotlightAction::ReindexTaskIds(
                moved_ids,
            )],
        );
    }
    Ok(result)
}

/// `Mutation` descriptor for one task's move-to-list inside a
/// `batch_move_tasks` loop. `apply` runs the canonical
/// `apply_task_update` patch with `list_id = Patch::Set(target)`
/// under the per-mutation `HlcSession`. The LWW-rejected branch
/// records the outcome in `rejected_by_lww` so the surface
/// finalizer skips the upsert enqueue and the caller adds the row
/// to the batch's `skipped` list.
struct BatchMoveTaskMutation<'a> {
    task_id: &'a str,
    target_list_id: &'a str,
    before_status: &'a str,
    now: &'a str,
    rejected_by_lww: RefCell<bool>,
}

impl<'a> Mutation for BatchMoveTaskMutation<'a> {
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
        let version = hlc.next_version_string();
        let patch = TaskUpdatePatch {
            task_id: self.task_id,
            list_id: Patch::Set(self.target_list_id),
            version: &version,
            now: self.now,
            before_status: Some(write::parse_task_status_for_update(
                self.task_id,
                self.before_status,
            )?),
            ..Default::default()
        };
        // The LWW guard rejecting this task's move (because a peer
        // envelope landed a strictly-newer `version` between the
        // per-task SELECT above and the gated UPDATE) surfaces as
        // `StoreError::StaleVersion`. Record the outcome so the
        // surface finalizer skips the upsert enqueue (no misleading
        // payload) and the caller adds the id to `skipped`.
        match write::apply_task_update(conn, &patch) {
            Ok(()) => {}
            Err(StoreError::StaleVersion { .. }) => {
                *self.rejected_by_lww.borrow_mut() = true;
            }
            Err(e) => return Err(e),
        }
        let summary = format!(
            "Batch-moved task '{}' → list '{}'",
            self.task_id, self.target_list_id
        );
        let after = serde_json::json!({ "id": self.task_id });
        Ok(MutationOutput::new(after, summary))
    }
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
/// Transactional body of `batch_move_tasks` against a caller-supplied
/// connection, returning the rich `BatchMoveResult`.
pub(crate) fn batch_move_tasks_with_conn(
    conn: &rusqlite::Connection,
    task_ids: Vec<String>,
    target_list_id: Option<String>,
) -> Result<BatchMoveResult, AppError> {
    let task_ids = validate_batch_task_ids(&task_ids)?;
    // A task must always belong to a real list; clearing list_id on a
    // move is nonsensical and would silently leave tasks orphaned. The
    // single-task `update_task` path enforces this invariant — batch
    // the same guard here so the batch endpoint can't be used as an
    // escape hatch around it.
    let target_list_id = target_list_id.ok_or_else(|| {
        AppError::Validation(
            "Tasks must belong to a real list. Choose a target list before moving.".to_string(),
        )
    })?;
    // `target_list_id` is a list-id field — accept the schema-seeded
    // `INBOX_LIST_ID` sentinel here too so `batch_move_tasks` matches
    // the CLI's `task move <list> ...` semantics for the canonical
    // default list.
    let target_list_id =
        crate::commands::shared::validate_list_id(&target_list_id, "target_list_id")
            .map_err(AppError::Validation)?;

    with_immediate_transaction(conn, |conn| {
        let now = sync_timestamp_now();
        let mut moved_ids = Vec::new();
        let mut skipped = Vec::new();

        // Single batch fetch for pre-mutation status / list_id.
        let pre_map = fetch_tasks_by_ids(conn, &task_ids)?;

        for id in &task_ids {
            let Some(task) = pre_map.get(id) else {
                skipped.push(id.clone());
                continue;
            };
            // Skip cancelled tasks (tombstones mustn't be resurrected
            // via a list move) and no-op moves (already in target list).
            if task.status == STATUS_CANCELLED || task.list_id == target_list_id {
                skipped.push(id.clone());
                continue;
            }

            let mutation = BatchMoveTaskMutation {
                task_id: id,
                target_list_id: target_list_id.as_str(),
                before_status: &task.status,
                now: &now,
                rejected_by_lww: RefCell::new(false),
            };

            execute_ipc_mutation_with_finalizer(conn, &mutation, |conn, _execution| {
                if *mutation.rejected_by_lww.borrow() {
                    // Skip the upsert enqueue when LWW rejected the
                    // local stamp — the peer's freshly-applied row
                    // already carries the authoritative state.
                    return Ok(());
                }
                // Unenriched — `enqueue_task_upsert` strips derived
                // fields.
                let updated = fetch_task_row_unenriched(conn, id)?;
                enqueue_task_upsert(conn, &updated)?;
                Ok(())
            })?;

            if *mutation.rejected_by_lww.borrow() {
                skipped.push(id.clone());
                continue;
            }
            moved_ids.push(id.clone());
        }

        let moved = fetch_ordered_tasks_by_ids(conn, &moved_ids, "batch move")?;
        Ok(BatchMoveResult {
            moved_count: moved.len(),
            moved,
            skipped,
        })
    })
}
