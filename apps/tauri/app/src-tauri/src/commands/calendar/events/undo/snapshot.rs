//! Pre-delete snapshot capture for calendar events and lists.
//!
//! Both helpers must be called BEFORE the row is deleted, while every
//! cascaded edge (calendar-event ↔ task links, attendees) is still
//! resident. The snapshot is the only source of truth at restore time —
//! anything missed here is lost.

use lorvex_domain::EventId;
use lorvex_store::repositories::task::calendar_links;

use crate::commands::fetch_list_by_id;
use crate::error::{AppError, AppResult};

use super::super::load_optional_calendar_event;
use super::token::EntitySnapshot;

/// Capture the snapshot needed to restore a calendar event delete.
///
/// Must be called BEFORE the SQLite cascade wipes the
/// `task_calendar_event_links` rows.
pub(in crate::commands::calendar::events) fn capture_calendar_event_snapshot(
    conn: &rusqlite::Connection,
    event_id: &str,
) -> AppResult<EntitySnapshot> {
    let event = load_optional_calendar_event(conn, event_id)
        .map_err(AppError::Internal)?
        .ok_or_else(|| AppError::NotFound(format!("Calendar event {event_id} not found")))?;
    let typed_event_id = EventId::from_trusted(event_id.to_string());
    let links =
        calendar_links::get_links_for_event(conn, &typed_event_id).map_err(AppError::from)?;
    let linked_task_ids = links
        .into_iter()
        .map(|l| l.task_id.as_str().to_string())
        .collect();
    Ok(EntitySnapshot::CalendarEvent {
        event: Box::new(event),
        linked_task_ids,
    })
}

/// Capture the snapshot needed to restore a list delete (#3420).
///
/// Must be called BEFORE the row is deleted. Lists hold no edges that
/// need replay (the assigned-task invariant blocks deletion of any
/// non-empty list), so the snapshot is just the row.
pub(crate) fn capture_list_snapshot(
    conn: &rusqlite::Connection,
    list_id: &str,
) -> AppResult<EntitySnapshot> {
    let list = fetch_list_by_id(conn, list_id)?
        .ok_or_else(|| AppError::NotFound(format!("List {list_id} not found")))?;
    Ok(EntitySnapshot::List { list })
}
