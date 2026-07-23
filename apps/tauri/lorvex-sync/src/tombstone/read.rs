//! Read-side tombstone helpers — single-row lookup and existence checks.

use rusqlite::{params, Connection};

use super::Tombstone;

/// Look up a tombstone for an entity.
///
/// Returns `None` if the entity is not tombstoned.
pub fn get_tombstone(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
) -> Result<Option<Tombstone>, rusqlite::Error> {
    // this is the most-prepared statement in the apply
    // pipeline (called per envelope and again per redirect-chase hop).
    // Route through `prepare_cached` so the connection's statement
    // cache amortizes preparation across the per-envelope hop loop.
    let mut stmt = conn.prepare_cached(
        "SELECT entity_type, entity_id, version, deleted_at,
                redirect_entity_id, redirect_entity_type
         FROM sync_tombstones
         WHERE entity_type = ?1 AND entity_id = ?2",
    )?;

    let mut rows = stmt.query_map(params![entity_type, entity_id], |row| {
        Ok(Tombstone {
            entity_type: row.get(0)?,
            entity_id: row.get(1)?,
            version: row.get(2)?,
            deleted_at: row.get(3)?,
            redirect_entity_id: row.get(4)?,
            redirect_entity_type: row.get(5)?,
        })
    })?;

    match rows.next() {
        Some(result) => Ok(Some(result?)),
        None => Ok(None),
    }
}

/// Check if an entity is tombstoned.
///
/// This is a lightweight check that avoids deserializing the full
/// tombstone row. Used only by in-crate tests today; gated behind
/// `cfg(test)` so the production lib doesn't carry the helper —
/// if a future production caller needs it, lift the gate
/// explicitly.
#[cfg(test)]
pub(crate) fn is_tombstoned(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
) -> Result<bool, rusqlite::Error> {
    let count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM sync_tombstones
         WHERE entity_type = ?1 AND entity_id = ?2",
        params![entity_type, entity_id],
        |row| row.get(0),
    )?;
    Ok(count > 0)
}
