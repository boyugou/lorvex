//! `current_focus` aggregate payload builder.
//!
//! Header columns from `current_focus` plus the materialized
//! `task_ids` collection rebuilt from `current_focus_items`.

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{json, Value};

use lorvex_store::StoreError;

/// Header columns for date-keyed schedule aggregates: a fixed-arity tuple
/// alias to keep clippy::type_complexity quiet on the query result.
type ScheduleHeader = (String, Option<String>, Option<String>, String, String);

pub(super) fn build_current_focus_payload(
    conn: &Connection,
    date: &str,
) -> Result<Option<Value>, StoreError> {
    let header: Option<ScheduleHeader> = conn
        .query_row(
            "SELECT date, briefing, timezone, created_at, updated_at
             FROM current_focus WHERE date = ?1",
            params![date],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                ))
            },
        )
        .optional()?;

    let Some((date, briefing, timezone, created_at, updated_at)) = header else {
        return Ok(None);
    };

    let task_ids = lorvex_store::current_focus_items::query_focus_task_ids(conn, &date)?;

    Ok(Some(json!({
        "date": date,
        "task_ids": task_ids,
        "briefing": briefing,
        "timezone": timezone,
        "created_at": created_at,
        "updated_at": updated_at,
    })))
}
