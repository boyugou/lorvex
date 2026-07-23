//! Calendar event create command (Tauri IPC adapter).
//!
//! Thin wrapper that translates the IPC arg shape into
//! [`lorvex_workflow::calendar_event::CalendarEventCreateInput`] and
//! delegates validation, `normalize_calendar_create`, recurrence anchoring, DST
//! diagnostics, and the row INSERT to
//! [`CreateCalendarEventMutation`]. The IPC layer owns the Tauri
//! transaction, sync outbox enqueue, DST `error_log` row write, and
//! `event_bus` broadcast.

use lorvex_domain::CanonicalCalendarEventType;
use lorvex_workflow::calendar_event::{
    CalendarEventCreateInput, CalendarEventOpError, CreateCalendarEventMutation,
};
use serde::Deserialize;

use crate::commands::shared::effects::execute_ipc_mutation_with_finalizer;
use crate::commands::sync_timestamp_now;
use crate::commands::with_immediate_transaction;
use crate::error::{AppError, AppResult};

use super::*;

#[cfg(test)]
mod tests;

#[derive(Debug, Deserialize)]
pub struct CreateCalendarEventArgs {
    pub title: String,
    pub recurrence: Option<String>,
    pub timezone: Option<String>,
    pub start_date: String,
    pub start_time: Option<String>,
    pub end_date: Option<String>,
    pub end_time: Option<String>,
    pub all_day: Option<bool>,
    pub description: Option<String>,
    pub location: Option<String>,
    pub url: Option<String>,
    pub color: Option<String>,
    pub event_type: Option<CanonicalCalendarEventType>,
    pub person_name: Option<String>,
}

fn map_op_error(error: CalendarEventOpError) -> AppError {
    match error {
        CalendarEventOpError::Validation(message) => AppError::Validation(message),
        CalendarEventOpError::Store(store_error) => AppError::from(store_error),
    }
}

fn workflow_create_input(args: CreateCalendarEventArgs) -> CalendarEventCreateInput {
    let CreateCalendarEventArgs {
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
    } = args;
    CalendarEventCreateInput {
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
        attendees: None,
    }
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
pub(crate) fn create_calendar_event_with_conn(
    conn: &rusqlite::Connection,
    args: CreateCalendarEventArgs,
    now: String,
) -> AppResult<CalendarEvent> {
    // `now` is part of the legacy entry shape; the workflow op
    // re-derives it through `sync_timestamp_now` inside `apply`. The
    // arg stays so callers (test fixtures, undo) don't need to change.
    let _ = now;
    let event_id = lorvex_domain::new_entity_id_string();
    let input = workflow_create_input(args);
    let mutation =
        CreateCalendarEventMutation::new(event_id.clone(), input).map_err(map_op_error)?;

    execute_ipc_mutation_with_finalizer(conn, &mutation, |conn, execution| {
        enqueue_calendar_to_outbox(
            conn,
            &event_id,
            lorvex_domain::naming::OP_UPSERT,
            &execution.output.after,
        )?;
        Ok(())
    })?;

    let event = load_calendar_event(conn, &event_id).map_err(AppError::Internal)?;
    if let CalendarDstGuard::Ambiguous {
        ref wall_clock,
        ref timezone,
    } = *mutation.dst_guard()
    {
        let message = format!(
            "Calendar event '{}' uses wall-clock {wall_clock} in {timezone}, which occurs \
             twice due to a daylight-saving fall-back transition. The event was saved using \
             the earlier occurrence.",
            event.title
        );
        crate::commands::diagnostics::append_error_log_internal(
            conn,
            "calendar_events.dst_ambiguous",
            &message,
            Some(format!("event_id={}", event.id)),
            Some("warn".to_string()),
        )
        .map_err(AppError::Validation)?;
    }
    Ok(event)
}

fn create_calendar_event_internal(
    conn: &rusqlite::Connection,
    args: CreateCalendarEventArgs,
    now: String,
) -> AppResult<CalendarEvent> {
    // `execute_ipc_mutation_with_finalizer` already broadcasts the
    // event_bus refresh; the wrapping transaction is all that remains
    // for this entry point. Tests still consume `create_calendar_event_internal`
    // because it's the smallest unit that runs end-to-end with an
    // implicit-transaction guarantee.
    let event = with_immediate_transaction(conn, |conn| {
        create_calendar_event_with_conn(conn, args, now)
    })?;
    Ok(event)
}

#[allow(clippy::too_many_arguments)]
#[tauri::command]
pub fn create_calendar_event(
    title: String,
    start_date: String,
    recurrence: Option<String>,
    timezone: Option<String>,
    start_time: Option<String>,
    end_date: Option<String>,
    end_time: Option<String>,
    all_day: Option<bool>,
    description: Option<String>,
    location: Option<String>,
    url: Option<String>,
    color: Option<String>,
    event_type: Option<CanonicalCalendarEventType>,
    person_name: Option<String>,
) -> Result<CalendarEvent, String> {
    let conn = get_conn()?;
    create_calendar_event_internal(
        &conn,
        CreateCalendarEventArgs {
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
        },
        sync_timestamp_now(),
    )
    .map_err(String::from)
}
