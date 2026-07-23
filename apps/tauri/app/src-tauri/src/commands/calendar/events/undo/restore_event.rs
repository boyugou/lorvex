//! Restore path for a deleted calendar event row + every cascaded edge.
//!
//! Re-inserts the canonical row with a freshly-minted HLC version
//! (strictly newer than the delete tombstone), replays every attendee
//! and EXDATE entry the snapshot captured, then re-links every task
//! that still exists locally. Each write emits a fresh upsert envelope
//! so peers under LWW prefer the restored row over the tombstone.

use lorvex_domain::naming::OP_UPSERT;
use lorvex_domain::{AttendeeStatus, EventId, TaskId};
use lorvex_store::repositories::calendar_event_write::CalendarEventCreateParams;
use lorvex_store::repositories::task::calendar_links;
use lorvex_workflow::calendar_event::{materialize_attendees, AttendeeShadowInput};
use rusqlite::params;

use crate::commands::enqueue_calendar_to_outbox;
use crate::commands::enqueue_to_outbox_typed;
use crate::commands::shared::to_json_value;
use crate::error::{AppError, AppResult};

use super::super::{CalendarEvent, CalendarEventAttendee};

/// Restore a calendar event from its pre-delete snapshot. The outer
/// caller (`undo_delete_entity_internal`) wraps this in an immediate
/// transaction so the row + attendees + task links land atomically.
pub(super) fn restore_calendar_event(
    conn: &rusqlite::Connection,
    event: &CalendarEvent,
    linked_task_ids: &[String],
    now: &str,
) -> AppResult<CalendarEvent> {
    // 1. Re-insert the calendar event row with a freshly-minted HLC
    //    version. The HLC generator is monotonic, so this version is
    //    strictly newer than the delete tombstone's version; peers
    //    running LWW therefore keep the restored row.
    let version = crate::hlc::generate_version_result()?;

    // INSERT OR REPLACE so a duplicate undo (or a peer that already
    // restored the row) doesn't fail on PK conflict. We ship a fresh
    // version regardless, so LWW on peers stays correct.
    let recurrence_exceptions = event.recurrence_exceptions.as_deref();
    let create_params = CalendarEventCreateParams {
        id: &event.id,
        title: &event.title,
        description: event.description.as_deref(),
        recurrence: event.recurrence.as_deref(),
        recurrence_exceptions,
        timezone: event.timezone.as_deref(),
        start_date: &event.start_date,
        start_time: event.start_time.as_deref(),
        end_date: event.end_date.as_deref(),
        end_time: event.end_time.as_deref(),
        all_day: event.all_day,
        location: event.location.as_deref(),
        url: event.url.as_deref(),
        color: event.color.as_deref(),
        event_type: event.event_type.as_str(),
        person_name: event.person_name.as_deref(),
        version: &version,
        now,
    };

    // We want INSERT OR REPLACE semantics. The repo helper uses plain
    // INSERT, so route through a direct prepared statement that uses
    // the same column shape. `created_at` must come from the snapshot
    // (the row's original birth-time), not `now` — undo restores the
    // pre-delete row, and rewriting `created_at` to the undo moment
    // (#3434) silently broke "list by oldest" sorts and any
    // analytics/UX that surfaces the original creation moment.
    insert_or_replace_calendar_event(conn, &create_params, &event.created_at)?;

    // Replay the attendee sub-table rows captured in the snapshot.
    // The cascade delete on `calendar_events` already removed every
    // `calendar_event_attendees` row for this event id, so re-inserting
    // the canonical row above leaves the attendee list empty until
    // `materialize_attendees` re-inserts the snapshot list. Without
    // this step undo restored the event headline but silently dropped
    // every invitee (#4582 B2). The materializer expects an outer
    // transaction; `undo_delete_entity_internal` opens an immediate
    // transaction around this whole function, so the contract holds.
    let event_id_typed = EventId::from_trusted(event.id.clone());
    let attendee_inputs: Vec<AttendeeShadowInput> = event
        .attendees
        .as_deref()
        .unwrap_or(&[])
        .iter()
        .map(attendee_projection_to_shadow_input)
        .collect();
    materialize_attendees(conn, &event_id_typed, &attendee_inputs).map_err(|err| {
        AppError::Internal(format!(
            "replay attendees for calendar event {}: {err}",
            event.id
        ))
    })?;

    // Reload to obtain canonical row state (created_at/updated_at).
    let restored =
        super::super::load_calendar_event(conn, &event.id).map_err(AppError::Internal)?;
    let payload = to_json_value(&restored)?;
    enqueue_calendar_to_outbox(conn, &restored.id, OP_UPSERT, &payload)?;

    // 2. Re-link the previously-linked tasks. Each link gets its own
    //    fresh HLC so peers keep them under LWW. Tasks that have since
    //    been deleted locally are silently skipped — the link insert
    //    has a FK to `tasks.id` and would fail otherwise. The typed
    //    event id from the attendee-replay step above is reused
    //    verbatim (the id round-trips through the INSERT OR REPLACE
    //    unchanged).
    for raw_task_id in linked_task_ids {
        let task_exists: bool = conn
            .prepare_cached("SELECT 1 FROM tasks WHERE id = ?1")
            .and_then(|mut stmt| stmt.exists(params![raw_task_id]))
            .map_err(AppError::from)?;
        if !task_exists {
            continue;
        }
        let task_id_typed = TaskId::from_trusted(raw_task_id.clone());
        let link_version = crate::hlc::generate_version_result()?;
        let (link, _applied) =
            calendar_links::insert_link(conn, &task_id_typed, &event_id_typed, &link_version, now)
                .map_err(AppError::from)?;
        let entity_id = format!("{task_id_typed}:{event_id_typed}");
        let link_payload = serde_json::to_value(&link).map_err(AppError::from)?;
        enqueue_to_outbox_typed(
            conn,
            lorvex_domain::naming::EDGE_TASK_CALENDAR_EVENT_LINK,
            &entity_id,
            OP_UPSERT,
            &link_payload,
        )?;
    }

    Ok(restored)
}

