//! "Shelve all" — atomically move all open tasks in a list to
//! `someday` status. Each per-task status flip is wrapped in a
//! `Mutation` descriptor and routed through
//! [`execute_ipc_mutation_with_finalizer`] so the canonical
//! `apply_task_update` patch path applies the LWW gate
//! (`new_version > existing_version`) and the
//! `status_transition_columns` metadata, and the per-row
//! `local_change_seq++` + event_bus broadcast share one pipeline
//! with every other Tauri write.

use std::cell::RefCell;

use rusqlite::{params, Connection};
use serde_json::Value;

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{TaskStatus, ENTITY_TASK, OP_UPSERT};
use lorvex_store::repositories::task::write::{self, TaskUpdatePatch};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};

use crate::commands::shared::effects::execute_ipc_mutation_with_finalizer;
use crate::commands::{
    enqueue_task_upsert, fetch_list_by_id, fetch_task_by_id, fetch_task_row_unenriched,
    sync_timestamp_now, with_immediate_transaction,
};
use crate::db::get_conn;
use crate::error::{AppError, AppResult};

#[derive(Debug, serde::Serialize)]
pub struct ShelveListResult {
    /// Number of tasks successfully transitioned to `someday`. Equals
    /// `shelved_task_ids.len()` — kept as an explicit field so the UI
    /// doesn't have to read `.length` on the array (and so a future
    /// pagination path can diverge if needed).
    pub shelved_count: usize,
    /// IDs of the tasks that were actually flipped to `someday` by this
    /// invocation. Excludes any tasks that the LWW gate rejected or
    /// that a peer apply moved off `open` between the SELECT and the
    /// per-row UPDATE — those are reported separately in
    /// `skipped_task_ids` so callers can surface a "couldn't shelve N
    /// tasks — they changed elsewhere" message instead of pretending
    /// the operation landed cleanly.
    pub shelved_task_ids: Vec<String>,
    /// IDs of tasks that were enumerated as `open` at SELECT time but
    /// could NOT be transitioned by this invocation, either because a
    /// concurrent apply changed their status before the per-row UPDATE
    /// or because `apply_task_update`'s LWW gate rejected the write
    /// (a strictly-newer remote envelope had already landed). The same
    /// rows will reconverge on the next sync apply tick.
    pub skipped_task_ids: Vec<String>,
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn shelve_list(list_id: String) -> Result<ShelveListResult, String> {
    // shape-check the list id at the IPC boundary before opening the
    // writer transaction. List-id contexts accept the `INBOX_LIST_ID`
    // sentinel — the CLI already does, parity at this trust boundary.
    let list_id_str = crate::commands::shared::validate_list_id(&list_id, "list_id")?;
    let list_id = lorvex_domain::ListId::from_trusted(list_id_str);
    shelve_list_inner(&list_id).map_err(String::from)
}

fn shelve_list_inner(list_id: &lorvex_domain::ListId) -> AppResult<ShelveListResult> {
    let conn = get_conn()?;
    let result = shelve_list_with_conn(&conn, list_id)?;
    // event_bus emit is handled by the per-row executor.
    Ok(result)
}

/// `Mutation` descriptor for one task's shelve transition inside a
/// `shelve_list` loop. The patch carries `status = Someday`,
/// `before_status` for status-transition metadata, and an empty rest;
/// `apply_task_update` issues the canonical
/// `version = ? + updated_at = ?` SET clauses and applies the strict
/// `?version > tasks.version` LWW gate. The LWW-rejected branch
/// records the outcome in `rejected_by_lww` so the surface finalizer
/// skips the upsert enqueue.
struct ShelveTaskMutation<'a> {
    task_id: &'a str,
    before_status: &'a str,
    now: &'a str,
    rejected_by_lww: RefCell<bool>,
}

impl<'a> Mutation for ShelveTaskMutation<'a> {
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
            status: Some(TaskStatus::Someday),
            version: &version,
            now: self.now,
            before_status: Some(write::parse_task_status_for_update(
                self.task_id,
                self.before_status,
            )?),
            ..Default::default()
        };
        match write::apply_task_update(conn, &patch) {
            Ok(()) => {}
            Err(StoreError::StaleVersion { .. }) => {
                *self.rejected_by_lww.borrow_mut() = true;
            }
            Err(e) => return Err(e),
        }
        let summary = format!("Shelved task '{}' → someday", self.task_id);
        let after = serde_json::json!({ "id": self.task_id });
        Ok(MutationOutput::new(after, summary))
    }
}

