use crate::db::get_read_conn;
use crate::error::AppError;
use lorvex_domain::CalendarAiAccessMode;

use super::{
    calendar_event_from_store_row, parse_calendar_date, CalendarEvent, UnifiedCalendarEvent,
    UnifiedCalendarEventKind,
};

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn get_calendar_event(id: String) -> Result<CalendarEvent, String> {
    // event ids are UUIDv7 — shape-check at the IPC
    // boundary so the renderer can't smuggle a malformed id back into
    // a later writer (this read powers the calendar-event edit panel).
    let id = crate::commands::shared::validate_uuid_id(&id, "id")?;
    // route through typed `AppError` so the IPC
    // envelope carries `kind: "not_found"` for the no-row case
    // (toast layer renders an inline "event no longer exists"
    // affordance) and `kind: "internal"` for any other rusqlite
    // failure — the previous shape stringified the raw rusqlite
    // error directly, leaking SQL detail to the renderer.
    let conn = get_read_conn().map_err(String::from)?;
    let row = lorvex_store::calendar_timeline::queries::get_calendar_event(&conn, &id)
        .map_err(AppError::from)
        .map_err(String::from)?
        .ok_or_else(|| AppError::NotFound(format!("Calendar event not found: {id}")))
        .map_err(String::from)?;
    let mut event = calendar_event_from_store_row(row);
    // Mirror the IPC `load_optional_calendar_event` projection so this
    // direct read path agrees with the mutation read paths — the
    // renderer's edit panel cannot tell whether it landed via a fresh
    // GET or a post-write refetch, so both shapes must carry the
    // merged attendees array.
    event.attendees = super::load_event_attendees(&conn, &event.id)?;
    Ok(event)
}

/// Retrieve calendar events that overlap `[from, to]`, with recurring events
/// expanded into individual occurrences. Includes both canonical and provider
/// events (Apple Calendar, .ics subscriptions, etc.) so all Tauri surfaces
/// (today, upcoming, popover) see the user's full schedule.
///
/// Delegates to `lorvex_store::calendar_timeline::get_calendar_timeline`.
#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn get_events_by_date_range(
    from: String,
    to: String,
) -> Result<Vec<UnifiedCalendarEvent>, String> {
    let from_day = parse_calendar_date(&from, "from")?;
    let to_day = parse_calendar_date(&to, "to")?;
    if to_day < from_day {
        return Err("to must be on or after from".to_string());
    }

    let conn = get_read_conn()?;
    let anchor_timezone = lorvex_workflow::timezone::anchored_timezone_name(&conn)
        .map_err(AppError::from)
        .map_err(String::from)?;

    let timeline = lorvex_store::calendar_timeline::get_calendar_timeline(
        &conn,
        &from,
        &to,
        CalendarAiAccessMode::FullDetails,
        &anchor_timezone,
    )
    .map_err(AppError::from)
    .map_err(String::from)?;

    let events: Vec<UnifiedCalendarEvent> = timeline
        .into_iter()
        .map(|item| {
            use lorvex_store::calendar_timeline::TimelineSource;
            UnifiedCalendarEvent {
                kind: match item.source() {
                    TimelineSource::Canonical => UnifiedCalendarEventKind::Canonical,
                    TimelineSource::Provider => UnifiedCalendarEventKind::Provider,
                },
                editable: item.editable(),
                id: item.id().to_string(),
                title: item.title().to_string(),
                description: None,
                recurrence: if item.is_recurring() {
                    Some("recurring".to_string())
                } else {
                    None
                },
                recurrence_exceptions: None,
                timezone: item.timezone().map(str::to_string),
                start_date: item.start_date().to_string(),
                start_time: item.start_time().map(|t| t.to_string()),
                end_date: item.end_date().map(|d| d.to_string()),
                end_time: item.end_time().map(|t| t.to_string()),
                all_day: item.all_day(),
                location: item.location().map(str::to_string),
                url: item.url().map(str::to_string),
                color: item.color().map(str::to_string),
                event_type: item.event_type().to_string(),
                person_name: item.person_name().map(str::to_string),
                created_at: String::new(),
                updated_at: String::new(),
                attendees_json: item.attendees_json().map(str::to_string),
            }
        })
        .collect();

    Ok(events)
}

/// Query both `calendar_events` and `provider_calendar_events` for a date range,
/// returning a merged list of `UnifiedCalendarEvent` items sorted chronologically.
///
/// Delegates to the shared `lorvex_store::calendar_timeline::get_calendar_timeline`
/// query and maps the result to the Tauri-specific `UnifiedCalendarEvent` type.
#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn get_calendar_events_unified(
    from: String,
    to: String,
) -> Result<Vec<UnifiedCalendarEvent>, String> {
    let from_day = parse_calendar_date(&from, "from")?;
    let to_day = parse_calendar_date(&to, "to")?;
    if to_day < from_day {
        return Err("to must be on or after from".to_string());
    }

    let conn = get_read_conn()?;
    let anchor_timezone = lorvex_workflow::timezone::anchored_timezone_name(&conn)
        .map_err(AppError::from)
        .map_err(String::from)?;

    let timeline = lorvex_store::calendar_timeline::get_calendar_timeline(
        &conn,
        &from,
        &to,
        CalendarAiAccessMode::FullDetails,
        &anchor_timezone,
    )
    .map_err(AppError::from)
    .map_err(String::from)?;

    let unified: Vec<UnifiedCalendarEvent> = timeline
        .into_iter()
        .map(|item| {
            use lorvex_store::calendar_timeline::TimelineSource;
            UnifiedCalendarEvent {
                kind: match item.source() {
                    TimelineSource::Canonical => UnifiedCalendarEventKind::Canonical,
                    TimelineSource::Provider => UnifiedCalendarEventKind::Provider,
                },
                editable: item.editable(),
                id: item.id().to_string(),
                title: item.title().to_string(),
                description: None,
                recurrence: if item.is_recurring() {
                    Some("recurring".to_string())
                } else {
                    None
                },
                recurrence_exceptions: None,
                timezone: item.timezone().map(str::to_string),
                start_date: item.start_date().to_string(),
                start_time: item.start_time().map(|t| t.to_string()),
                end_date: item.end_date().map(|d| d.to_string()),
                end_time: item.end_time().map(|t| t.to_string()),
                all_day: item.all_day(),
                location: item.location().map(str::to_string),
                url: item.url().map(str::to_string),
                color: item.color().map(str::to_string),
                event_type: item.event_type().to_string(),
                person_name: item.person_name().map(str::to_string),
                created_at: String::new(),
                updated_at: String::new(),
                attendees_json: item.attendees_json().map(str::to_string),
            }
        })
        .collect();

    Ok(unified)
}
