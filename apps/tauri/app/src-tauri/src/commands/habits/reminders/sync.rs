use crate::commands::enqueue_to_outbox_typed;
use crate::error::{AppError, AppResult};
use lorvex_domain::naming::{ENTITY_HABIT_REMINDER_POLICY, OP_DELETE, OP_UPSERT};

use super::model::HabitReminderPolicy;

pub(super) fn enqueue_habit_reminder_policy_upsert(
    conn: &rusqlite::Connection,
    policy: &HabitReminderPolicy,
) -> AppResult<()> {
    let payload = serde_json::json!({
        "id": &policy.id,
        "habit_id": &policy.habit_id,
        "reminder_time": &policy.reminder_time,
        "enabled": policy.enabled,
        "created_at": &policy.created_at,
        "updated_at": &policy.updated_at,
    });
    enqueue_to_outbox_typed(
        conn,
        ENTITY_HABIT_REMINDER_POLICY,
        &policy.id,
        OP_UPSERT,
        &payload,
    )
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
/// typed delete for `habit_reminder_policies`. The
/// snapshot is loaded BEFORE the row is removed so peers can
/// reconstruct the policy state from the tombstone instead of
/// receiving a degenerate `{id}`-only envelope.
pub(super) fn enqueue_habit_reminder_policy_delete<T: serde::Serialize>(
    conn: &rusqlite::Connection,
    envelope: crate::commands::DeleteEnvelope<T>,
) -> AppResult<()> {
    let payload = serde_json::to_value(&envelope.snapshot).map_err(AppError::from)?;
    enqueue_to_outbox_typed(
        conn,
        ENTITY_HABIT_REMINDER_POLICY,
        &envelope.id,
        OP_DELETE,
        &payload,
    )
}

pub(super) fn load_habit_reminder_policy_pre_delete_snapshot(
    conn: &rusqlite::Connection,
    id: &str,
) -> AppResult<serde_json::Value> {
    use rusqlite::OptionalExtension;
    conn.query_row(
        "SELECT id, habit_id, reminder_time, enabled, created_at, updated_at
         FROM habit_reminder_policies
         WHERE id = ?1",
        rusqlite::params![id],
        |row| {
            Ok(serde_json::json!({
                "id": row.get::<_, String>(0)?,
                "habit_id": row.get::<_, String>(1)?,
                "reminder_time": row.get::<_, String>(2)?,
                "enabled": row.get::<_, i64>(3)? != 0,
                "created_at": row.get::<_, String>(4)?,
                "updated_at": row.get::<_, String>(5)?,
            }))
        },
    )
    .optional()
    .map_err(AppError::from)?
    .ok_or_else(|| {
        AppError::NotFound(format!(
            "habit reminder policy '{id}' not found for sync snapshot"
        ))
    })
}
