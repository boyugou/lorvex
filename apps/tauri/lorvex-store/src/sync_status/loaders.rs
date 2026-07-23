//! Thin DB-access helpers for the sync-status snapshot loader.
//! Isolated so the orchestrator in [`super::snapshot`] threads
//! checkpoint/preference reads through a single `prepare_cached`
//! statement each, regardless of how many keys it queries.

use rusqlite::{params, Connection, OptionalExtension};

use crate::StoreError;

pub(super) fn load_sync_checkpoint_value(
    conn: &Connection,
    key: &str,
) -> Result<Option<String>, StoreError> {
    lorvex_runtime::sync_checkpoint_get(conn, key).map_err(StoreError::from)
}

pub(super) fn load_preference_value(
    conn: &Connection,
    key: &str,
) -> Result<Option<String>, StoreError> {
    conn.prepare_cached("SELECT value FROM preferences WHERE key = ?1")
        .map_err(StoreError::from)?
        .query_row(params![key], |row| row.get(0))
        .optional()
        .map_err(StoreError::from)
}
