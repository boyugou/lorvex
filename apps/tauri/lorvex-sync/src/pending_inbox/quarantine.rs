//! Poison-envelope quarantine blocklist helpers.

use rusqlite::{params, Connection};

/// Whether `(entity_type, entity_id, version)` is on the poison-envelope
/// blocklist.
pub(super) fn is_quarantined(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    version: &str,
) -> Result<bool, rusqlite::Error> {
    let mut stmt = conn.prepare_cached(
        "SELECT 1 FROM sync_quarantine_blocklist \
         WHERE entity_type = ?1 AND entity_id = ?2 AND version = ?3 \
         LIMIT 1",
    )?;
    let mut rows = stmt.query(params![entity_type, entity_id, version])?;
    Ok(rows.next()?.is_some())
}

/// Record `(entity_type, entity_id, version)` on the poison-envelope blocklist.
///
/// First write wins: under a redelivery storm the same poisoned identity may
/// land here many times, and the original `quarantined_at` is the
/// diagnostically valuable one. `DO NOTHING` preserves that first-observed
/// timestamp instead of advancing it on every redelivery (#3307 T2-6). The
/// per-cause diagnostic string lives in the sibling `sync_conflict_log` row
/// each caller writes alongside this blocklist entry.
pub(super) fn record_quarantine(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    version: &str,
) -> Result<(), rusqlite::Error> {
    conn.execute(
        "INSERT INTO sync_quarantine_blocklist
            (entity_type, entity_id, version, quarantined_at)
         VALUES (?1, ?2, ?3, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
         ON CONFLICT(entity_type, entity_id, version) DO NOTHING",
        params![entity_type, entity_id, version],
    )?;
    Ok(())
}
