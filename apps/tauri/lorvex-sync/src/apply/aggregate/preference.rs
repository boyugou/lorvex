//! Apply handlers for the `preference` aggregate (KV PK = `key`).
//!
//! Local-only preference keys (filesystem paths, per-device sync backend
//! choice, etc.) are filtered defensively at the apply boundary so even a
//! legacy peer that pushed one before the outbox filter landed cannot
//! overwrite the local value.

use rusqlite::{named_params, Connection};

use super::super::LwwTieBreak;
use super::helpers::required_str;
use super::ApplyError;

pub(crate) fn apply_preference_upsert(
    conn: &Connection,
    entity_id: &str,
    payload: &str,
    version: &str,
    allow_equal_versions: LwwTieBreak,
    // handler doesn't currently consume the apply
    // timestamp, but every aggregate-upsert signature carries it
    // for uniform dispatch — `_apply_ts` keeps the parameter shape
    // without the unused-variable warning.
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    if lorvex_domain::preference_keys::is_local_only_preference(entity_id) {
        return Ok(());
    }

    let val: serde_json::Value = serde_json::from_str(payload)?;

    let value = val.get("value").ok_or_else(|| {
        ApplyError::InvalidPayload("preference payload: value is required".to_string())
    })?;
    let value = serde_json::to_string(value)?;
    let updated_at = required_str(&val, "updated_at", "preference")?;

    // lifted the LWW upsert template into the shared
    // `LwwUpsertSpec` builder so the conflict / SET / version-compare
    // shape stays consistent with every other aggregate handler.
    static SQL_CACHE: std::sync::OnceLock<[String; 2]> = std::sync::OnceLock::new();
    let sql = crate::apply::LwwUpsertSpec {
        table: "preferences",
        columns: &["key", "value", "updated_at", "version"],
        conflict: &["key"],
        tie_break: allow_equal_versions,
    }
    .build_sql_cached(&SQL_CACHE);
    conn.prepare_cached(sql)?.execute(named_params! {
        ":key": entity_id,
        ":value": value,
        ":updated_at": updated_at,
        ":version": version,
    })?;
    Ok(())
}

/// defense-in-depth LWW guard. Mirrors the
/// `WHERE ?2 >= version` pattern used by every other aggregate-delete
/// handler (task, list, habit, calendar_event).
pub(crate) fn apply_preference_delete(
    conn: &Connection,
    entity_id: &str,
    version: &str,
    // see `apply_preference_upsert` for the rationale on the
    // `_apply_ts` rename.
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    if lorvex_domain::preference_keys::is_local_only_preference(entity_id) {
        return Ok(());
    }
    crate::apply::lww_gated_delete(conn, "preferences", &["key"], &[entity_id], version)?;
    Ok(())
}
