use rusqlite::{params, Connection, OptionalExtension, Row};
use serde_json::{json, Value};

use crate::error::StoreError;

pub const MEMORY_SELECT_COLUMNS: &str = "key, content, version, updated_at";

/// Primitive shared by the row-mapper and any in-memory writer that
/// already has the four fields in hand and would otherwise hand-roll
/// the same JSON shape.
pub fn memory_payload(key: &str, content: &str, version: &str, updated_at: &str) -> Value {
    json!({
        "key": key,
        "content": content,
        "version": version,
        "updated_at": updated_at,
    })
}

pub fn memory_payload_from_row(row: &Row<'_>) -> rusqlite::Result<Value> {
    let key: String = row.get(0)?;
    let content: String = row.get(1)?;
    let version: String = row.get(2)?;
    let updated_at: String = row.get(3)?;
    Ok(memory_payload(&key, &content, &version, &updated_at))
}

/// Load the sync payload for a single `memories` row. Returns
/// `Ok(None)` if the row has been deleted.
pub fn load_memory_sync_payload(conn: &Connection, key: &str) -> Result<Option<Value>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql =
        SQL.get_or_init(|| format!("SELECT {MEMORY_SELECT_COLUMNS} FROM memories WHERE key = ?1"));
    Ok(conn
        .query_row(sql, params![key], memory_payload_from_row)
        .optional()?)
}

/// Load the pre-delete tombstone payload for a memory row.
///
/// This intentionally reuses the normal memory sync payload shape so
/// delete envelopes carry the same diagnostic fields as upserts:
/// `key`, `content`, `version`, and `updated_at`.
pub fn load_memory_delete_snapshot(
    conn: &Connection,
    key: &str,
) -> Result<Option<Value>, StoreError> {
    load_memory_sync_payload(conn, key)
}
