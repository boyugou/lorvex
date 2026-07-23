use rusqlite::{params, Connection, OptionalExtension, Row};
use serde_json::{json, Value};

use crate::error::StoreError;

pub const TAG_SELECT_COLUMNS: &str =
    "id, display_name, lookup_key, color, created_at, updated_at, version";

pub fn tag_payload_from_row(row: &Row<'_>) -> rusqlite::Result<Value> {
    Ok(json!({
        "id": row.get::<_, String>(0)?,
        "display_name": row.get::<_, String>(1)?,
        "lookup_key": row.get::<_, String>(2)?,
        "color": row.get::<_, Option<String>>(3)?,
        "created_at": row.get::<_, String>(4)?,
        "updated_at": row.get::<_, String>(5)?,
        // `version` is `Option<String>` to defensively absorb a row
        // that pre-dates the column add (legacy DBs only). The current
        // schema declares `version TEXT NOT NULL`.
        "version": row.get::<_, Option<String>>(6)?,
    }))
}

pub fn load_tag_sync_payload(
    conn: &Connection,
    tag_id: &lorvex_domain::TagId,
) -> Result<Option<Value>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| format!("SELECT {TAG_SELECT_COLUMNS} FROM tags WHERE id = ?1"));
    Ok(conn
        .query_row(sql, params![tag_id], tag_payload_from_row)
        .optional()?)
}
