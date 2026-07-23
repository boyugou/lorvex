use crate::commands::shared;
use crate::commands::{sync_timestamp_now, with_immediate_transaction};
use crate::db::get_conn;
use crate::error::{AppError, AppResult};
use crate::event_bus;

pub(super) fn mark_habit_reminder_fired_with_conn(
    conn: &rusqlite::Connection,
    policy_id: &str,
    notified_at: &str,
) -> AppResult<()> {
    conn.execute(
        "INSERT INTO habit_reminder_delivery_state
         (policy_id, last_fired_at, updated_at)
         VALUES (?1, ?2, ?2)
         ON CONFLICT(policy_id) DO UPDATE SET
           last_fired_at = excluded.last_fired_at,
           updated_at = excluded.updated_at",
        rusqlite::params![policy_id, notified_at],
    )
    .map_err(AppError::from)?;
    Ok(())
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn mark_habit_reminder_fired(policy_id: String) -> Result<(), String> {
    // policy ids are UUIDv7 — shape-check before the
    // writer transaction so a malformed id can't reach the local
    // delivery-state table.
    //
    // This command intentionally does not emit an `ai_changelog` row.
    // Delivery state is device-local notification bookkeeping — a peer
    // device does not need to know that THIS device showed the reminder.
    // The `data_changed` emit below refreshes the local UI, but the
    // absence of a sync envelope here is by design, not an audit oversight.
    let policy_id = shared::validate_uuid_id(&policy_id, "policy_id")?;
    let result = (|| -> AppResult<()> {
        let conn = get_conn()?;
        let notified_at = sync_timestamp_now();
        with_immediate_transaction(&conn, |conn| {
            mark_habit_reminder_fired_with_conn(conn, &policy_id, &notified_at)
        })?;
        event_bus::emit_data_changed(event_bus::Entity::Habit);
        Ok(())
    })();

    result.map_err(String::from)
}
