use rusqlite::{params, Connection, OptionalExtension, Row};
use serde_json::{json, Value};

use crate::error::StoreError;

// ---------------------------------------------------------------------------
// preference (upsert payload — no `version`; matches the runtime
// `enqueue_preference_upsert` shape, which the apply path expects)
// ---------------------------------------------------------------------------

pub const PREFERENCE_UPSERT_SELECT_COLUMNS: &str = "key, value, updated_at";

/// Build a preference upsert payload from the column triple. The
/// `value` column is a JSON-encoded `TEXT`; this helper parses it
/// (callers downstream of the writer have already canonicalised the
/// JSON, so a parse failure is a hard data-corruption signal).
pub fn preference_upsert_payload(
    key: &str,
    value_raw: &str,
    updated_at: &str,
) -> Result<Value, StoreError> {
    let parsed: Value = serde_json::from_str(value_raw).map_err(|error| {
        StoreError::Serialization(format!(
            "preference '{key}' must be canonical JSON: {error}"
        ))
    })?;
    Ok(json!({
        "key": key,
        "value": parsed,
        "updated_at": updated_at,
    }))
}

pub fn load_preference_sync_payload(
    conn: &Connection,
    key: &str,
) -> Result<Option<Value>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!("SELECT {PREFERENCE_UPSERT_SELECT_COLUMNS} FROM preferences WHERE key = ?1")
    });
    let row = conn
        .query_row(sql, params![key], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
            ))
        })
        .optional()?;
    row.map(|(key, value_raw, updated_at)| preference_upsert_payload(&key, &value_raw, &updated_at))
        .transpose()
}

// ---------------------------------------------------------------------------
// preference (pre-delete snapshot — carries `version`; matches the
// runtime `load_preference_pre_delete_snapshot` shape)
// ---------------------------------------------------------------------------

const PREFERENCE_DELETE_SELECT_COLUMNS: &str = "key, value, version, updated_at";

fn preference_delete_snapshot_from_row(row: &Row<'_>) -> rusqlite::Result<Value> {
    Ok(json!({
        "key": row.get::<_, String>(0)?,
        "value": row.get::<_, Option<String>>(1)?,
        "version": row.get::<_, String>(2)?,
        "updated_at": row.get::<_, String>(3)?,
    }))
}

pub fn load_preference_delete_snapshot(
    conn: &Connection,
    key: &str,
) -> Result<Option<Value>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!("SELECT {PREFERENCE_DELETE_SELECT_COLUMNS} FROM preferences WHERE key = ?1")
    });
    Ok(conn
        .query_row(sql, params![key], preference_delete_snapshot_from_row)
        .optional()?)
}
