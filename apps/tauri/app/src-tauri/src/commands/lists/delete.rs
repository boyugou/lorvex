//! `delete_list` IPC command — typed
//! [`lorvex_workflow::mutation::Mutation`] descriptor wrapping the
//! shared `list_repo::delete_list_lww` call. Routes through
//! [`crate::commands::shared::effects::execute_ipc_entity_mutation`].
//!
//! The pre-delete `EntitySnapshot` needed for the undo toast is
//! captured inside `apply` and surfaced back through
//! [`lorvex_workflow::mutation::MutationOutput::set_extra`] under
//! [`lorvex_workflow::mutation_extras::LIST_DELETE_UNDO_SNAPSHOT`].
//! The surrounding handler reads the snapshot out, mints the undo
//! token, and returns the [`DeleteListResult`] to the caller.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_LIST, OP_DELETE};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use lorvex_workflow::mutation_extras::LIST_DELETE_UNDO_SNAPSHOT;
use rusqlite::Connection;
use serde_json::Value;

use crate::commands::calendar::events::{build_undo_token, capture_list_snapshot};
use crate::commands::shared::effects::execute_ipc_entity_mutation;
use crate::commands::{
    enqueue_list_delete_with_version, fetch_list_by_id, with_immediate_transaction,
    DeleteListResult,
};
use crate::db::get_conn;
use crate::error::{AppError, AppResult};

/// Validated arguments for the descriptor. The pre-delete row check
/// (and the assigned-task invariant) live in the surrounding handler
/// so `apply` sees an already-validated id.
struct DeleteListMutation<'a> {
    id: &'a lorvex_domain::ListId,
    /// Mirror of the human-facing list name; threaded in for the
    /// audit summary only so the descriptor doesn't have to reload
    /// the row after the surrounding handler already loaded it.
    name: &'a str,
}

impl<'a> Mutation for DeleteListMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_LIST
    }
    fn operation(&self) -> &'static str {
        OP_DELETE
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        // No audit funnel consumes this on Tauri; the undo-snapshot
        // path uses `MutationOutput::extra` instead.
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        // Capture the undo snapshot BEFORE the row is wiped — mirrors
        // the calendar-event delete ordering rule.
        let snapshot = capture_list_snapshot(conn, self.id.as_str()).map_err(|e| match e {
            AppError::Store(boxed) => *boxed,
            AppError::NotFound(msg) => StoreError::NotFound {
                entity: ENTITY_LIST,
                id: msg,
            },
            other => StoreError::Invariant(other.to_string()),
        })?;
        let snapshot_json = serde_json::to_value(&snapshot).map_err(|e| {
            StoreError::Serialization(format!(
                "list delete snapshot serialization failed for '{}': {e}",
                self.id.as_str()
            ))
        })?;

        let delete_version = hlc.next_version_string();
        let deleted =
            lorvex_store::repositories::list_repo::delete_list_lww(conn, self.id, &delete_version)?;
        if deleted == 0 {
            return Err(StoreError::NotFound {
                entity: ENTITY_LIST,
                id: self.id.as_str().to_string(),
            });
        }

        let mut output = MutationOutput::new(
            serde_json::json!({
                "id": self.id.as_str(),
                "deleted": true,
                "version": delete_version,
            }),
            format!("Deleted list '{}'", self.name),
        );
        output.set_extra(&LIST_DELETE_UNDO_SNAPSHOT, snapshot_json);
        Ok(output)
    }
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn delete_list(id: String) -> Result<DeleteListResult, String> {
    // shape-check the list id at the IPC boundary so a
    // trim-equivalent or malformed value can't reach the destructive
    // writer (which would surface as "List X not found" downstream
    // instead of an explicit shape rejection).
    // list-id contexts accept `INBOX_LIST_ID`; the
    // last-list invariant inside `delete_list_internal` still rejects
    // an attempt to delete the only list in the DB.
    let id = crate::commands::shared::validate_list_id(&id, "id")?;
    let conn = get_conn()?;
    let result = delete_list_internal(&conn, &id).map_err(String::from)?;
    Ok(result)
}

pub(crate) fn delete_list_internal(
    conn: &rusqlite::Connection,
    id: &str,
) -> AppResult<DeleteListResult> {
    let undo_snapshot_value = with_immediate_transaction(conn, |conn| {
        let list = fetch_list_by_id(conn, id)?
            .ok_or_else(|| AppError::NotFound(format!("List {id} not found")))?;
        let sync_delete_payload =
            lorvex_sync::outbox_enqueue::read_entity_payload_snapshot(conn, ENTITY_LIST, id)
                .map_err(AppError::from)?;

        // Prevent deleting the last list — at least one must exist for task creation.
        let total_lists: i64 = conn
            .query_row("SELECT COUNT(*) FROM lists", [], |row| row.get(0))
            .map_err(AppError::from)?;
        if total_lists <= 1 {
            return Err(AppError::Validation(
                "Cannot delete the last list. At least one list must exist for task creation."
                    .to_string(),
            ));
        }

        let id_typed = lorvex_domain::ListId::from_trusted(id.to_string());
        let assigned_task_count =
            lorvex_store::repositories::list_repo::count_assigned_tasks_in_list(conn, &id_typed)
                .map_err(AppError::from)?;
        if assigned_task_count > 0 {
            return Err(AppError::Validation(format!(
                "Cannot delete list '{}' while {} task(s) are still assigned. Reassign or permanently delete those tasks first.",
                list.name, assigned_task_count
            )));
        }

        let mutation = DeleteListMutation {
            id: &id_typed,
            name: &list.name,
        };

        let mut output = execute_ipc_entity_mutation(conn, &mutation, |conn, execution| {
            // Pull the delete version off the post-row payload so
            // the outbox tombstone shares the HLC stamp the row
            // UPDATE consumed. Tagged on the JSON shape that
            // `apply` builds — see `DeleteListMutation::apply`.
            let delete_version = execution
                .output
                .after
                .get("version")
                .and_then(Value::as_str)
                .ok_or_else(|| {
                    AppError::Internal("list delete output missing `version` field".to_string())
                })?;
            enqueue_list_delete_with_version(conn, id, &sync_delete_payload, delete_version)?;
            Ok(())
        })?;

        let snapshot_json = output
            .take_extra(&LIST_DELETE_UNDO_SNAPSHOT)
            .ok_or_else(|| {
                AppError::Internal(
                    "list delete completed without capturing undo snapshot".to_string(),
                )
            })?;
        Ok(snapshot_json)
    })?;

    let snapshot = serde_json::from_value(undo_snapshot_value).map_err(AppError::from)?;
    let undo_token = build_undo_token(snapshot)?;

    Ok(DeleteListResult {
        deleted_list_id: id.to_string(),
        undo_token,
    })
}
