use lorvex_domain::naming::ENTITY_CALENDAR_EVENT;
use lorvex_store::repositories::calendar_event_write;
use lorvex_sync::outbox_enqueue::{
    enqueue_edge_tombstones_for_calendar_event_delete, enqueue_payload_delete, OutboxWriteContext,
};
use serde::Serialize;

use super::undo::{build_undo_token, capture_calendar_event_snapshot};
use super::*;
use crate::commands::get_or_create_sync_device_id_typed;
use crate::commands::with_immediate_transaction;
use crate::error::{AppError, AppResult};
use crate::event_bus;

/// IPC return shape for [`delete_calendar_event`]. Carries the list of
/// tasks unlinked by the cascade (so the caller can refresh affected
/// task rows) plus an opaque `undo_token` that the UI surfaces in a
/// short-lived "Undo" toast (#3392).
#[derive(Debug, Serialize)]
pub struct DeleteCalendarEventResult {
    pub unlinked_task_ids: Vec<String>,
    pub undo_token: String,
}

pub(crate) struct CalendarEventDeleteOutcome {
    pub unlinked_task_ids: Vec<String>,
    pub undo_token: String,
}

pub(crate) fn delete_calendar_event_internal(
    conn: &rusqlite::Connection,
    id: &str,
) -> AppResult<CalendarEventDeleteOutcome> {
    with_immediate_transaction(conn, |conn| delete_calendar_event_with_conn(conn, id))
}

pub(crate) fn delete_calendar_event_with_conn(
    conn: &rusqlite::Connection,
    id: &str,
) -> AppResult<CalendarEventDeleteOutcome> {
    // capture the full pre-delete snapshot (event row +
    // every linked task id) so #3392's snapshot-based undo can
    // restore both the row and its edges if the user clicks Undo
    // within the TTL window.
    let undo_snapshot = capture_calendar_event_snapshot(conn, id)?;

    // capture the FULL pre-delete calendar
    // event row before the FK CASCADE wipes it locally. The DELETE
    // envelope ships the snapshot so peers running LWW have the
    // version + created_at + every field on hand to compare and to
    // populate the changelog `before_json` audit row — the previous
    // shape was `{id}` only, which forced peers into the degenerate
    // "no version" compare branch and lost the snapshot for a peer
    // that had already GC'd its own copy.
    let before_event = load_optional_calendar_event(conn, id).map_err(AppError::Internal)?;

    // tombstone + enqueue DELETE envelopes for every live
    // task_calendar_event_link edge BEFORE the SQLite FK CASCADE wipes
    // them. Without this the cascade is invisible to sync and peers
    // that received the link upsert before the event delete end up
    // with orphaned edge rows.
    // Each edge tombstone gets its own HLC version via the closure so
    // the strictly-monotonic-version invariant holds across the loop;
    // reusing a single `edge_version` across edges would cause peers
    // to drop every tombstone past the first under LWW.
    let device_id = get_or_create_sync_device_id_typed(conn)?;
    let event_id_typed = lorvex_domain::EventId::from_trusted(id.to_string());
    let unlinked_edge_snapshots = enqueue_edge_tombstones_for_calendar_event_delete(
        conn,
        &event_id_typed,
        &device_id,
        #[allow(clippy::result_large_err)] // closure type is fixed by outbox edge tombstone API
        || {
            crate::hlc::generate_version_result().map_err(|err| {
                lorvex_sync::outbox_enqueue::EnqueueError::Store(
                    lorvex_store::error::StoreError::Validation(format!(
                        "generate_version_result failed during edge tombstone enqueue: {err}"
                    )),
                )
            })
        },
    )
    .map_err(|error| {
        AppError::Internal(format!(
            "calendar event delete edge tombstone enqueue failed: {error}"
        ))
    })?;
    let unlinked_task_ids = unlinked_edge_snapshots
        .iter()
        .map(|snapshot| snapshot.task_id.as_str().to_string())
        .collect();

    let payload = match before_event.as_ref() {
        Some(event) => serde_json::to_value(event).map_err(AppError::from)?,
        None => serde_json::json!({ "id": id }),
    };
    let delete_version = crate::hlc::generate_version_result()?;
    calendar_event_write::delete_calendar_event_lww(conn, id, &delete_version)
        .map_err(AppError::from)?;

    enqueue_payload_delete(
        conn,
        ENTITY_CALENDAR_EVENT,
        id,
        &payload,
        OutboxWriteContext {
            version: &delete_version,
            device_id: &device_id,
        },
    )
    .map_err(AppError::from)?;

    let undo_token = build_undo_token(undo_snapshot)?;
    Ok(CalendarEventDeleteOutcome {
        unlinked_task_ids,
        undo_token,
    })
}

