//! thin CLI read of the `error_logs` table — the
//! single-source slice of the MCP `get_recent_logs` tool that callers
//! most often want from a shell pipeline. Returns rows in
//! reverse-chronological order so the most recent failure is first.
//!
//! This is intentionally a strict subset of the MCP tool; the full
//! `get_recent_logs` (which merges error_logs, ai_changelog and
//! sync_outbox with redaction policy) is tracked separately.

use rusqlite::Connection;

use crate::error::CliError;

#[derive(Debug, Clone, serde::Serialize)]
pub(crate) struct ErrorLogRow {
    pub(crate) id: String,
    pub(crate) source: String,
    pub(crate) level: String,
    pub(crate) message: String,
    pub(crate) details: Option<String>,
    pub(crate) created_at: String,
}

pub(crate) fn list_recent_error_logs_with_conn(
    conn: &Connection,
    limit: u32,
    source_filter: Option<&str>,
) -> Result<Vec<ErrorLogRow>, CliError> {
    let mut sql = String::from(
        "SELECT id, source, level, message, details, created_at \
         FROM error_logs",
    );
    let mut params: Vec<Box<dyn rusqlite::ToSql>> = Vec::new();
    if let Some(src) = source_filter {
        sql.push_str(" WHERE source = ?1");
        params.push(Box::new(src.to_string()));
    }
    sql.push_str(" ORDER BY created_at DESC, id DESC LIMIT ?");
    sql.push_str(&(params.len() + 1).to_string());
    params.push(Box::new(i64::from(limit)));

    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt
        .query_map(
            rusqlite::params_from_iter(params.iter().map(std::convert::AsRef::as_ref)),
            |row| {
                Ok(ErrorLogRow {
                    id: row.get(0)?,
                    source: row.get(1)?,
                    level: row.get(2)?,
                    message: row.get(3)?,
                    details: row.get(4)?,
                    created_at: row.get(5)?,
                })
            },
        )?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(rows)
}
