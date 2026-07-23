//! Calendar event update orchestrator (Tauri IPC adapter).
//!
//! Thin wrapper that accepts the IPC wire payload, lifts it into
//! [`lorvex_workflow::calendar_event::CalendarEventUpdateInput`], and
//! delegates validation, `normalize_calendar_update`, recurrence anchoring, EXDATE
//! preservation, and the row UPDATE to
//! [`UpdateCalendarEventMutation`]. The IPC layer owns the Tauri
//! transaction, sync outbox enqueue, DST `error_log` row write, and
//! `event_bus` broadcast.
//!
//! Wire shape: pure `Patch<T>` JSON — an absent key means "don't
//! touch", `null` means "clear", and a string value means "set". The
//! renderer emits this directly through `buildPayload`; there is no
//! `clear_fields[]` array on the wire.

pub(crate) mod command;

#[cfg(test)]
mod tests;

pub use command::update_calendar_event;
#[allow(unused_imports)]
pub(crate) use command::wire_into_workflow_input;

use lorvex_workflow::calendar_event::{
    CalendarEventOpError, CalendarEventUpdateInput, UpdateCalendarEventMutation,
};
use lorvex_workflow::calendar_normalization::CalendarUpdateExisting;

use crate::commands::shared::effects::execute_ipc_mutation_with_finalizer;
use crate::commands::shared::to_json_value;
use crate::commands::with_immediate_transaction;
use crate::error::{AppError, AppResult};

use super::*;

fn map_op_error(error: CalendarEventOpError) -> AppError {
    match error {
        CalendarEventOpError::Validation(message) => AppError::Validation(message),
        CalendarEventOpError::Store(store_error) => AppError::from(store_error),
    }
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
pub(crate) fn update_calendar_event_internal(
    conn: &rusqlite::Connection,
    input: CalendarEventUpdateInput,
    now: &str,
) -> AppResult<CalendarEvent> {
    with_immediate_transaction(conn, |conn| {
        update_calendar_event_with_conn(conn, input, now)
    })
}

pub(crate) fn update_calendar_event_with_conn(
    conn: &rusqlite::Connection,
    input: CalendarEventUpdateInput,
    now: &str,
) -> AppResult<CalendarEvent> {
    // `now` is part of the legacy entry shape; the workflow op
    // re-derives it through `sync_timestamp_now` inside `apply`. The
    // arg stays so the entry-point signature doesn't ripple.
    let _ = now;

    let event_id = input.id.clone();
    let before_event = load_optional_calendar_event(conn, &event_id)
        .map_err(AppError::Internal)?
        .ok_or_else(|| AppError::NotFound(format!("Calendar event not found: {event_id}")))?;
    let before_recurrence = before_event.recurrence.clone();
    let before_json = to_json_value(&before_event)?;
    let existing = existing_from_event(&before_event);

    let mutation =
        UpdateCalendarEventMutation::new(input, existing, before_json, before_recurrence)
            .map_err(map_op_error)?;

    let dst_guard = mutation.dst_guard().clone();

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
    } = dst_guard
    {
        let message = format!(
            "Calendar event '{}' uses wall-clock {wall_clock} in {timezone}, which occurs \
                 twice due to a daylight-saving fall-back transition. The event was saved using \
                 the earlier occurrence.",
            event.title
        );
        // The row was already committed and the outbox was already
        // flushed by `execute_ipc_mutation_with_finalizer` above; this
        // DST advisory log is best-effort observability. Surface log
        // failures via `eprintln!` so they reach the diagnostic stream
        // without misclassifying as a user-facing validation error.
        // Returning `AppError::Validation` here would show the user a
        // "validation error" after the event was already saved, and a
        // retry would double-create the row.
        if let Err(log_err) = crate::commands::diagnostics::append_error_log_internal(
            conn,
            "calendar_events.dst_ambiguous",
            &message,
            Some(format!("event_id={}", event.id)),
            Some("warn".to_string()),
        ) {
            eprintln!(
                "calendar_events.dst_ambiguous log insert failed (event already committed): \
                 event_id={} err={log_err}",
                event.id
            );
        }
    }
    Ok(event)
}

fn existing_from_event(event: &CalendarEvent) -> CalendarUpdateExisting {
    CalendarUpdateExisting {
        start_date: event.start_date.clone(),
        start_time: event.start_time.clone(),
        end_date: event.end_date.clone(),
        end_time: event.end_time.clone(),
        all_day: event.all_day,
        timezone: event.timezone.clone(),
    }
}
