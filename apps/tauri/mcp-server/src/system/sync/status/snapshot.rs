use crate::error::McpError;
use rusqlite::Connection;

pub(crate) fn get_sync_status(conn: &Connection) -> Result<String, McpError> {
    let snapshot = lorvex_store::load_sync_status_snapshot(conn)?;
    Ok(serde_json::to_string_pretty(&snapshot)?)
}
