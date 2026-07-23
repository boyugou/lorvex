//! Tauri command boundary for snapshot-based undo.
//!
//! Validates the token, dispatches to the per-entity restore helpers
//! inside an immediate transaction, and emits the matching `event_bus`
//! invalidation so the UI refreshes the right view after the restore.

use crate::commands::sync_timestamp_now;
use crate::commands::with_immediate_transaction;
use crate::db::get_conn;
use crate::error::{AppError, AppResult};
use crate::event_bus;

use super::restore_event::restore_calendar_event;
use super::restore_list::restore_list;
use super::token::{parse_and_validate_token, EntitySnapshot};

/// Discriminator emitted alongside the restored row so the Tauri
/// command can dispatch the right `event_bus` invalidation. The
/// `EntitySnapshot` enum is serialized to the frontend opaquely; this
/// kind is consumed only inside the Rust command boundary.
#[derive(Debug)]
pub(crate) enum RestoredEntity {
    CalendarEvent(serde_json::Value),
    List(serde_json::Value),
}

pub(crate) fn undo_delete_entity_internal(
    conn: &rusqlite::Connection,
    token_str: &str,
    now: &str,
) -> AppResult<RestoredEntity> {
    let token = parse_and_validate_token(token_str)?;
    let result = with_immediate_transaction(conn, |conn| match token.snapshot {
        EntitySnapshot::CalendarEvent {
            event,
            linked_task_ids,
        } => {
            let restored = restore_calendar_event(conn, &event, &linked_task_ids, now)?;
            Ok(RestoredEntity::CalendarEvent(
                serde_json::to_value(&restored).map_err(AppError::from)?,
            ))
        }
        EntitySnapshot::List { list } => {
            let restored = restore_list(conn, &list, now)?;
            Ok(RestoredEntity::List(
                serde_json::to_value(&restored).map_err(AppError::from)?,
            ))
        }
    })?;
    Ok(result)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn undo_delete_entity(token: String) -> Result<serde_json::Value, String> {
    let conn = get_conn()?;
    let now = sync_timestamp_now();
    let restored = undo_delete_entity_internal(&conn, &token, &now).map_err(String::from)?;
    match restored {
        RestoredEntity::CalendarEvent(v) => {
            event_bus::emit_data_changed(event_bus::Entity::CalendarEvent);
            Ok(v)
        }
        RestoredEntity::List(v) => {
            event_bus::emit_data_changed(event_bus::Entity::List);
            Ok(v)
        }
    }
}
