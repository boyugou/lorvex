use super::update_calendar_event_internal;
use super::*;
use crate::commands::sync_timestamp_now;
use crate::event_bus;
use lorvex_domain::{AttendeeStatus, CanonicalCalendarEventType, Patch};
use lorvex_sync_payload::{AttendeeWire, CalendarEventUpdateWire};
use lorvex_workflow::calendar_event::{AttendeeShadowInput, CalendarEventUpdateInput};

/// Lift the canonical attendee wire into the workflow's
/// `AttendeeShadowInput`, strict-parsing the raw PARTSTAT string into
/// the canonical [`AttendeeStatus`] enum at the IPC trust boundary so
/// non-canonical spellings reject before the materializer.
fn attendee_wire_into_shadow(wire: AttendeeWire) -> Result<AttendeeShadowInput, String> {
    let status = match wire.status {
        Some(raw) => Some(
            AttendeeStatus::parse_strict(&raw)
                .ok_or_else(|| format!("unknown attendee status: {raw}"))?,
        ),
        None => None,
    };
    Ok(AttendeeShadowInput {
        email: wire.email,
        name: wire.name,
        status,
    })
}

/// Lift the canonical [`CalendarEventUpdateWire`] into the workflow's
/// [`CalendarEventUpdateInput`]. Strict-parses the raw PARTSTAT and
/// the raw `event_type` string at the IPC trust boundary; lets the
/// workflow op handle every other validation.
pub(crate) fn wire_into_workflow_input(
    wire: CalendarEventUpdateWire,
) -> Result<CalendarEventUpdateInput, String> {
    let attendees = match wire.attendees {
        Patch::Unset => Patch::Unset,
        Patch::Clear => Patch::Clear,
        Patch::Set(list) => Patch::Set(
            list.into_iter()
                .map(attendee_wire_into_shadow)
                .collect::<Result<Vec<_>, _>>()?,
        ),
    };
    let event_type = match wire.event_type {
        Patch::Unset => Patch::Unset,
        Patch::Clear => Patch::Clear,
        Patch::Set(raw) => Patch::Set(parse_canonical_event_type(&raw)?),
    };
    Ok(CalendarEventUpdateInput {
        id: wire.id,
        title: wire.title,
        recurrence: wire.recurrence,
        timezone: wire.timezone,
        start_date: wire.start_date,
        start_time: wire.start_time,
        end_date: wire.end_date,
        end_time: wire.end_time,
        all_day: wire.all_day,
        description: wire.description,
        location: wire.location,
        url: wire.url,
        color: wire.color,
        event_type,
        person_name: wire.person_name,
        attendees,
    })
}

fn parse_canonical_event_type(raw: &str) -> Result<CanonicalCalendarEventType, String> {
    match raw {
        "event" => Ok(CanonicalCalendarEventType::Event),
        "birthday" => Ok(CanonicalCalendarEventType::Birthday),
        "anniversary" => Ok(CanonicalCalendarEventType::Anniversary),
        "memorial" => Ok(CanonicalCalendarEventType::Memorial),
        other => Err(format!("unknown event_type: {other}")),
    }
}

/// Accepts the update payload as a raw JSON value so that serde can
/// distinguish absent fields from explicit `null` values via the
/// `Patch<T>` serde impl. The frontend sends `null` to clear a field.
#[tauri::command]
pub fn update_calendar_event(payload: serde_json::Value) -> Result<CalendarEvent, String> {
    let mut wire: CalendarEventUpdateWire =
        serde_json::from_value(payload).map_err(|e| format!("Invalid update payload: {e}"))?;
    let conn = get_conn()?;
    // event ids are UUIDv7 — shape-check before the
    // writer transaction so a malformed id from the renderer can't
    // reach `update_calendar_event_internal`.
    wire.id = crate::commands::shared::validate_uuid_id(&wire.id, "id")?;
    let workflow_input = wire_into_workflow_input(wire)?;
    let now = sync_timestamp_now();
    let result =
        update_calendar_event_internal(&conn, workflow_input, &now).map_err(String::from)?;
    event_bus::emit_data_changed(event_bus::Entity::CalendarEvent);
    Ok(result)
}