/// Lift a snapshot-side [`CalendarEventAttendee`] (the IPC-shaped
/// projection that the read path returns) back into the workflow-side
/// [`AttendeeShadowInput`] the materializer accepts. Non-canonical
/// PARTSTAT spellings on the stored row are coerced through
/// `parse_strict`; an unrecognized status drops to `None` rather than
/// failing the undo, mirroring how every other surface treats stored
/// rows whose status is missing.
fn attendee_projection_to_shadow_input(att: &CalendarEventAttendee) -> AttendeeShadowInput {
    AttendeeShadowInput {
        email: att.email.clone(),
        name: att.name.clone(),
        status: att.status.as_deref().and_then(AttendeeStatus::parse_strict),
    }
}

fn insert_or_replace_calendar_event(
    conn: &rusqlite::Connection,
    p: &CalendarEventCreateParams<'_>,
    created_at: &str,
) -> AppResult<()> {
    // `created_at` is bound from the snapshot's original value so the
    // restored row preserves its birth-time. `updated_at` uses `now` so
    // the row's last-touched moment is the undo. The two columns must
    // be bound via distinct `?17` / `?18` placeholders — sharing one
    // placeholder rewrites `created_at` (#3434).
    conn.prepare_cached(
        "INSERT OR REPLACE INTO calendar_events \
         (id, title, description, recurrence, timezone, \
          start_date, start_time, end_date, end_time, all_day, location, url, color, \
          event_type, person_name, version, created_at, updated_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18)",
    )
    .map_err(AppError::from)?
    .execute(params![
        p.id,
        p.title,
        p.description,
        p.recurrence,
        p.timezone,
        p.start_date,
        p.start_time,
        p.end_date,
        p.end_time,
        i64::from(p.all_day),
        p.location,
        p.url,
        p.color,
        p.event_type,
        p.person_name,
        p.version,
        created_at,
        p.now,
    ])
    .map_err(AppError::from)?;
    // EXDATE registry now lives in
    // `calendar_event_recurrence_exceptions` (#4585) — restore it
    // from the snapshot's wire JSON alongside the parent row.
    lorvex_store::recurrence_exceptions::replace_event_exceptions_from_json(
        conn,
        p.id,
        p.recurrence_exceptions,
    )
    .map_err(AppError::from)?;
    Ok(())
}
