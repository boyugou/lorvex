//! `focus_schedule` aggregate payload builder.
//!
//! Header columns from `focus_schedule` plus the materialized
//! `blocks` collection rebuilt from `focus_schedule_blocks` via the
//! shared snapshot helper.

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{json, Value};

use lorvex_store::StoreError;

/// Header columns for date-keyed schedule aggregates: a fixed-arity tuple
/// alias to keep clippy::type_complexity quiet on the query result.
type ScheduleHeader = (String, Option<String>, Option<String>, String, String);

pub(super) fn build_focus_schedule_payload(
    conn: &Connection,
    date: &str,
) -> Result<Option<Value>, StoreError> {
    let header: Option<ScheduleHeader> = conn
        .query_row(
            "SELECT date, rationale, timezone, created_at, updated_at
             FROM focus_schedule WHERE date = ?1",
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

    let Some((date, rationale, timezone, created_at, updated_at)) = header else {
        return Ok(None);
    };

    let blocks = lorvex_store::focus_schedule_snapshot::serialize_blocks_for_sync(conn, &date)?;

    Ok(Some(json!({
        "date": date,
        "blocks": blocks,
        "rationale": rationale,
        "timezone": timezone,
        "created_at": created_at,
        "updated_at": updated_at,
    })))
}
