//! Bulk purge: walk every task with status `cancelled`, run the
//! cascade-delete bookkeeping for each, and hard-delete the rows in
//! a single writer transaction. Surfaces a typed
//! [`PurgeCancelledTasksResult`] (vs. the previous loose
//! `serde_json::Value`) so the renderer can update its in-memory
//! cache from the response without a redundant round-trip.

use std::cell::RefCell;

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, OP_DELETE};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::Value;

use super::super::super::*;
use super::cascade::{cleanup_plan_refs_after_removal, enqueue_cascaded_task_child_deletes};
use crate::commands::shared::effects::execute_ipc_mutation_with_finalizer;

/// Typed result for `purge_cancelled_tasks`. Ships `purged_count`
/// (the canonical name across batch ops) and the explicit
/// `purged_task_ids` list so the UI can update its in-memory cache
/// without re-querying — a `serde_json::Value` returning only
/// `{deleted: N}` would force callers to round-trip just to learn
/// which task ids were destroyed.
#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct PurgeCancelledTasksResult {
    pub purged_count: usize,
    pub purged_task_ids: Vec<String>,
}

/// One row scheduled for hard-delete inside the bulk purge.
struct PurgeTarget {
    snapshot: crate::commands::Task,
    delete_version: String,
}

/// `Mutation` descriptor for the bulk cancelled-task purge.
///
/// `apply` performs the cascade cleanup and the LWW hard-delete
/// inline, then stashes the per-task delete tuples in `enqueue_targets`
/// so the surface finalizer can emit the matching outbox tombstones
/// under the executor's `local_change_seq` bump + event_bus broadcast.
struct PurgeCancelledTasksMutation {
    enqueue_targets: RefCell<Vec<PurgeTarget>>,
}

impl PurgeCancelledTasksMutation {
    fn new() -> Self {
        Self {
            enqueue_targets: RefCell::new(Vec::new()),
        }
    }
}

impl Mutation for PurgeCancelledTasksMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }
    fn operation(&self) -> &'static str {
        OP_DELETE
    }
    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }
    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let count: i64 = conn.query_row(
            "SELECT COUNT(*) FROM tasks WHERE status = 'cancelled'",
            [],
            |row| row.get(0),
        )?;
        if count == 0 {
            return Ok(MutationOutput::new(
                serde_json::json!({ "purged_count": 0 }),
                "Purged 0 cancelled tasks",
            ));
        }

        // collect FULL Task snapshots, not just IDs, so
        // the outbox delete envelopes carry the pre-delete version
        // (HLC). Without this, peers processing the delete receive
        // only `{"id": "..."}` and the LWW tombstone guard has
        // nothing to compare against — a concurrent re-open of the
        // same task on another device could be incorrectly wiped.
        let mut stmt = conn.prepare_cached("SELECT id FROM tasks WHERE status = 'cancelled'")?;
        let cancelled_ids: Vec<String> = stmt
            .query_map([], |row| row.get(0))?
            .collect::<Result<Vec<_>, _>>()?;
        drop(stmt);
        let cancelled_snapshots: Vec<crate::commands::Task> = cancelled_ids
            .iter()
            .map(|id| {
                crate::commands::fetch_task_by_id(conn, id).map_err(|err| match err {
                    AppError::Store(s) => *s,
                    other => StoreError::Invariant(other.to_string()),
                })
            })
            .collect::<Result<Vec<_>, _>>()?;

        let mut purge_targets: Vec<PurgeTarget> = Vec::new();
        for snapshot in cancelled_snapshots {
            let delete_version = hlc.next_version_string();
            if delete_version.as_str() > snapshot.version.as_str() {
                purge_targets.push(PurgeTarget {
                    snapshot,
                    delete_version,
                });
            }
        }

        if purge_targets.is_empty() {
            return Ok(MutationOutput::new(
                serde_json::json!({ "purged_count": 0 }),
                "Purged 0 cancelled tasks",
            ));
        }

        let purge_task_ids: Vec<String> = purge_targets
            .iter()
            .map(|t| t.snapshot.id.clone())
            .collect();

        // Clean up orphaned references in current_focus, focus_schedule, and dependency edges.
        let now_for_deps = lorvex_domain::sync_timestamp_now();
        for task_id in &purge_task_ids {
            enqueue_cascaded_task_child_deletes(conn, task_id, &now_for_deps).map_err(|err| {
                match err {
                    AppError::Store(s) => *s,
                    other => StoreError::Invariant(other.to_string()),
                }
            })?;
        }

        // Keep these pre-task-delete clears because some older cleanup
        // paths still inspect reminder/link tables before the final task
        // row DELETE lands. The explicit per-entity delete+tombstone
        // enqueue above is what makes the cascades visible to peers.
        for task_id in &purge_task_ids {
            conn.prepare_cached("DELETE FROM task_reminders WHERE task_id = ?1")?
                .execute([task_id])?;

            conn.prepare_cached("DELETE FROM task_calendar_event_links WHERE task_id = ?1")?
                .execute([task_id])?;

            cleanup_plan_refs_after_removal(conn, task_id).map_err(|err| match err {
                AppError::Store(s) => *s,
                other => StoreError::Invariant(other.to_string()),
            })?;
            // Propagate the error explicitly: a silent `let _ =`
            // drop would leave other tasks locally blocked by
            // cancelled ones AND skip the tombstone enqueue so the
            // dependency edge would never propagate as removed to
            // peer devices.
            let task_id_typed = lorvex_domain::TaskId::from_trusted(task_id.to_string());
            let affected_dependent_ids =
                crate::commands::tasks::dependencies::cleanup_task_dependency_refs_after_removal(
                    conn,
                    &task_id_typed,
                    &now_for_deps,
                )
                .map_err(|err| match err {
                    AppError::Store(s) => *s,
                    other => StoreError::Invariant(other.to_string()),
                })?;
            enqueue_affected_dependents(conn, &affected_dependent_ids).map_err(
                |err| match err {
                    AppError::Store(s) => *s,
                    other => StoreError::Invariant(other.to_string()),
                },
            )?;
        }

        let mut completed: Vec<PurgeTarget> = Vec::new();
        for target in purge_targets {
            let task_id = lorvex_domain::TaskId::from_trusted(target.snapshot.id.clone());
            let deleted = lorvex_store::repositories::task::write::hard_delete_task_lww(
                conn,
                &task_id,
                &target.delete_version,
            )?;
            if deleted > 0 {
                completed.push(target);
            }
        }

        let after = serde_json::json!({
            "purged_count": completed.len(),
            "purged_task_ids": completed.iter().map(|t| t.snapshot.id.clone()).collect::<Vec<_>>(),
        });
        let summary = format!("Purged {} cancelled task(s)", completed.len());
        *self.enqueue_targets.borrow_mut() = completed;
        Ok(MutationOutput::new(after, summary))
    }
}

