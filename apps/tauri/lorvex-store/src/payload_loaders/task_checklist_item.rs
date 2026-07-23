use rusqlite::{params, Connection, OptionalExtension, Row};
use serde_json::{json, Value};

use crate::error::StoreError;

pub const TASK_CHECKLIST_ITEM_SELECT_COLUMNS: &str =
    "id, task_id, position, text, completed_at, created_at, updated_at";

pub fn task_checklist_item_payload_from_row(row: &Row<'_>) -> rusqlite::Result<Value> {
    Ok(json!({
        "id": row.get::<_, String>(0)?,
        "task_id": row.get::<_, String>(1)?,
        "position": row.get::<_, i64>(2)?,
        "text": row.get::<_, String>(3)?,
        "completed_at": row.get::<_, Option<String>>(4)?,
        "created_at": row.get::<_, String>(5)?,
        "updated_at": row.get::<_, String>(6)?,
    }))
}

pub fn load_task_checklist_item_sync_payload(
    conn: &Connection,
    item_id: &lorvex_domain::ChecklistItemId,
) -> Result<Option<Value>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!(
            "SELECT {TASK_CHECKLIST_ITEM_SELECT_COLUMNS} FROM task_checklist_items WHERE id = ?1"
        )
    });
    Ok(conn
        .query_row(sql, params![item_id], task_checklist_item_payload_from_row)
        .optional()?)
}
