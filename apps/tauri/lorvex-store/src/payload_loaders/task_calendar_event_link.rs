use lorvex_domain::{EventId, TaskId};
use rusqlite::{params, Connection, OptionalExtension, Row};
use serde_json::{json, Value};

use crate::error::StoreError;

pub const TASK_CALENDAR_EVENT_LINK_SELECT_COLUMNS: &str =
    "task_id, calendar_event_id, version, created_at, updated_at";

/// Primitive payload builder shared by the row-mapper and the
/// `DeletedTaskCalendarEventLinkSnapshot` tombstone path. See
/// `task_dependency_payload` for the same pattern.
pub fn task_calendar_event_link_payload(
    task_id: &TaskId,
    calendar_event_id: &EventId,
    version: &str,
    created_at: &str,
    updated_at: &str,
) -> Value {
    json!({
        "task_id": task_id,
        "calendar_event_id": calendar_event_id,
        "version": version,
        "created_at": created_at,
        "updated_at": updated_at,
    })
}

pub fn task_calendar_event_link_payload_from_row(row: &Row<'_>) -> rusqlite::Result<Value> {
    let task_id: TaskId = row.get(0)?;
    let calendar_event_id: EventId = row.get(1)?;
    let version: String = row.get(2)?;
    let created_at: String = row.get(3)?;
    let updated_at: String = row.get(4)?;
    Ok(task_calendar_event_link_payload(
        &task_id,
        &calendar_event_id,
        &version,
        &created_at,
        &updated_at,
    ))
}

pub fn load_task_calendar_event_link_sync_payload(
    conn: &Connection,
    task_id: &TaskId,
    calendar_event_id: &EventId,
) -> Result<Option<Value>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!(
            "SELECT {TASK_CALENDAR_EVENT_LINK_SELECT_COLUMNS} \
             FROM task_calendar_event_links \
             WHERE task_id = ?1 AND calendar_event_id = ?2"
        )
    });
    Ok(conn
        .query_row(
            sql,
            params![task_id, calendar_event_id],
            task_calendar_event_link_payload_from_row,
        )
        .optional()?)
}
