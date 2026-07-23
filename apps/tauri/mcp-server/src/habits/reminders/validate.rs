//! Shared trust-boundary validation for the habit reminder writers.

use rusqlite::{Connection, OptionalExtension};

use crate::error::McpError;

/// validate `habit_id` references an existing habit at
/// the MCP trust boundary so the assistant gets a clean validation
/// error before any write work happens.
/// check lived deep in the store layer and surfaced as a generic
/// `StoreError::NotFound`, conflating "habit doesn't exist" with
/// "policy slot doesn't exist". Reject up-front with an actionable
/// Validation error.
pub(super) fn validate_habit_id_exists(conn: &Connection, habit_id: &str) -> Result<(), McpError> {
    let trimmed = habit_id.trim();
    if trimmed.is_empty() {
        return Err(McpError::Validation(
            "habit_id must not be empty".to_string(),
        ));
    }
    let exists: Option<String> = conn
        .query_row("SELECT id FROM habits WHERE id = ?1", [trimmed], |row| {
            row.get(0)
        })
        .optional()?;
    if exists.is_none() {
        return Err(McpError::Validation(format!(
            "habit_id '{trimmed}' does not reference an existing habit"
        )));
    }
    Ok(())
}
