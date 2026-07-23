use super::*;

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK_REMINDER, OP_DELETE};
use lorvex_domain::{ReminderId, TaskId};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use serde_json::Value;

use crate::commands::shared::effects::execute_ipc_entity_mutation;

/// Descriptor for the DELETE on `task_reminders`. The pre-delete
/// snapshot is loaded by the surrounding command body and surfaced
/// through the finalizer so the typed `DeleteEnvelope` carries the
/// full reminder shape peers need to mint their own `before_json`.
struct RemoveTaskReminderMutation<'a> {
    task_id: &'a TaskId,
    reminder_id: &'a ReminderId,
}

impl<'a> Mutation for RemoveTaskReminderMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK_REMINDER
    }
    fn operation(&self) -> &'static str {
        OP_DELETE
    }

    fn pre_snapshot(&self, _conn: &rusqlite::Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }

    fn apply(
        &self,
        conn: &rusqlite::Connection,
        hlc: &HlcSession<'_>,
    ) -> Result<MutationOutput, StoreError> {
        // Stamp a session-bound version so the executor's HLC session
        // accounts for this DELETE (the tombstone envelope itself
        // carries the pre-delete version + payload, not this stamp).
        let _ = hlc.next_version_string();
        let rows_affected = conn.execute(
            "DELETE FROM task_reminders WHERE id = ?1 AND task_id = ?2",
            params![self.reminder_id.as_str(), self.task_id.as_str()],
        )?;
        if rows_affected == 0 {
            return Err(StoreError::NotFound {
                entity: ENTITY_TASK_REMINDER,
                id: self.reminder_id.as_str().to_string(),
            });
        }
        Ok(MutationOutput::new(
            serde_json::json!({
                "id": self.reminder_id.as_str(),
                "task_id": self.task_id.as_str(),
            }),
            format!(
                "Removed reminder {} from task {}",
                self.reminder_id, self.task_id
            ),
        ))
    }
}

/// Remove a specific reminder by task ID and reminder ID.
pub(super) fn remove_task_reminder_with_conn(
    conn: &rusqlite::Connection,
    task_id: &TaskId,
    reminder_id: &ReminderId,
) -> AppResult<()> {
    fetch_task_by_id(conn, task_id.as_str()).map(|_| ())?;
    // load the pre-delete snapshot BEFORE issuing the
    // DELETE so the typed `DeleteEnvelope` carries the full reminder
    // state. A peer that GC'd its local copy can reconstruct the row
    // for its own `before_json` audit row from this envelope.
    let snapshot =
        crate::commands::load_task_reminder_pre_delete_snapshot(conn, reminder_id.as_str())?;

    let mutation = RemoveTaskReminderMutation {
        task_id,
        reminder_id,
    };
    execute_ipc_entity_mutation(conn, &mutation, |conn, _execution| {
        enqueue_task_reminder_delete(
            conn,
            crate::commands::DeleteEnvelope::new(reminder_id.as_str(), snapshot.clone()),
        )?;
        Ok(())
    })
    .map_err(|err| match err {
        AppError::Store(boxed) => match *boxed {
            StoreError::NotFound { id, .. } => {
                AppError::NotFound(format!("Reminder {id} not found for task {task_id}"))
            }
            other => AppError::Store(Box::new(other)),
        },
        other => other,
    })?;
    Ok(())
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
fn remove_task_reminder_inner(task_id: TaskId, reminder_id: ReminderId) -> AppResult<()> {
    let conn = get_conn()?;
    // event_bus emit is handled inside the
    // `execute_ipc_entity_mutation` finalizer for the reminder DELETE.
    remove_task_reminder_in_transaction(&conn, &task_id, &reminder_id)
}

fn remove_task_reminder_in_transaction(
    conn: &rusqlite::Connection,
    task_id: &TaskId,
    reminder_id: &ReminderId,
) -> AppResult<()> {
    with_immediate_transaction(conn, |conn| {
        remove_task_reminder_with_conn(conn, task_id, reminder_id)
    })
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn remove_task_reminder(task_id: String, reminder_id: String) -> Result<(), String> {
    // both ids are UUIDv7 — shape-check at the IPC
    // boundary before the destructive writer.
    let task_id_str = crate::commands::shared::validate_uuid_id(&task_id, "task_id")?;
    let reminder_id_str = crate::commands::shared::validate_uuid_id(&reminder_id, "reminder_id")?;
    remove_task_reminder_inner(
        TaskId::from_trusted(task_id_str),
        ReminderId::from_trusted(reminder_id_str),
    )
    .map_err(String::from)
}
