use crate::error::McpError;
use rusqlite::Connection;
use serde_json::Value;

/// Query task_ids from the current_focus_items sub-table for a given date,
/// returning them in position order.
pub(crate) fn query_focus_task_ids(conn: &Connection, date: &str) -> Result<Vec<String>, McpError> {
    lorvex_store::current_focus_items::query_focus_task_ids(conn, date)
        .map_err(|e| McpError::Internal(format!("Failed to query focus task ids: {e}")))
}

/// Enrich a current_focus row (from SELECT *) with a derived task_ids array
/// fetched from the current_focus_items sub-table.
pub(crate) fn enrich_current_focus_row(
    conn: &Connection,
    mut row: Value,
) -> Result<Value, McpError> {
    let Value::Object(ref mut object) = row else {
        return Ok(row);
    };
    let date = object
        .get("date")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| McpError::Validation("current_focus row missing date".to_string()))?;
    let task_ids = query_focus_task_ids(conn, date)?;
    object.insert(
        "task_ids".to_string(),
        Value::Array(task_ids.into_iter().map(Value::String).collect()),
    );
    Ok(row)
}

#[cfg(test)]
mod tests;