pub(crate) fn delete_calendar_event_result_from_outcome(
    outcome: CalendarEventDeleteOutcome,
) -> DeleteCalendarEventResult {
    DeleteCalendarEventResult {
        unlinked_task_ids: outcome.unlinked_task_ids,
        undo_token: outcome.undo_token,
    }
}

fn delete_calendar_event_inner(id: &str) -> AppResult<DeleteCalendarEventResult> {
    let conn = get_conn()?;
    let outcome = delete_calendar_event_internal(&conn, id)?;
    event_bus::emit_data_changed(event_bus::Entity::CalendarEvent);
    Ok(delete_calendar_event_result_from_outcome(outcome))
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn delete_calendar_event(id: String) -> Result<DeleteCalendarEventResult, String> {
    // calendar event ids are UUIDv7 — shape-check at
    // the IPC boundary so a malformed value is refused before the
    // destructive cascade (which tombstones every linked task edge).
    let id = crate::commands::shared::validate_uuid_id(&id, "id")?;
    delete_calendar_event_inner(&id).map_err(String::from)
}

#[cfg(test)]
mod tests {
    //! `delete_calendar_event_internal` ships
    //! a DELETE envelope whose payload is the full pre-delete calendar
    //! event row (version + created_at + title + every field), not the
    //! degenerate `{id}` shape that defeated peer LWW.
    use super::*;
    use crate::test_support::test_conn;
    use rusqlite::params;

    fn seed_calendar_event(conn: &rusqlite::Connection, id: &str, title: &str) {
        conn.execute(
            "INSERT INTO calendar_events
                (id, title, start_date, all_day, version, created_at, updated_at)
             VALUES (?1, ?2, '2026-04-20', 1,
                     '0000000000000_0000_seedcalseedcalse',
                     '2026-04-19T08:00:00Z', '2026-04-19T08:00:00Z')",
            params![id, title],
        )
        .expect("seed calendar event");
    }

    fn read_delete_envelope_payload(
        conn: &rusqlite::Connection,
        entity_id: &str,
    ) -> serde_json::Value {
        let raw: String = conn
            .query_row(
                "SELECT payload FROM sync_outbox \
                 WHERE entity_type = 'calendar_event' AND entity_id = ?1 AND operation = 'delete' \
                 ORDER BY id DESC LIMIT 1",
                params![entity_id],
                |row| row.get(0),
            )
            .expect("load calendar_event delete envelope payload");
        serde_json::from_str(&raw).expect("parse calendar_event delete payload")
    }

    #[test]
    fn delete_calendar_event_internal_ships_full_snapshot_not_id_only_payload() {
        crate::hlc::ensure_hlc_for_test();
        let conn = test_conn();
        let event_id = lorvex_domain::new_entity_id_string();
        seed_calendar_event(&conn, &event_id, "Standup");

        delete_calendar_event_internal(&conn, &event_id).expect("delete should succeed");

        let payload = read_delete_envelope_payload(&conn, &event_id);
        assert!(
            payload.get("version").and_then(|v| v.as_str()).is_some(),
            "payload must carry pre-delete version (got {payload})"
        );
        assert!(
            payload.get("created_at").and_then(|v| v.as_str()).is_some(),
            "payload must carry pre-delete created_at (got {payload})"
        );
        assert_eq!(
            payload.get("title").and_then(|v| v.as_str()),
            Some("Standup"),
            "payload must carry pre-delete title for `before_json` audit"
        );
    }
}
