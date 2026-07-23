use lorvex_domain::CanonicalCalendarEventType;
use lorvex_store::calendar_timeline::CalendarEventRow;
use serde::{Deserialize, Serialize};

// `pub(super)` so the child modules under `events/` resolve these
// helpers via `super::*` without an intermediate `mutations/` layer.
pub(super) use crate::commands::enqueue_calendar_to_outbox;
pub(super) use crate::commands::with_immediate_transaction;
pub(super) use crate::db::get_conn;

pub(crate) mod create;
pub(crate) mod delete;
pub(crate) mod exceptions;
pub(crate) mod ics_export;
pub(crate) mod query;
pub(crate) mod scope;
pub(crate) mod undo;
pub(crate) mod update;
mod validation;

#[allow(unused_imports)]
pub use create::create_calendar_event;
#[cfg(test)]
pub(crate) use delete::delete_calendar_event_internal;
#[allow(unused_imports)]
pub use delete::{delete_calendar_event, DeleteCalendarEventResult};
pub(crate) use lorvex_workflow::calendar_normalization::CalendarDstGuard;
#[allow(unused_imports)]
#[rustfmt::skip]
pub use query::{get_events_by_date_range};
pub(crate) use undo::{build_undo_token, capture_list_snapshot};
#[allow(unused_imports)]
pub use update::update_calendar_event;
#[cfg(test)]
pub(crate) use update::update_calendar_event_internal;
#[allow(dead_code)]
pub(crate) use validation::normalize_calendar_recurrence;
pub(crate) use validation::parse_calendar_date;

// `load_calendar_event` / `load_optional_calendar_event` were lifted from
// the former `events/mutations/mod.rs` (#3371 phase 1c) when the
// redundant `mutations/` middle layer was dropped — they remain
// `pub(super)` because only siblings under `events/` consume them.
pub(super) fn load_calendar_event(
    conn: &rusqlite::Connection,
    id: &str,
) -> Result<CalendarEvent, String> {
    load_optional_calendar_event(conn, id)?.ok_or_else(|| format!("Calendar event not found: {id}"))
}

pub(super) fn load_optional_calendar_event(
    conn: &rusqlite::Connection,
    id: &str,
) -> Result<Option<CalendarEvent>, String> {
    let row = lorvex_store::calendar_timeline::queries::get_calendar_event(conn, id)
        .map_err(crate::commands::shared::sanitize_db_error)?;
    let Some(row) = row else { return Ok(None) };
    let mut event = calendar_event_from_store_row(row);
    event.attendees = load_event_attendees(conn, &event.id)?;
    Ok(Some(event))
}

/// Load the attendees array for a single calendar event, merged with
/// any forward-compat shadow fields. Mirrors what the MCP server's
/// `enrich_event_with_attendees` writes onto its JSON projection and
/// what the sync envelope builder ships on the wire — every read path
/// the desktop app exposes therefore matches the assistant's view.
/// Returns `None` when the event has zero attendees (canonical event
/// without invitees), matching the MCP `attendees: null` convention.
pub(crate) fn load_event_attendees(
    conn: &rusqlite::Connection,
    event_id: &str,
) -> Result<Option<Vec<CalendarEventAttendee>>, String> {
    let typed = lorvex_domain::EventId::from_trusted(event_id.to_string());
    let raw = lorvex_sync_payload::attendee_shadow::load_attendees_with_extras(conn, &typed)
        .map_err(|e| format!("load attendees for {event_id}: {e}"))?;
    if raw.is_empty() {
        return Ok(None);
    }
    let parsed: Vec<CalendarEventAttendee> = raw
        .into_iter()
        .map(|v: serde_json::Value| {
            let email = v
                .get("email")
                .and_then(serde_json::Value::as_str)
                .unwrap_or("")
                .to_string();
            let name = v
                .get("name")
                .and_then(serde_json::Value::as_str)
                .map(str::to_string);
            let status = v
                .get("status")
                .and_then(serde_json::Value::as_str)
                .map(str::to_string);
            CalendarEventAttendee {
                email,
                name,
                status,
            }
        })
        .collect();
    Ok(Some(parsed))
}

