//! Preference repository — shared write operations for the `preferences` table.
//!
//! Used by both the Tauri app and the MCP server so the upsert/delete SQL
//! exists in exactly one place.

use rusqlite::{params, Connection};

use crate::error::StoreError;

/// Upsert a preference (INSERT ... ON CONFLICT DO UPDATE).
///
/// the UPDATE branch is gated by
/// `WHERE excluded.version > preferences.version` so a stale local
/// write cannot clobber a newer remote one in the sync-apply path.
/// Equal-version writes are no-ops by design — preference upserts
/// don't merge surplus fields the way tag/recurrence merges do, so
/// strict-greater is the correct semantics. Returns `Ok(true)` when
/// the row actually wrote (insert or version-newer update),
/// `Ok(false)` when the LWW gate rejected a stale write.
pub fn set_preference(
    conn: &Connection,
    key: &str,
    value: &str,
    version: &str,
    now: &str,
) -> Result<bool, StoreError> {
    let rows = conn
        .prepare_cached(
            "INSERT INTO preferences (key, value, version, updated_at) \
             VALUES (?1, ?2, ?3, ?4) \
             ON CONFLICT(key) DO UPDATE SET \
                value = excluded.value, version = excluded.version, updated_at = excluded.updated_at \
             WHERE excluded.version > preferences.version",
        )?
        .execute(params![key, value, version, now])?;
    Ok(rows > 0)
}

/// Delete a preference by key, gated by an LWW version comparison.
///
/// a blind DELETE let a stale local clear clobber a newer
/// remote `set_preference` write under cross-device races (device A
/// `set theme=dark` at v3 racing device B `clear theme` at v2). Mirrors
/// the pattern in [`set_preference`]: the caller passes the HLC stamp it
/// generated for the clear, and the DELETE proceeds only if that stamp
/// is strictly greater than the row's stored version.
///
/// Returns the number of rows actually deleted (0 or 1 — the
/// `preferences.key` primary key guarantees at most one match). A `0`
/// return covers both "key didn't exist" and "LWW gate rejected a
/// stale clear"; callers cannot distinguish these by design — both
/// are "no row to drop after this call" and the changelog/outbox
/// pipeline keys off `deleted > 0`.
///
/// standardized on `Result<usize, _>` to match every
/// other `delete_*` repository helper. Callers branching on the
/// boolean shape simply compare against `0`.
pub fn clear_preference(conn: &Connection, key: &str, version: &str) -> Result<usize, StoreError> {
    Ok(conn
        .prepare_cached("DELETE FROM preferences WHERE key = ?1 AND ?2 > version")?
        .execute(params![key, version])?)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests;
