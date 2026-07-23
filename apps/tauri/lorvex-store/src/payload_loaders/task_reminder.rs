use rusqlite::{params, Connection, OptionalExtension, Row};
use serde_json::{json, Value};

use crate::error::StoreError;

pub const TASK_REMINDER_SELECT_COLUMNS: &str = "id, task_id, reminder_at, dismissed_at, \
    cancelled_at, created_at, original_local_time, original_tz";

pub fn task_reminder_payload_from_row(row: &Row<'_>) -> rusqlite::Result<Value> {
    Ok(json!({
        "id": row.get::<_, String>(0)?,
        "task_id": row.get::<_, String>(1)?,
        "reminder_at": row.get::<_, String>(2)?,
        "dismissed_at": row.get::<_, Option<String>>(3)?,
        "cancelled_at": row.get::<_, Option<String>>(4)?,
        "created_at": row.get::<_, String>(5)?,
        "original_local_time": row.get::<_, Option<String>>(6)?,
        "original_tz": row.get::<_, Option<String>>(7)?,
    }))
}

pub fn load_task_reminder_sync_payload(
    conn: &Connection,
    reminder_id: &lorvex_domain::ReminderId,
) -> Result<Option<Value>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!("SELECT {TASK_REMINDER_SELECT_COLUMNS} FROM task_reminders WHERE id = ?1")
    });
    Ok(conn
        .query_row(sql, params![reminder_id], task_reminder_payload_from_row)
        .optional()?)
}
