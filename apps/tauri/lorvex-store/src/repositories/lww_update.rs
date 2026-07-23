//! Shared helper for LWW-gated UPDATE statements that need to translate
//! a "zero rows changed" outcome into [`StoreError::StaleVersion`].
//!
//! Every entity that maintains an LWW-style `version` column writes the
//! same shape:
//!
//! ```sql
//! UPDATE <table> SET … WHERE id = :id AND :version > version
//! ```
//!
//! When the gate rejects the write, raw `execute()` returns `0` and
//! every caller has to repeat the same `if rows == 0 { return
//! Err(StaleVersion) }` boilerplate. Leaking the `usize` shape into
//! the high-level surfaces (Tauri / MCP / CLI) makes them
//! re-implement the check too, sometimes with subtly different error
//! messages.
//!
//! This helper internalizes the translation by appending `RETURNING 1`
//! to the SQL and using `query_row`. SQLite returns `QueryReturnedNoRows`
//! when the LWW gate filters every candidate row, which we map to
//! [`StoreError::StaleVersion`]. The boundary layers consume the typed
//! error directly via the existing `McpError::Store(StaleVersion)` →
//! `ErrorKind::SyncConflict` mapping (mcp-server) or
//! `AppError::from(StoreError)` → IPC error (Tauri).

use rusqlite::{Connection, Params};

use crate::error::StoreError;

/// Run a LWW-gated `UPDATE … RETURNING 1` and translate the
/// `QueryReturnedNoRows` outcome into [`StoreError::StaleVersion`].
///
/// The caller is responsible for appending `RETURNING 1` to the SQL —
/// keeping the SQL fragment in the caller's hand lets each repository
/// keep its existing dynamic SET-clause builder unchanged. The helper's
/// only job is the prepare-cached + query_row + NoRows-translation
/// dance.
///
/// `entity` and `id` populate the [`StoreError::StaleVersion`] payload
/// so the boundary layers can quote the offending row when they map
/// the error onto the wire.
pub(crate) fn execute_lww_update<P: Params>(
    conn: &Connection,
    sql: &str,
    params: P,
    entity: &'static str,
    id: &str,
) -> Result<(), StoreError> {
    match conn.prepare_cached(sql)?.query_row(params, |_row| Ok(())) {
        Ok(()) => Ok(()),
        Err(rusqlite::Error::QueryReturnedNoRows) => Err(StoreError::StaleVersion {
            entity,
            id: id.to_string(),
        }),
        Err(e) => Err(e.into()),
    }
}
