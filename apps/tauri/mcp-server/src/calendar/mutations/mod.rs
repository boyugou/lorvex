use crate::contract::{
    AttendeeInput, BatchCreateCalendarEventsArgs, CreateCalendarEventArgs, DeleteCalendarEventArgs,
    UpdateCalendarEventArgs,
};
use crate::error::McpError;
use crate::system::handler_support::{new_uuid, plural_s};
use lorvex_domain::naming::{ENTITY_CALENDAR_EVENT, OP_DELETE};
use lorvex_workflow::calendar_normalization::CalendarDstGuard;
use rusqlite::Connection;
use serde_json::{json, Value};

mod create;
mod delete;
mod scope;
mod update;

pub(crate) use create::{batch_create_calendar_events, create_calendar_event};
pub(crate) use delete::delete_calendar_event;
pub(crate) use scope::{delete_scoped_calendar_event, edit_scoped_calendar_event};
pub(crate) use update::update_calendar_event;

fn record_dst_ambiguity_warning(
    conn: &Connection,
    event_id: &str,
    title: &str,
    guard: &CalendarDstGuard,
) {
    if let CalendarDstGuard::Ambiguous {
        wall_clock,
        timezone,
    } = guard
    {
        let message = format!(
            "Calendar event '{title}' uses wall-clock {wall_clock} in {timezone}, which occurs \
             twice due to a daylight-saving fall-back transition. The event was saved using \
             the earlier occurrence."
        );
        lorvex_store::error_log::append_error_log_best_effort(
            conn,
            "calendar_events.dst_ambiguous",
            &message,
            Some(&format!("event_id={event_id}")),
            Some("warn"),
        );
    }
}

fn calendar_event_read_error(error: rusqlite::Error) -> McpError {
    match error {
        rusqlite::Error::FromSqlConversionFailure(column, _, source) => {
            let field = match column {
                6 => "start_date",
                10 => "all_day",
                13 => "event_type",
                _ => "calendar event projection",
            };
            McpError::Validation(format!(
                "existing calendar event row has invalid field '{field}': {source}"
            ))
        }
        other => McpError::Sql(Box::new(other)),
    }
}

pub(super) fn load_calendar_event_json(
    conn: &Connection,
    id: &str,
) -> Result<Option<Value>, McpError> {
    let Some(row) = lorvex_store::calendar_timeline::queries::get_calendar_event(conn, id)
        .map_err(calendar_event_read_error)?
    else {
        return Ok(None);
    };
    let mut event = serde_json::to_value(row)?;
    enrich_event_with_attendees(conn, &mut event)?;
    Ok(Some(event))
}

// The attendee sub-table materializer (NFC sanitization, length
// caps, PARTSTAT gate) lives in
// `lorvex_workflow::calendar_event::materialize_attendees`. Create
// and update both delegate there so the trust boundary is one
// canonical routine across MCP, CLI, and Tauri.

/// Enrich a calendar event JSON value with its attendees array derived from the sub-table.
///
/// the attendees array is the one nested per-item payload that
/// currently carries rich JSON on the wire. Known fields
/// (`email`/`name`/`status`) live in `calendar_event_attendees`; any
/// surplus keys a newer peer emitted were captured during apply in
/// `calendar_event_attendee_shadow`. We merge both here so the next
/// outbound enqueue round-trips unknown fields back to the peer mesh
/// without drop. `load_attendees_with_extras` in `lorvex-store` is the
/// single source of truth for the merge; both the MCP enrich path and
/// the app's outbox seeder call through it.
pub(crate) fn enrich_event_with_attendees(
    conn: &Connection,
    event: &mut Value,
) -> Result<(), McpError> {
    let id = match event.get("id").and_then(Value::as_str) {
        Some(id) => id.to_string(),
        None => return Ok(()),
    };

    let typed_event_id = lorvex_domain::EventId::from_trusted(id.clone());
    let attendees =
        lorvex_sync_payload::attendee_shadow::load_attendees_with_extras(conn, &typed_event_id)
            .map_err(|e| McpError::Internal(format!("load attendees for {id}: {e}")))?;
    let exception_dates =
        lorvex_store::recurrence_exceptions::load_event_exception_dates(conn, &id)
            .map_err(McpError::from)?;
    let recurrence_exceptions = serde_json::to_string(&exception_dates)?;

    if let Some(obj) = event.as_object_mut() {
        if attendees.is_empty() {
            obj.insert("attendees".to_string(), Value::Null);
        } else {
            obj.insert("attendees".to_string(), Value::Array(attendees));
        }
        obj.insert(
            "recurrence_exceptions".to_string(),
            Value::String(recurrence_exceptions),
        );
    }

    Ok(())
}

/// Enrich multiple calendar event JSON values with attendees.
///
/// this call
/// [`enrich_event_with_attendees`] in a per-event loop, issuing N
/// separate `SELECT … WHERE event_id = ?1` round trips for an
/// N-event timeline window. The batch path below collapses that
/// to a single `IN (…)` query via
/// [`lorvex_sync_payload::attendee_shadow::load_attendees_with_extras_for_events`]
/// so a 50-event calendar list page enriches in one round trip
/// instead of fifty.
pub(crate) fn enrich_events_with_attendees(
    conn: &Connection,
    events: &mut [Value],
) -> Result<(), McpError> {
    if events.is_empty() {
        return Ok(());
    }

    let ids: Vec<&str> = events
        .iter()
        .filter_map(|e| e.get("id").and_then(Value::as_str))
        .collect();
    if ids.is_empty() {
        return Ok(());
    }

    let mut by_event =
        lorvex_sync_payload::attendee_shadow::load_attendees_with_extras_for_events(conn, &ids)
            .map_err(|e| McpError::Internal(format!("batch load attendees: {e}")))?;

    for event in events.iter_mut() {
        let Some(id) = event.get("id").and_then(Value::as_str) else {
            continue;
        };
        // `remove` so each id's vector is consumed at most once even
        // if the input contained the same event twice (which
        // shouldn't happen but is cheap to make robust against).
        let attendees = by_event.remove(id).unwrap_or_default();
        let exception_dates =
            lorvex_store::recurrence_exceptions::load_event_exception_dates(conn, id)
                .map_err(McpError::from)?;
        let recurrence_exceptions = serde_json::to_string(&exception_dates)?;
        if let Some(obj) = event.as_object_mut() {
            if attendees.is_empty() {
                obj.insert("attendees".to_string(), Value::Null);
            } else {
                obj.insert("attendees".to_string(), Value::Array(attendees));
            }
            obj.insert(
                "recurrence_exceptions".to_string(),
                Value::String(recurrence_exceptions),
            );
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests;
