use lorvex_domain::naming::OP_UPSERT;
// `ENTITY_CALENDAR_EVENT` is referenced only by colocated
// `#[cfg(test)]` outbox-payload assertions. Gate the import with the
// same cfg so the release build stays clean.
#[cfg(test)]
use lorvex_domain::naming::ENTITY_CALENDAR_EVENT;
use lorvex_domain::EventId;
use lorvex_store::repositories::calendar_event_exceptions;

use crate::commands::enqueue_calendar_to_outbox;
use crate::commands::shared::to_json_value;
use crate::commands::{sync_timestamp_now, with_immediate_transaction};
use crate::db::get_conn;
use crate::error::{AppError, AppResult};
use crate::event_bus;

use super::{load_calendar_event, CalendarEvent};

pub(crate) fn add_event_exception_with_conn(
    conn: &rusqlite::Connection,
    event_id: &EventId,
    date: &str,
    now: &str,
) -> AppResult<CalendarEvent> {
    let version = crate::hlc::generate_version_result()?;

    calendar_event_exceptions::add_recurrence_exception(conn, event_id, date, &version, now)
        .map_err(AppError::from)?;

    let event = load_calendar_event(conn, event_id.as_str()).map_err(AppError::Internal)?;
    let after = to_json_value(&event)?;
    enqueue_calendar_to_outbox(conn, &event.id, OP_UPSERT, &after)?;

    Ok(event)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
fn add_event_exception_inner(event_id: EventId, date: String) -> AppResult<CalendarEvent> {
    // Validate the exception date as canonical YYYY-MM-DD before
    // opening the transaction. Recurrence expansion in `lorvex-domain`
    // and the apply pipeline both assume YYYY-MM-DD in
    // `recurrence_exceptions` JSON; without this guard a value like
    // `"tomorrow"` or `"2026-04-31"` would ride the upsert envelope
    // to every peer and silently break expansion.
    lorvex_domain::validation::validate_date_format(&date)
        .map_err(|e| AppError::Validation(e.to_string()))?;
    let conn = get_conn()?;
    let now = sync_timestamp_now();

    let event = with_immediate_transaction(&conn, |conn| {
        add_event_exception_with_conn(conn, &event_id, &date, &now)
    })?;
    event_bus::emit_data_changed(event_bus::Entity::CalendarEvent);

    Ok(event)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn add_event_exception(event_id: String, date: String) -> Result<CalendarEvent, String> {
    // event ids are UUIDv7 — shape-check at the IPC
    // boundary. The `date` argument has its own (YYYY-MM-DD) shape
    // contract enforced inside `add_event_exception_inner`.
    let event_id_str = crate::commands::shared::validate_uuid_id(&event_id, "event_id")?;
    add_event_exception_inner(EventId::from_trusted(event_id_str), date).map_err(String::from)
}

/// Inverse of `add_event_exception_with_conn`. No renderer-facing
/// Tauri command exposes this — calendar exceptions only flow one way
/// through the UI — but a regression test pins the unwind path:
/// removing a previously-recorded exception must enqueue a fresh
/// upsert with `recurrence_exceptions = NULL`.
#[cfg(test)]
fn remove_event_exception_with_conn(
    conn: &rusqlite::Connection,
    event_id: &EventId,
    date: &str,
    now: &str,
) -> AppResult<CalendarEvent> {
    let version = crate::hlc::generate_version_result()?;

    calendar_event_exceptions::remove_recurrence_exception(conn, event_id, date, &version, now)
        .map_err(AppError::from)?;

    let event = load_calendar_event(conn, event_id.as_str()).map_err(AppError::Internal)?;
    let after = to_json_value(&event)?;
    enqueue_calendar_to_outbox(conn, &event.id, OP_UPSERT, &after)?;

    Ok(event)
}

#[cfg(test)]
mod tests {
    use super::*;

    use crate::test_support::test_conn;
    use rusqlite::params;

    fn setup() -> rusqlite::Connection {
        test_conn()
    }

    fn seed_recurring_event(conn: &rusqlite::Connection, recurrence_exceptions: Option<&str>) {
        conn.execute(
            "INSERT INTO calendar_events (
                id, title, description, recurrence, timezone,
                start_date, start_time, end_date, end_time, all_day, location, color,
                event_type, person_name, version, created_at, updated_at
             ) VALUES (
                '01966a3f-7c8b-7d4e-8f3a-00000000e001', 'Recurring Event', NULL, ?1, 'UTC',
                '2026-03-20', '09:00', '2026-03-20', '09:30', 0, NULL, NULL,
                'event', NULL, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-20T08:00:00Z', '2026-03-20T08:00:00Z'
             )",
            params![r#"{"FREQ":"DAILY","INTERVAL":1}"#],
        )
        .expect("seed recurring calendar event");
        lorvex_store::recurrence_exceptions::replace_event_exceptions_from_json(
            conn,
            "01966a3f-7c8b-7d4e-8f3a-00000000e001",
            recurrence_exceptions,
        )
        .expect("seed exceptions");
    }

    #[test]
    fn add_event_exception_with_conn_enqueues_updated_event_snapshot() {
        let conn = setup();
        seed_recurring_event(&conn, None);

        let event = add_event_exception_with_conn(
            &conn,
            &EventId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000e001".to_string()),
            "2026-03-22",
            "2026-03-22T12:00:00Z",
        )
        .expect("add event exception");

        assert_eq!(
            event.recurrence_exceptions.as_deref(),
            Some(r#"["2026-03-22"]"#)
        );

        let (operation, payload): (String, String) = conn
            .query_row(
                "SELECT operation, payload
                 FROM sync_outbox
                 WHERE entity_type = ?1 AND entity_id = ?2
                 ORDER BY id DESC
                 LIMIT 1",
                params![
                    ENTITY_CALENDAR_EVENT,
                    "01966a3f-7c8b-7d4e-8f3a-00000000e001"
                ],
                |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
            )
            .expect("load calendar event outbox payload");
        let payload: serde_json::Value =
            serde_json::from_str(&payload).expect("calendar event payload should be valid json");

        assert_eq!(operation, OP_UPSERT);
        assert_eq!(payload["id"], "01966a3f-7c8b-7d4e-8f3a-00000000e001");
        assert_eq!(payload["recurrence_exceptions"], r#"["2026-03-22"]"#);
    }

    #[test]
    fn remove_event_exception_with_conn_enqueues_updated_event_snapshot() {
        let conn = setup();
        seed_recurring_event(&conn, Some(r#"["2026-03-22"]"#));

        let event = remove_event_exception_with_conn(
            &conn,
            &EventId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000e001".to_string()),
            "2026-03-22",
            "2026-03-22T12:30:00Z",
        )
        .expect("remove event exception");

        assert_eq!(event.recurrence_exceptions, None);

        let payload: String = conn
            .query_row(
                "SELECT payload
                 FROM sync_outbox
                 WHERE entity_type = ?1 AND entity_id = ?2
                 ORDER BY id DESC
                 LIMIT 1",
                params![
                    ENTITY_CALENDAR_EVENT,
                    "01966a3f-7c8b-7d4e-8f3a-00000000e001"
                ],
                |row| row.get::<_, String>(0),
            )
            .expect("load calendar event outbox payload");
        let payload: serde_json::Value =
            serde_json::from_str(&payload).expect("calendar event payload should be valid json");

        assert!(payload["recurrence_exceptions"].is_null());
    }
}