/// Attendee row projected onto the IPC `CalendarEvent`. Mirrors the
/// `{ email, name, status }` columns on `calendar_event_attendees` (the
/// only three keys the schema currently owns; any forward-compat
/// extras a newer peer emitted live on `calendar_event_attendee_shadow`
/// and round-trip through the sync envelope, but the desktop IPC
/// projects only the known columns).
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct CalendarEventAttendee {
    pub email: String,
    pub name: Option<String>,
    pub status: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct CalendarEvent {
    pub id: String,
    pub title: String,
    pub description: Option<String>,
    pub recurrence: Option<String>,
    pub recurrence_exceptions: Option<String>,
    pub timezone: Option<String>,
    pub start_date: String,
    pub start_time: Option<String>,
    pub end_date: Option<String>,
    pub end_time: Option<String>,
    pub all_day: bool,
    pub location: Option<String>,
    pub url: Option<String>,
    pub color: Option<String>,
    pub event_type: CanonicalCalendarEventType,
    pub person_name: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    /// Attendees attached to this event, merged from
    /// `calendar_event_attendees` + the forward-compat shadow.
    /// `None` for canonical events with no invitees (matches the
    /// MCP `attendees: null` convention so every read surface — MCP
    /// JSON projection, sync envelope, Tauri IPC — agrees on the
    /// "no attendees" shape).
    pub attendees: Option<Vec<CalendarEventAttendee>>,
}

pub(crate) fn calendar_event_from_store_row(row: CalendarEventRow) -> CalendarEvent {
    let start_date = row.start_date().to_string();
    let start_time = row.start_time().map(|time| time.to_string());
    let end_date = row.end_date().map(|date| date.to_string());
    let end_time = row.end_time().map(|time| time.to_string());
    let all_day = row.all_day();

    CalendarEvent {
        id: row.id,
        title: row.title,
        description: row.description,
        recurrence: row.recurrence,
        recurrence_exceptions: row.recurrence_exceptions,
        timezone: row.timezone,
        start_date,
        start_time,
        end_date,
        end_time,
        all_day,
        location: row.location,
        url: row.url,
        color: row.color,
        event_type: row.event_type,
        person_name: row.person_name,
        created_at: row.created_at,
        updated_at: row.updated_at,
        // Callers that need attendees go through
        // `load_optional_calendar_event`, which overlays the merged
        // attendee array onto this skeleton via `load_event_attendees`.
        // Read paths that bypass that helper (the unified-timeline
        // SELECT that projects across canonical + provider tables)
        // also project attendees independently and never construct
        // CalendarEvent through this helper.
        attendees: None,
    }
}

/// Kind discriminator for `UnifiedCalendarEvent.kind`.
/// was an unconstrained `String` that always carried one of two exact
/// values; narrowed to a proper enum so the TS `'canonical' | 'provider'`
/// mirror now has a direct Rust counterpart and serialization is
/// compile-time-checked.
#[derive(Debug, Serialize, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum UnifiedCalendarEventKind {
    Canonical,
    Provider,
}

/// Unified calendar event returned by the combined query across canonical and
/// provider tables. Extends `CalendarEvent` with `kind` and `editable` fields.
#[derive(Debug, Serialize, Clone)]
pub struct UnifiedCalendarEvent {
    pub id: String,
    pub title: String,
    pub description: Option<String>,
    pub recurrence: Option<String>,
    pub recurrence_exceptions: Option<String>,
    pub timezone: Option<String>,
    pub start_date: String,
    pub start_time: Option<String>,
    pub end_date: Option<String>,
    pub end_time: Option<String>,
    pub all_day: bool,
    pub location: Option<String>,
    pub url: Option<String>,
    pub color: Option<String>,
    /// intentionally `String` (not `CanonicalCalendarEventType`)
    /// because provider events preserve upstream iCal categories that are
    /// NOT in the canonical allowlist. The TS mirror matches — narrowing
    /// would break the provider passthrough. Canonical-event writes still
    /// go through the typed enum at the CalendarEvent boundary.
    pub event_type: String,
    pub person_name: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    /// `"canonical"` for app-owned events, `"provider"` for external events.
    pub kind: UnifiedCalendarEventKind,
    /// Whether the event can be edited/deleted in the UI.
    pub editable: bool,
    /// JSON array of attendees for provider events.
    /// Format: `[{"email":"...","name":"...","status":"accepted"}]`.
    pub attendees_json: Option<String>,
}
