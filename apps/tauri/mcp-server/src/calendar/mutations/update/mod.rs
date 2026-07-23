use super::*;
use crate::runtime::change_tracking::execute_mcp_mutation;
use lorvex_domain::{AttendeeStatus, CanonicalCalendarEventType, Patch};
use lorvex_sync_payload::{AttendeeWire, CalendarEventUpdateWire};
use lorvex_workflow::calendar_event::{
    AttendeeShadowInput, CalendarEventOpError, CalendarEventUpdateInput,
    UpdateCalendarEventMutation,
};
use lorvex_workflow::calendar_normalization::CalendarUpdateExisting;

/// MCP update adapter. The workflow mutation owns `normalize_calendar_update`;
/// this module only strict-parses MCP wire enums and reconstructs the
/// existing-field context needed by the workflow.
fn map_op_error(error: CalendarEventOpError) -> McpError {
    match error {
        CalendarEventOpError::Validation(message) => McpError::Validation(message),
        CalendarEventOpError::Store(store_error) => McpError::Store(Box::new(store_error)),
    }
}

/// Strict-parse a single attendee wire entry. The wire carries the
/// raw PARTSTAT string so the canonical [`CalendarEventUpdateWire`]
/// shape stays surface-agnostic; the MCP handler is the trust
/// boundary that rejects non-canonical spellings.
fn attendee_wire_into_shadow(wire: AttendeeWire) -> Result<AttendeeShadowInput, McpError> {
    let status = match wire.status {
        Some(raw) => Some(
            AttendeeStatus::parse_strict(&raw)
                .ok_or_else(|| McpError::Validation(format!("unknown attendee status: {raw}")))?,
        ),
        None => None,
    };
    Ok(AttendeeShadowInput {
        email: wire.email,
        name: wire.name,
        status,
    })
}

fn shadow_attendees_patch(
    input: Patch<Vec<AttendeeWire>>,
) -> Result<Patch<Vec<AttendeeShadowInput>>, McpError> {
    input.try_map(|list| {
        list.into_iter()
            .map(attendee_wire_into_shadow)
            .collect::<Result<Vec<_>, _>>()
    })
}

fn parse_canonical_event_type(raw: &str) -> Result<CanonicalCalendarEventType, McpError> {
    match raw {
        "event" => Ok(CanonicalCalendarEventType::Event),
        "birthday" => Ok(CanonicalCalendarEventType::Birthday),
        "anniversary" => Ok(CanonicalCalendarEventType::Anniversary),
        "memorial" => Ok(CanonicalCalendarEventType::Memorial),
        other => Err(McpError::Validation(format!("unknown event_type: {other}"))),
    }
}

fn event_type_patch(input: Patch<String>) -> Result<Patch<CanonicalCalendarEventType>, McpError> {
    input.try_map(|raw| parse_canonical_event_type(&raw))
}

fn required_existing_string_field(
    before_obj: &serde_json::Map<String, Value>,
    field: &str,
) -> Result<String, McpError> {
    match before_obj.get(field) {
        Some(Value::String(value)) if !value.trim().is_empty() => Ok(value.clone()),
        _ => Err(McpError::Validation(format!(
            "existing calendar event row missing required field '{field}'"
        ))),
    }
}

fn required_existing_bool_field(
    before_obj: &serde_json::Map<String, Value>,
    field: &str,
) -> Result<bool, McpError> {
    match before_obj.get(field) {
        Some(Value::Bool(value)) => Ok(*value),
        Some(Value::Number(value)) => match value.as_i64() {
            Some(0) => Ok(false),
            Some(1) => Ok(true),
            _ => Err(McpError::Validation(format!(
                "existing calendar event row has invalid boolean field '{field}'"
            ))),
        },
        _ => Err(McpError::Validation(format!(
            "existing calendar event row missing required field '{field}'"
        ))),
    }
}

fn optional_existing_string_field(
    before_obj: &serde_json::Map<String, Value>,
    field: &str,
) -> Option<String> {
    before_obj
        .get(field)
        .and_then(Value::as_str)
        .map(ToString::to_string)
}

pub(crate) fn update_calendar_event(
    conn: &Connection,
    args: UpdateCalendarEventArgs,
) -> Result<String, McpError> {
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let UpdateCalendarEventArgs {
        wire,
        idempotency_key,
        dry_run: _,
        include_diff,
    } = args;
    let CalendarEventUpdateWire {
        id,
        title,
        recurrence,
        timezone,
        start_date,
        start_time,
        end_date,
        end_time,
        all_day,
        description,
        location,
        url,
        color,
        event_type,
        person_name,
        attendees,
    } = wire;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "update_calendar_event",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }

    let before = load_calendar_event_json(conn, &id)?
        .ok_or_else(|| McpError::NotFound(format!("Calendar event '{id}' not found")))?;
    let before_obj = before
        .as_object()
        .ok_or_else(|| McpError::Internal("Invalid calendar event row shape".to_string()))?;
    let existing = CalendarUpdateExisting {
        start_date: required_existing_string_field(before_obj, "start_date")?,
        start_time: optional_existing_string_field(before_obj, "start_time"),
        end_date: optional_existing_string_field(before_obj, "end_date"),
        end_time: optional_existing_string_field(before_obj, "end_time"),
        all_day: required_existing_bool_field(before_obj, "all_day")?,
        timezone: optional_existing_string_field(before_obj, "timezone"),
    };
    let before_recurrence = optional_existing_string_field(before_obj, "recurrence");

    // MCP's wire contract is the canonical `CalendarEventUpdateWire`
    // — the handler's only adapter work is strict-parsing the raw
    // `event_type` and PARTSTAT strings at this trust boundary.
    let input = CalendarEventUpdateInput {
        id: id.clone(),
        title,
        recurrence,
        timezone,
        start_date,
        start_time,
        end_date,
        end_time,
        all_day,
        description,
        location,
        url,
        color,
        event_type: event_type_patch(event_type)?,
        person_name,
        attendees: shadow_attendees_patch(attendees)?,
    };

    let mutation =
        UpdateCalendarEventMutation::new(input, existing, before.clone(), before_recurrence)
            .map_err(map_op_error)?;
    let output = execute_mcp_mutation(conn, &mutation, "update_calendar_event", id)?;
    let event = output.after;
    let title = event
        .get("title")
        .and_then(Value::as_str)
        .unwrap_or("unknown");
    record_dst_ambiguity_warning(conn, mutation.event_id(), title, mutation.dst_guard());

    let response = if include_diff {
        serde_json::to_string(&serde_json::json!({
            "before": before.clone(),
            "after": event.clone(),
            "event": event,
        }))?
    } else {
        serde_json::to_string(&event)?
    };
    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "update_calendar_event",
        &request_repr,
        &response,
    )?;
    Ok(response)
}

#[cfg(test)]
mod tests;
