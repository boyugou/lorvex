use super::*;
use crate::contract::{
    AddEventExceptionArgs, CreateCalendarEventArgs, RecurringCalendarEventScopeArg,
    ScopedCalendarEventDeleteArgs, ScopedCalendarEventEditArgs, UpdateCalendarEventArgs,
};
use lorvex_domain::Patch;
use lorvex_sync_payload::{AttendeeWire, CalendarEventUpdateWire};
use lorvex_workflow::calendar_recurrence_scope::{
    rebase_date_range_to_occurrence, truncate_recurrence_before, TruncateRecurrenceResult,
};

fn rebase_create_args_to_occurrence(
    mut args: CreateCalendarEventArgs,
    occurrence_date: &str,
) -> Result<CreateCalendarEventArgs, McpError> {
    let (start_date, end_date) = rebase_date_range_to_occurrence(
        &args.start_date,
        args.end_date.as_deref(),
        occurrence_date,
    )
    .ok_or_else(|| McpError::Validation("Invalid scoped calendar occurrence date".to_string()))?;
    args.start_date = start_date;
    args.end_date = end_date;
    Ok(args)
}

fn option_to_patch(value: Option<String>) -> Patch<String> {
    match value {
        Some(value) => Patch::Set(value),
        None => Patch::Clear,
    }
}

fn recurrence_to_patch(value: Option<String>) -> Patch<String> {
    match value {
        Some(value) => Patch::Set(value),
        None => Patch::Clear,
    }
}

fn update_args_from_full_payload(
    id: String,
    payload: CreateCalendarEventArgs,
    recurrence: Patch<String>,
) -> UpdateCalendarEventArgs {
    UpdateCalendarEventArgs {
        wire: CalendarEventUpdateWire {
            id,
            title: Some(payload.title),
            recurrence,
            timezone: option_to_patch(payload.timezone),
            start_date: Patch::Set(payload.start_date),
            start_time: option_to_patch(payload.start_time),
            end_date: option_to_patch(payload.end_date),
            end_time: option_to_patch(payload.end_time),
            all_day: payload.all_day,
            description: option_to_patch(payload.description),
            location: option_to_patch(payload.location),
            url: option_to_patch(payload.url),
            color: option_to_patch(payload.color),
            event_type: Patch::Set(
                payload
                    .event_type
                    .map(|e| {
                        Into::<lorvex_domain::CanonicalCalendarEventType>::into(e)
                            .as_str()
                            .to_string()
                    })
                    .unwrap_or_else(|| {
                        lorvex_domain::CanonicalCalendarEventType::Event
                            .as_str()
                            .to_string()
                    }),
            ),
            person_name: option_to_patch(payload.person_name),
            attendees: match payload.attendees {
                Some(list) => Patch::Set(
                    list.into_iter()
                        .map(|a| AttendeeWire {
                            email: a.email,
                            name: a.name,
                            // Re-emit the kebab-case canonical PARTSTAT
                            // string. The MCP handler reparses on
                            // ingest, so this stays lossless.
                            status: a.status.map(|s| {
                                lorvex_domain::AttendeeStatus::from(s).as_str().to_string()
                            }),
                        })
                        .collect(),
                ),
                None => Patch::Unset,
            },
        },
        idempotency_key: None,
        dry_run: false,
        include_diff: false,
    }
}

fn parse_json(raw: String) -> Result<Value, McpError> {
    serde_json::from_str(&raw).map_err(McpError::from)
}

fn scoped_edit_response(
    original_event: Option<Value>,
    replacement_event: Option<Value>,
    delete_result: Option<Value>,
    noop: bool,
) -> Result<String, McpError> {
    Ok(serde_json::to_string(&json!({
        "original_event": original_event,
        "replacement_event": replacement_event,
        "delete_result": delete_result,
        "noop": noop,
    }))?)
}

