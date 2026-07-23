use crate::error::{AppError, AppResult};
use lorvex_domain::naming::{ENTITY_CALENDAR_EVENT, OP_DELETE, OP_UPSERT};
use lorvex_sync::outbox_enqueue::{
    enqueue_payload_delete, enqueue_payload_upsert, OutboxWriteContext,
};

pub(crate) fn get_or_create_sync_device_id_typed(conn: &rusqlite::Connection) -> AppResult<String> {
    // route through the canonical runtime helper so
    // every surface (app, MCP, CLI) shares the same `ON CONFLICT DO
    // NOTHING RETURNING` claim path. The previous shape did the
    // INSERT and the readback in two separate statements; the runtime
    // helper collapses them into one busy-retry-eligible round-trip.
    lorvex_runtime::get_or_create_device_id(conn).map_err(AppError::from)
}

pub(crate) fn enqueue_to_outbox_typed(
    conn: &rusqlite::Connection,
    entity_type: &str,
    entity_id: &str,
    operation: &str,
    payload: &serde_json::Value,
) -> AppResult<()> {
    let Some(device_id) = crate::hlc::try_device_id() else {
        return Err(AppError::Internal(
            "outbox write failed: HLC not initialized".to_string(),
        ));
    };

    let version = crate::hlc::generate_version_result()?;
    let ctx = OutboxWriteContext {
        version: &version,
        device_id,
    };

    if operation == OP_DELETE {
        enqueue_payload_delete(conn, entity_type, entity_id, payload, ctx).map_err(AppError::from)
    } else {
        enqueue_payload_upsert(conn, entity_type, entity_id, payload, ctx).map_err(AppError::from)
    }
}

pub(crate) fn enqueue_to_outbox(
    conn: &rusqlite::Connection,
    entity_type: &str,
    entity_id: &str,
    operation: &str,
    payload: &serde_json::Value,
) -> Result<(), String> {
    enqueue_to_outbox_typed(conn, entity_type, entity_id, operation, payload).map_err(String::from)
}

/// enqueue a calendar_event sync envelope. For UPSERT, the
/// payload is rebuilt from the canonical aggregate builder so the
/// envelope carries the live attendee set + per-attendee shadow extras
/// (#2317) — the previous shape passed `to_json_value(&event)` which
/// silently dropped attendees because the `CalendarEvent` struct does
/// not own them. For DELETE, we honor the caller-supplied payload (the
/// pre-delete snapshot) so peers can construct a meaningful tombstone.
pub(crate) fn enqueue_calendar_to_outbox(
    conn: &rusqlite::Connection,
    event_id: &str,
    operation: &str,
    payload: &serde_json::Value,
) -> AppResult<()> {
    let effective_payload: std::borrow::Cow<'_, serde_json::Value> = if operation == OP_UPSERT {
        let built = lorvex_sync::payload_build::aggregate::build_aggregate_payload(
            conn,
            ENTITY_CALENDAR_EVENT,
            event_id,
        )
        .map_err(AppError::from)?
        .ok_or_else(|| {
            AppError::Internal(format!(
                "calendar_event '{event_id}' enqueue: row vanished between persist and enqueue"
            ))
        })?;
        std::borrow::Cow::Owned(built)
    } else {
        std::borrow::Cow::Borrowed(payload)
    };
    enqueue_to_outbox_typed(
        conn,
        ENTITY_CALENDAR_EVENT,
        event_id,
        operation,
        effective_payload.as_ref(),
    )
    .map_err(|error| {
        AppError::Internal(format!(
            "calendar event {operation} sync enqueue failed: {error}"
        ))
    })
}
