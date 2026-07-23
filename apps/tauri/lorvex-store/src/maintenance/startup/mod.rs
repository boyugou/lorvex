//! Shared storage-layer startup maintenance.
//!
//! These passes keep SQLite-backed local storage healthy without depending on
//! app, MCP, CLI, or sync runtime code. They are deliberately best-effort at
//! call sites, but the functions return typed errors so callers can log the
//! exact failing sweep.

use rusqlite::Connection;

use crate::{error::StoreError, error_log};

/// Scan preference rows whose values are not valid JSON and surface one
/// diagnostic row per corrupt key.
pub fn run_startup_preferences_integrity(conn: &Connection) -> Result<u64, StoreError> {
    let bad_keys = {
        let mut stmt = conn.prepare("SELECT key FROM preferences WHERE json_valid(value) = 0")?;
        let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
        rows.collect::<Result<Vec<_>, rusqlite::Error>>()?
    };

    for key in &bad_keys {
        let message = format!(
            "preference '{key}' has a stored value that is not valid JSON; \
             frontend parsers fall back to their default silently. \
             Re-set the preference from Settings to clear the corruption."
        );
        error_log::append_error_log_best_effort(
            conn,
            "preferences.corruption",
            &message,
            None,
            Some("warn"),
        );
    }

    Ok(bad_keys.len() as u64)
}

#[cfg(test)]
mod tests;
