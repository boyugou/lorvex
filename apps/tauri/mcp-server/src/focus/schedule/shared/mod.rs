use crate::error::McpError;
use lorvex_domain::parse_hhmm_to_minutes;
use rusqlite::Connection;
use serde_json::{json, Value};

/// Query focus_schedule_blocks for a given schedule_date and return them as a JSON array.
/// DB stores start_time/end_time as INTEGER (minute-of-day); output uses HH:MM strings.
///
/// Returns blocks WITHOUT stripping provider event_ids — used for the human-facing
/// MCP read APIs. The sync write path uses
/// [`lorvex_store::focus_schedule_snapshot::serialize_blocks_for_sync`] via the
/// canonical aggregate builder (see #2938).
pub(super) fn query_blocks_for_schedule(
    conn: &Connection,
    schedule_date: &str,
) -> Result<Vec<Value>, McpError> {
    let mut stmt = conn.prepare_cached(
        "SELECT b.block_type, b.start_time, b.end_time, b.task_id, b.event_id, b.title \
         FROM focus_schedule_blocks b WHERE b.schedule_date = ?1 ORDER BY b.position ASC",
    )?;
    let blocks = stmt
        .query_map([schedule_date], |row| {
            let block_type: String = row.get(0)?;
            let start_minutes: i64 = row.get(1)?;
            let end_minutes: i64 = row.get(2)?;
            let task_id: Option<String> = row.get(3)?;
            let event_id: Option<String> = row.get(4)?;
            let title: Option<String> = row.get(5)?;
            Ok(json!({
                "block_type": block_type,
                "start_time": start_minutes,
                "end_time": end_minutes,
                "task_id": task_id,
                "event_id": event_id,
                "title": title,
            }))
        })?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(blocks)
}

/// Materialize a blocks array into focus_schedule_blocks rows.
/// Deletes existing blocks for the schedule_date first, then inserts new ones.
/// Input blocks use HH:MM strings for start_time/end_time; stored as INTEGER (minute-of-day).
pub(super) fn materialize_blocks(
    conn: &Connection,
    schedule_date: &str,
    blocks: &[Value],
) -> Result<(), McpError> {
    let entries: Vec<lorvex_store::focus_schedule_blocks::ScheduleBlockEntry> = blocks
        .iter()
        .map(|block| {
            let block_type = block
                .get("block_type")
                .and_then(Value::as_str)
                .filter(|value| !value.trim().is_empty())
                .ok_or_else(|| {
                    McpError::Validation("focus schedule block_type is required".to_string())
                })?
                .to_string();
            let start_minutes = parse_block_minutes(block, "start_time")?;
            let end_minutes = parse_block_minutes(block, "end_time")?;
            if end_minutes <= start_minutes {
                return Err(McpError::Validation(format!(
                    "focus schedule block end_time must be later than start_time ({end_minutes} <= {start_minutes})"
                )));
            }
            let task_id = if block_type == "task" {
                block
                    .get("task_id")
                    .and_then(Value::as_str)
                    .filter(|s| !s.is_empty())
                    .map(String::from)
            } else {
                None
            };
            let event_id = block
                .get("event_id")
                .and_then(Value::as_str)
                .filter(|s| !s.is_empty())
                .map(String::from);
            let title = block.get("title").and_then(Value::as_str).map(String::from);
            Ok(
                lorvex_store::focus_schedule_blocks::ScheduleBlockEntry {
                    block_type,
                    start_minutes,
                    end_minutes,
                    task_id,
                    event_id,
                    title,
                },
            )
        })
        .collect::<Result<Vec<_>, McpError>>()?;

    lorvex_store::focus_schedule_blocks::materialize_schedule_blocks(conn, schedule_date, &entries)
        .map_err(|e| McpError::Internal(format!("Failed to materialize schedule blocks: {e}")))
}

fn parse_block_minutes(block: &Value, field: &str) -> Result<i64, McpError> {
    let value = block
        .get(field)
        .ok_or_else(|| McpError::Validation(format!("focus schedule {field} is required")))?;

    match value {
        Value::String(raw) => parse_hhmm_to_minutes(raw).ok_or_else(|| {
            McpError::Validation(format!(
                "focus schedule {field} must be HH:MM or integer minutes"
            ))
        }),
        Value::Number(raw) => raw
            .as_i64()
            .filter(|minutes| (0..=1440).contains(minutes))
            .ok_or_else(|| {
                McpError::Validation(format!(
                    "focus schedule {field} integer minutes must be between 0 and 1440"
                ))
            }),
        _ => Err(McpError::Validation(format!(
            "focus schedule {field} must be HH:MM or integer minutes"
        ))),
    }
}

/// Attach a derived blocks array from the sub-table to a focus_schedule row JSON.
pub(crate) fn normalize_focus_schedule_row(
    conn: &Connection,
    mut row: Value,
) -> Result<Value, McpError> {
    let schedule_date = row
        .get("date")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| McpError::Validation("focus schedule row missing date".to_string()))?;

    let blocks = query_blocks_for_schedule(conn, schedule_date)?;

    if let Value::Object(ref mut obj) = row {
        obj.insert("blocks".to_string(), Value::Array(blocks));
    }

    Ok(row)
}

#[cfg(test)]
mod tests;
