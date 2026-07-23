//! Upsert for the `preferences` key/value table.

use rusqlite::Connection;

use super::super::helpers::{
    invalid_payload, required_string_field, required_sync_timestamp_field, VersionedJsonlLine,
};
use super::{import_lww_upsert, LwwUpsertSpec, UpsertResult};
use crate::import::ImportError;

pub(in crate::import::apply::upserts) fn upsert_preference(
    conn: &Connection,
    entry: &VersionedJsonlLine,
) -> Result<UpsertResult, ImportError> {
    let p = &entry.payload;
    let key = required_string_field(p, "key", "preference payload")?;
    let version = entry.version.as_str();
    let value = p
        .get("value")
        .ok_or_else(|| invalid_payload("preference payload.value is required"))?;
    let value = serde_json::to_string(value).map_err(ImportError::from)?;
    let updated_at = required_sync_timestamp_field(p, "updated_at", "preference payload")?;

    import_lww_upsert(
        conn,
        &LwwUpsertSpec {
            table: "preferences",
            id_col: "key",
            id_val: &key,
            version,
            insert_sql:
                "INSERT INTO preferences (key, value, updated_at, version) VALUES (?1,?2,?3,?4)",
            update_sql: "UPDATE preferences SET value=?2, updated_at=?3, version=?4 WHERE key=?1",
        },
        rusqlite::params![key, value, updated_at, version],
    )
}