fn scoped_delete_response(
    event: Option<Value>,
    delete_result: Option<Value>,
    noop: bool,
) -> Result<String, McpError> {
    Ok(serde_json::to_string(&json!({
        "event": event,
        "delete_result": delete_result,
        "noop": noop,
    }))?)
}

pub(crate) fn edit_scoped_calendar_event(
    conn: &Connection,
    args: ScopedCalendarEventEditArgs,
) -> Result<String, McpError> {
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let ScopedCalendarEventEditArgs {
        id,
        occurrence_date,
        scope,
        payload,
        dry_run: _,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "edit_scoped_calendar_event",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }

    lorvex_domain::validation::validate_date_format(&occurrence_date)?;
    let original = load_calendar_event_json(conn, &id)?
        .ok_or_else(|| McpError::NotFound(format!("Calendar event '{id}' not found")))?;

    let response = match scope {
        RecurringCalendarEventScopeArg::AllInSeries => {
            let recurrence = recurrence_to_patch(payload.recurrence.clone());
            let updated = parse_json(update_calendar_event(
                conn,
                update_args_from_full_payload(id, payload, recurrence),
            )?)?;
            scoped_edit_response(Some(updated), None, None, false)?
        }
        RecurringCalendarEventScopeArg::ThisOnly => {
            crate::calendar::add_event_exception(
                conn,
                AddEventExceptionArgs {
                    event_id: id.clone(),
                    date: occurrence_date.clone(),
                    idempotency_key: None,
                    dry_run: false,
                },
            )?;
            let mut replacement_args = rebase_create_args_to_occurrence(payload, &occurrence_date)?;
            replacement_args.recurrence = None;
            let replacement = parse_json(create_calendar_event(conn, replacement_args)?)?;
            let original_after = load_calendar_event_json(conn, &id)?
                .ok_or_else(|| McpError::NotFound(format!("Calendar event '{id}' not found")))?;
            scoped_edit_response(Some(original_after), Some(replacement), None, false)?
        }
        RecurringCalendarEventScopeArg::ThisAndFollowing => {
            let start_date = original
                .get("start_date")
                .and_then(Value::as_str)
                .ok_or_else(|| {
                    McpError::Validation(
                        "existing calendar event row missing required field 'start_date'"
                            .to_string(),
                    )
                })?;
            let truncation = truncate_recurrence_before(
                original.get("recurrence").and_then(Value::as_str),
                &occurrence_date,
                Some(start_date),
            );
            if truncation == TruncateRecurrenceResult::Noop {
                scoped_edit_response(Some(original), None, None, true)?
            } else {
                let replacement_args = rebase_create_args_to_occurrence(payload, &occurrence_date)?;
                let replacement = parse_json(create_calendar_event(conn, replacement_args)?)?;
                let (original_event, delete_result) = match truncation {
                    TruncateRecurrenceResult::Truncated(recurrence)
                        if occurrence_date.as_str() > start_date =>
                    {
                        let updated = parse_json(update_calendar_event(
                            conn,
                            UpdateCalendarEventArgs {
                                wire: CalendarEventUpdateWire {
                                    id,
                                    title: None,
                                    recurrence: Patch::Set(recurrence),
                                    timezone: Patch::Unset,
                                    start_date: Patch::Unset,
                                    start_time: Patch::Unset,
                                    end_date: Patch::Unset,
                                    end_time: Patch::Unset,
                                    all_day: None,
                                    description: Patch::Unset,
                                    location: Patch::Unset,
                                    url: Patch::Unset,
                                    color: Patch::Unset,
                                    event_type: Patch::Unset,
                                    person_name: Patch::Unset,
                                    attendees: Patch::Unset,
                                },
                                idempotency_key: None,
                                dry_run: false,
                                include_diff: false,
                            },
                        )?)?;
                        (Some(updated), None)
                    }
                    TruncateRecurrenceResult::Truncated(_)
                    | TruncateRecurrenceResult::Collapse
                    | TruncateRecurrenceResult::Noop => {
                        let deleted = parse_json(delete_calendar_event(
                            conn,
                            crate::contract::DeleteCalendarEventArgs {
                                id,
                                dry_run: false,
                                idempotency_key: None,
                            },
                        )?)?;
                        (None, Some(deleted))
                    }
                };
                scoped_edit_response(original_event, Some(replacement), delete_result, false)?
            }
        }
    };

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "edit_scoped_calendar_event",
        &request_repr,
        &response,
    )?;
    Ok(response)
}