/// Permanently delete all tasks with status 'cancelled'.
#[tauri::command]
pub fn purge_cancelled_tasks() -> Result<PurgeCancelledTasksResult, String> {
    purge_cancelled_tasks_inner().map_err(String::from)
}

fn purge_cancelled_tasks_inner() -> Result<PurgeCancelledTasksResult, AppError> {
    let conn = get_conn()?;
    let result = purge_cancelled_tasks_with_conn(&conn)?;

    // event_bus emit is handled by the executor (always emits even when 0
    // rows were purged, which is acceptable — the prior code skipped the
    // emit on empty, but a no-op invalidate is cheap and consistent with
    // every other executor-routed surface).

    // Post-commit: remove purged tasks from Spotlight index.
    if !result.purged_task_ids.is_empty() {
        crate::platform::spotlight::apply_actions(
            &conn,
            &[crate::platform::spotlight::SpotlightAction::RemoveTaskIds(
                result.purged_task_ids.clone(),
            )],
        );
    }
    Ok(result)
}

/// Transactional body of `purge_cancelled_tasks` against a
/// caller-supplied connection. Returns the typed
/// `PurgeCancelledTasksResult` so the outer wrapper (or a test) can
/// drive the Spotlight removal off the purged ids.
pub(crate) fn purge_cancelled_tasks_with_conn(
    conn: &rusqlite::Connection,
) -> Result<PurgeCancelledTasksResult, AppError> {
    with_immediate_transaction(conn, |conn| {
        let mutation = PurgeCancelledTasksMutation::new();
        execute_ipc_mutation_with_finalizer(conn, &mutation, |conn, _execution| {
            for target in mutation.enqueue_targets.borrow().iter() {
                crate::commands::enqueue_task_delete_with_version(
                    conn,
                    &target.snapshot.id,
                    Some(&target.snapshot),
                    &target.delete_version,
                )?;
            }
            Ok(())
        })?;
        let targets = mutation.enqueue_targets.into_inner();
        let purged_task_ids: Vec<String> = targets.iter().map(|t| t.snapshot.id.clone()).collect();
        Ok(PurgeCancelledTasksResult {
            purged_count: purged_task_ids.len(),
            purged_task_ids,
        })
    })
}
