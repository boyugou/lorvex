//! Hard-delete path: the IPC `permanent_delete_task`, the inner
//! Spotlight + event-bus dispatcher, and the testable `_with_conn`
//! transactional body. Reserved for tasks already in the Trash
//! (i.e. `archived_at IS NOT NULL`); rejecting live tasks at this
//! gate prevents an IPC caller — or a stale UI that missed the
//! Trash affordance — from destroying data with no undo path.

use std::cell::RefCell;

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, OP_DELETE};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::{params, Connection};
use serde_json::Value;

use super::super::super::*;
use super::cascade::{cleanup_plan_refs_after_removal, enqueue_cascaded_task_child_deletes};
use crate::commands::enqueue_task_delete_with_version;
use crate::commands::shared::effects::execute_ipc_mutation_with_finalizer;

/// `Mutation` descriptor for the permanent-delete (Trash → gone)
/// transition.
///
/// `apply` runs the cascade cleanup, the LWW hard-delete via the
/// per-mutation [`HlcSession`] stamp, and stashes the pre-delete
/// snapshot + minted version so the surface finalizer can enqueue
/// the outbox tombstone with the same HLC.
struct PermanentDeleteTaskMutation<'a> {
    id: &'a str,
    /// Stashed by `apply` when the row was found and deleted; the
    /// surface finalizer reads this to emit the matching outbox
    /// tombstone with the same HLC stamp.
    enqueue: RefCell<Option<EnqueuePayload>>,
}

struct EnqueuePayload {
    before: Option<crate::commands::Task>,
    delete_version: String,
    deleted: bool,
}

impl<'a> Mutation for PermanentDeleteTaskMutation<'a> {
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
        let id = self.id;
        let before = conn
            .query_row(
                &format!("SELECT {TASK_COLS} FROM tasks WHERE id = ?1"),
                params![id],
                task_from_row,
            )
            .optional()?;

        // `permanent_delete_task` operates only on already-archived
        // tasks. The normal user-facing delete goes through
        // `archive_task` (soft-delete / Trash); hard-delete is
        // reserved for the Trash view's "Delete forever" button and
        // the `empty_trash` sweep. Rejecting a live task here prevents
        // an IPC caller (or a stale UI state that missed the trash
        // affordance) from permanently destroying data with no undo
        // path.
        if let Some(ref task) = before {
            if task.archived_at.is_none() {
                return Err(StoreError::Invariant(format!(
                    "Task '{id}' is not in the Trash — move it to the Trash first via archive_task"
                )));
            }
        }

        let now = lorvex_domain::sync_timestamp_now();

        let task_id_typed = lorvex_domain::TaskId::from_trusted(id.to_string());
        let affected_dependent_ids =
            cleanup_task_dependency_refs_after_removal(conn, &task_id_typed, &now).map_err(
                |err| match err {
                    AppError::Store(s) => *s,
                    other => StoreError::Invariant(other.to_string()),
                },
            )?;
        enqueue_affected_dependents(conn, &affected_dependent_ids).map_err(|err| match err {
            AppError::Store(s) => *s,
            other => StoreError::Invariant(other.to_string()),
        })?;
        cleanup_plan_refs_after_removal(conn, id).map_err(|err| match err {
            AppError::Store(s) => *s,
            other => StoreError::Invariant(other.to_string()),
        })?;
        enqueue_cascaded_task_child_deletes(conn, id, &now).map_err(|err| match err {
            AppError::Store(s) => *s,
            other => StoreError::Invariant(other.to_string()),
        })?;

        let delete_version = hlc.next_version_string();
        let affected = lorvex_store::repositories::task::write::hard_delete_task_lww(
            conn,
            &lorvex_domain::TaskId::from_trusted(id.to_string()),
            &delete_version,
        )?;

        let deleted = affected > 0;
        let summary = if deleted {
            format!("Permanently deleted task '{id}'")
        } else {
            format!("Permanent delete no-op for task '{id}'")
        };
        let after = serde_json::json!({ "id": id, "deleted": deleted });

        *self.enqueue.borrow_mut() = Some(EnqueuePayload {
            before,
            delete_version,
            deleted,
        });

        Ok(MutationOutput::new(after, summary))
    }
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn permanent_delete_task(id: String) -> Result<(), String> {
    // task ids are UUIDv7 — shape-check at the IPC
    // boundary so a malformed id can't reach the hard-delete writer.
    let id = crate::commands::shared::validate_uuid_id(&id, "id")?;
    permanent_delete_task_inner(id).map_err(String::from)
}

fn permanent_delete_task_inner(id: String) -> Result<(), AppError> {
    let conn = get_conn()?;
    let deleted = permanent_delete_task_with_conn(&conn, &id)?;

    // event_bus emit is handled by the executor.

    // Post-commit: remove permanently deleted task from Spotlight index.
    if deleted {
        crate::platform::spotlight::apply_actions(
            &conn,
            &[crate::platform::spotlight::SpotlightAction::RemoveTaskIds(
                vec![id],
            )],
        );
    }
    Ok(())
}

/// Transactional body of `permanent_delete_task` against a
/// caller-supplied connection. Returns whether a row was actually
/// deleted, which the outer wrapper uses to gate the Spotlight removal.
pub(crate) fn permanent_delete_task_with_conn(
    conn: &rusqlite::Connection,
    id: &str,
) -> Result<bool, AppError> {
    with_immediate_transaction(conn, |conn| {
        let mutation = PermanentDeleteTaskMutation {
            id,
            enqueue: RefCell::new(None),
        };
        let mut deleted = false;
        execute_ipc_mutation_with_finalizer(conn, &mutation, |conn, _execution| {
            let payload = mutation
                .enqueue
                .borrow_mut()
                .take()
                .expect("permanent-delete mutation must populate enqueue payload");
            deleted = payload.deleted;
            if payload.deleted {
                enqueue_task_delete_with_version(
                    conn,
                    id,
                    payload.before.as_ref(),
                    &payload.delete_version,
                )?;
            }
            Ok(())
        })?;
        Ok(deleted)
    })
}