/// Testable entry point — runs the shelve transaction against a
/// caller-supplied connection.
///
/// Routes every per-task status flip through a [`ShelveTaskMutation`]
/// descriptor so the canonical patch path applies the LWW gate and
/// the `status_transition_columns` metadata, and the per-row
/// executor finalizer applies the standard `local_change_seq++` +
/// `event_bus::emit_data_changed` side effects.
pub(crate) fn shelve_list_with_conn(
    conn: &rusqlite::Connection,
    list_id: &lorvex_domain::ListId,
) -> AppResult<ShelveListResult> {
    with_immediate_transaction(conn, |conn| {
        // Verify the list exists
        fetch_list_by_id(conn, list_id.as_str())?
            .ok_or_else(|| AppError::NotFound(format!("List {list_id} not found")))?;

        // Find all open tasks in this list
        let open_ids: Vec<String> = conn
            .prepare_cached(
                "SELECT id FROM tasks \
                 WHERE list_id = ?1 AND status = 'open' AND archived_at IS NULL",
            )
            .and_then(|mut s| {
                s.query_map(params![list_id.as_str()], |r| r.get(0))
                    .and_then(|rows| rows.collect())
            })
            .map_err(AppError::from)?;

        if open_ids.is_empty() {
            return Ok(ShelveListResult {
                shelved_count: 0,
                shelved_task_ids: vec![],
                skipped_task_ids: vec![],
            });
        }

        // Cap the resulting bulk-shelve batch so a pathologically large
        // list (e.g. an inbox bloated by an import) can't pin the writer
        // transaction for minutes while every other writer waits. The
        // user can re-issue the shelve until the list drains; one
        // `MAX_IPC_BATCH_ITEMS`-sized chunk per call still finishes in
        // well under a second on ordinary hardware.
        if open_ids.len() > crate::commands::shared::MAX_IPC_BATCH_ITEMS {
            return Err(AppError::Validation(format!(
                "list contains {} open tasks; shelve cap is {} per call",
                open_ids.len(),
                crate::commands::shared::MAX_IPC_BATCH_ITEMS
            )));
        }

        let now = sync_timestamp_now();

        let mut shelved_task_ids: Vec<String> = Vec::with_capacity(open_ids.len());
        let mut skipped_task_ids: Vec<String> = Vec::new();
        for id in &open_ids {
            // Snapshot the pre-update state so the patch carries the
            // correct `before_status` for status-transition metadata.
            // Re-fetch inside the loop because earlier iterations may
            // have changed shared state (none in practice today, but
            // the cost is one indexed lookup per task and it keeps the
            // pattern uniform with batch.rs / updates.rs).
            let pre_task = fetch_task_by_id(conn, id)?;
            // A peer apply may have raced this loop and already moved
            // the row off `open` (e.g. cancelled it). Skip without
            // logging or enqueueing — the batch_move pattern does the
            // same on a stale-status row.
            if pre_task.status != "open" {
                skipped_task_ids.push(id.clone());
                continue;
            }

            let mutation = ShelveTaskMutation {
                task_id: id,
                before_status: &pre_task.status,
                now: &now,
                rejected_by_lww: RefCell::new(false),
            };

            execute_ipc_mutation_with_finalizer(conn, &mutation, |conn, _execution| {
                if *mutation.rejected_by_lww.borrow() {
                    return Ok(());
                }
                // Unenriched — `enqueue_task_upsert` strips derived
                // fields.
                let task = fetch_task_row_unenriched(conn, id)?;
                enqueue_task_upsert(conn, &task)?;
                Ok(())
            })?;

            if *mutation.rejected_by_lww.borrow() {
                skipped_task_ids.push(id.clone());
                continue;
            }
            shelved_task_ids.push(id.clone());
        }

        Ok(ShelveListResult {
            shelved_count: shelved_task_ids.len(),
            shelved_task_ids,
            skipped_task_ids,
        })
    })
}
