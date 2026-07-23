use lorvex_workflow::habit_reminder_ops;

use crate::commands::shared;
use crate::commands::{sync_timestamp_now, with_immediate_transaction};
use crate::db::{get_conn, get_read_conn};
use crate::error::{AppError, AppResult};
use crate::event_bus;

use super::model::HabitReminderPolicy;
use super::sync::{
    enqueue_habit_reminder_policy_delete, enqueue_habit_reminder_policy_upsert,
    load_habit_reminder_policy_pre_delete_snapshot,
};

pub(super) fn upsert_habit_reminder_policy_with_conn(
    conn: &rusqlite::Connection,
    policy_id: Option<&str>,
    habit_id: &lorvex_domain::HabitId,
    reminder_time: &str,
    enabled: bool,
    now: &str,
) -> AppResult<HabitReminderPolicy> {
    let version = crate::hlc::generate_version_result()?;

    let row = habit_reminder_ops::upsert_habit_reminder_policy(
        conn,
        &habit_reminder_ops::UpsertHabitReminderPolicyParams {
            policy_id,
            habit_id: habit_id.as_str(),
            reminder_time,
            enabled,
            version: &version,
            now,
        },
    )?;

    let policy = HabitReminderPolicy::from(row);

    enqueue_habit_reminder_policy_upsert(conn, &policy)?;
    Ok(policy)
}

fn delete_habit_reminder_policy_with_conn(
    conn: &rusqlite::Connection,
    id: &str,
) -> AppResult<bool> {
    // Snapshot the row BEFORE the DELETE so the tombstone envelope
    // ships the full policy. NotFound is allowed — return early
    // without enqueuing a tombstone, matching the contract that a
    // no-op DELETE returns `false`.
    let snapshot = match load_habit_reminder_policy_pre_delete_snapshot(conn, id) {
        Ok(snapshot) => snapshot,
        Err(AppError::NotFound(_)) => return Ok(false),
        Err(other) => return Err(other),
    };
    let result = habit_reminder_ops::delete_habit_reminder_policy(conn, id)?;

    if !result.deleted {
        return Ok(false);
    }

    enqueue_habit_reminder_policy_delete(conn, crate::commands::DeleteEnvelope::new(id, snapshot))?;
    Ok(true)
}

#[tauri::command]
pub fn get_habit_reminder_policies() -> Result<Vec<HabitReminderPolicy>, String> {
    let result = (|| -> AppResult<Vec<HabitReminderPolicy>> {
        let conn = get_read_conn()?;
        let rows = habit_reminder_ops::list_all_policies(&conn)?;
        Ok(rows.into_iter().map(HabitReminderPolicy::from).collect())
    })();

    result.map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn upsert_habit_reminder_policy(
    id: Option<String>,
    habit_id: String,
    reminder_time: String,
    enabled: Option<bool>,
) -> Result<HabitReminderPolicy, String> {
    // validate UUID shape for the policy id (when
    // present, INSERT path uses caller-supplied id) and habit_id
    // before the writer transaction so a malformed value can't reach
    // the FK column.
    let id = match id {
        Some(raw) => Some(shared::validate_uuid_id(&raw, "id")?),
        None => None,
    };
    let habit_id_str = shared::validate_uuid_id(&habit_id, "habit_id")?;
    let habit_id = lorvex_domain::HabitId::from_trusted(habit_id_str);
    let conn = get_conn()?;
    let now = sync_timestamp_now();
    let policy = with_immediate_transaction(&conn, |conn| {
        upsert_habit_reminder_policy_with_conn(
            conn,
            id.as_deref(),
            &habit_id,
            &reminder_time,
            enabled.unwrap_or(true),
            &now,
        )
    })
    .map_err(String::from)?;
    event_bus::emit_data_changed(event_bus::Entity::Habit);
    Ok(policy)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn delete_habit_reminder_policy(id: String) -> Result<bool, String> {
    // shape-check the policy id (UUIDv7) at the IPC
    // boundary so a malformed value is rejected before the destructive
    // writer rather than silently returning `false` (no row deleted).
    let id = shared::validate_uuid_id(&id, "id")?;
    let conn = get_conn()?;
    let deleted = with_immediate_transaction(&conn, |conn| {
        delete_habit_reminder_policy_with_conn(conn, &id)
    })
    .map_err(String::from)?;

    if deleted {
        event_bus::emit_data_changed(event_bus::Entity::Habit);
    }

    Ok(deleted)
}
