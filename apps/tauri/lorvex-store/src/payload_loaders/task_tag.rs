use lorvex_domain::{TagId, TaskId};
use rusqlite::{params, Connection, OptionalExtension, Row};
use serde_json::{json, Value};

use crate::error::StoreError;

pub const TASK_TAG_SELECT_COLUMNS: &str = "task_id, tag_id, version, created_at";

/// Primitive shared by the row-mapper and the cascade-snapshot path
/// in `lorvex_sync::startup_trash_purge::snapshots` so the upsert
/// (row → payload) and tombstone (cascade snapshot → payload) shapes
/// stay in lock-step.
pub fn task_tag_payload(
    task_id: &TaskId,
    tag_id: &TagId,
    version: &str,
    created_at: &str,
) -> Value {
    json!({
        "task_id": task_id,
        "tag_id": tag_id,
        "version": version,
        "created_at": created_at,
    })
}

pub fn task_tag_payload_from_row(row: &Row<'_>) -> rusqlite::Result<Value> {
    let task_id: TaskId = row.get(0)?;
    let tag_id: TagId = row.get(1)?;
    let version: String = row.get(2)?;
    let created_at: String = row.get(3)?;
    Ok(task_tag_payload(&task_id, &tag_id, &version, &created_at))
}

pub fn load_task_tag_sync_payload(
    conn: &Connection,
    task_id: &TaskId,
    tag_id: &TagId,
) -> Result<Option<Value>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!(
            "SELECT {TASK_TAG_SELECT_COLUMNS} FROM task_tags WHERE task_id = ?1 AND tag_id = ?2"
        )
    });
    Ok(conn
        .query_row(sql, params![task_id, tag_id], task_tag_payload_from_row)
        .optional()?)
}
