use lorvex_domain::{HabitId, HabitReminderPolicyId};
use rusqlite::Row;
use serde_json::{json, Value};

pub const HABIT_REMINDER_POLICY_SELECT_COLUMNS: &str =
    "id, habit_id, reminder_time, enabled, version, created_at, updated_at";

/// Primitive shared by the row-mapper and the
/// `DeletedHabitReminderPolicySnapshot` tombstone path.
/// `habit_reminder_policies.enabled` is registered in
/// `SQLITE_BOOL_COLUMNS`; emit a JSON boolean.
pub fn habit_reminder_policy_payload(
    id: &HabitReminderPolicyId,
    habit_id: &HabitId,
    reminder_time: &str,
    enabled: bool,
    version: &str,
    created_at: &str,
    updated_at: &str,
) -> Value {
    json!({
        "id": id,
        "habit_id": habit_id,
        "reminder_time": reminder_time,
        "enabled": enabled,
        "version": version,
        "created_at": created_at,
        "updated_at": updated_at,
    })
}

pub fn habit_reminder_policy_payload_from_row(row: &Row<'_>) -> rusqlite::Result<Value> {
    let id: HabitReminderPolicyId = row.get(0)?;
    let habit_id: HabitId = row.get(1)?;
    let reminder_time: String = row.get(2)?;
    let enabled: bool = row.get(3)?;
    let version: String = row.get(4)?;
    let created_at: String = row.get(5)?;
    let updated_at: String = row.get(6)?;
    Ok(habit_reminder_policy_payload(
        &id,
        &habit_id,
        &reminder_time,
        enabled,
        &version,
        &created_at,
        &updated_at,
    ))
}