pub(crate) fn delete_scoped_calendar_event(
    conn: &Connection,
    args: ScopedCalendarEventDeleteArgs,
) -> Result<String, McpError> {
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let ScopedCalendarEventDeleteArgs {
        id,
        occurrence_date,
        scope,
        dry_run: _,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "delete_scoped_calendar_event",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }

    lorvex_domain::validation::validate_date_format(&occurrence_date)?;
    let original = load_calendar_event_json(conn, &id)?
        .ok_or_else(|| McpError::NotFound(format!("Calendar event '{id}' not found")))?;

    let response = match scope {
        RecurringCalendarEventScopeArg::AllInSeries => {
            let deleted = parse_json(delete_calendar_event(
                conn,
                crate::contract::DeleteCalendarEventArgs {
                    id,
                    dry_run: false,
                    idempotency_key: None,
                },
            )?)?;
            scoped_delete_response(None, Some(deleted), false)?
        }
        RecurringCalendarEventScopeArg::ThisOnly => {
            let updated = parse_json(crate::calendar::add_event_exception(
                conn,
                AddEventExceptionArgs {
                    event_id: id,
                    date: occurrence_date,
                    idempotency_key: None,
                    dry_run: false,
                },
            )?)?;
            scoped_delete_response(Some(updated), None, false)?
        }
        RecurringCalendarEventScopeArg::ThisAndFollowing => {
            let start_date = original
                .get("start_date")
                .and_then(Value::as_str)
                .ok_or_else(|| {
                    McpError::Validation(
                        "existing calendar event row missing required field 'start_date'"
                            .to_string(),
                    )
                })?;
            match truncate_recurrence_before(
                original.get("recurrence").and_then(Value::as_str),
                &occurrence_date,
                Some(start_date),
            ) {
                TruncateRecurrenceResult::Noop => {
                    scoped_delete_response(Some(original), None, true)?
                }
                TruncateRecurrenceResult::Truncated(recurrence)
                    if occurrence_date.as_str() > start_date =>
                {
                    let updated = parse_json(update_calendar_event(
                        conn,
                        UpdateCalendarEventArgs {
                            wire: CalendarEventUpdateWire {
                                id,
                                title: None,
                                recurrence: Patch::Set(recurrence),
                                timezone: Patch::Unset,
                                start_date: Patch::Unset,
                                start_time: Patch::Unset,
                                end_date: Patch::Unset,
                                end_time: Patch::Unset,
                                all_day: None,
                                description: Patch::Unset,
                                location: Patch::Unset,
                                url: Patch::Unset,
                                color: Patch::Unset,
                                event_type: Patch::Unset,
                                person_name: Patch::Unset,
                                attendees: Patch::Unset,
                            },
                            idempotency_key: None,
                            dry_run: false,
                            include_diff: false,
                        },
                    )?)?;
                    scoped_delete_response(Some(updated), None, false)?
                }
                TruncateRecurrenceResult::Truncated(_) | TruncateRecurrenceResult::Collapse => {
                    let deleted = parse_json(delete_calendar_event(
                        conn,
                        crate::contract::DeleteCalendarEventArgs {
                            id,
                            dry_run: false,
                            idempotency_key: None,
                        },
                    )?)?;
                    scoped_delete_response(None, Some(deleted), false)?
                }
            }
        }
    };

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "delete_scoped_calendar_event",
        &request_repr,
        &response,
    )?;
    Ok(response)
}
