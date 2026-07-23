//! `apply_calendar_event_delete` — LWW-gated parent delete with a
//! cascade pass over `task_calendar_event_links` (the only synced
//! edge for the calendar_event aggregate).

use rusqlite::Connection;

use lorvex_domain::ids::EventId;

use super::super::super::LwwTieBreak;
use super::super::helpers::{gate_then_cascade_into_outcome, tombstone_composite_edges};
use super::super::{ApplyError, LwwGatedDeleteOutcome};

/// Returns the shared [`super::super::LwwGatedDeleteOutcome`] so the
/// in-handler LWW gate's `Reject` arm surfaces as a typed outcome
/// rather than collapsing into `Ok(())`. A silent no-op DELETE that
/// returned `Ok(())` would let the dispatcher report `Applied` and
/// `apply_envelope` mint a tombstone over the surviving local row.
pub(crate) fn apply_calendar_event_delete(
    conn: &Connection,
    entity_id: &str,
    version: &str,
    apply_ts: &str,
) -> Result<LwwGatedDeleteOutcome, ApplyError> {
    // Issue #3285 phase 3: parse to the typed `EventId` once at the
    // handler entry. Every SQL bind, helper call, and conflict-log
    // write below threads the typed id; the `&str` parameter is
    // preserved only because the dispatch table's fn-pointer type
    // is shared across aggregate handlers.
    let event_id = EventId::from_trusted(entity_id.to_string());
    let event_id_str = event_id.as_str();
    // route through the shared `gate_then_cascade`
    // helper so the LWW gate fires BEFORE the cascade closure can
    // run. See [`super::super::task::apply_task_delete`] for the full
    // rationale;
    // applied here (task_calendar_event_links were tombstoned even
    // when a tainted local `version` would make the byte-compare
    // fallback refuse the parent delete).
    gate_then_cascade_into_outcome(
        conn,
        "SELECT version FROM calendar_events WHERE id = ?1",
        "DELETE FROM calendar_events WHERE id = :id",
        event_id_str,
        version,
        LwwTieBreak::AllowEqual,
        |conn| {
            // task_calendar_event_links — the only synced edge for
            // calendar_event. Attendees + calendar_event_exceptions
            // are device-local projections whose sync is handled
            // via the aggregate payload itself.
            //
            // Borrow `event_id_str` / `version` / `apply_ts` straight
            // from the surrounding scope; the `FnOnce` closure
            // bound on `gate_then_cascade_into_outcome` imposes no
            // `'static` requirement, so the three `to_string()`
            // unnecessary.
            tombstone_composite_edges(
                conn,
                "SELECT task_id, version FROM task_calendar_event_links \
                 WHERE calendar_event_id = ?1",
                event_id_str,
                lorvex_domain::naming::EDGE_TASK_CALENDAR_EVENT_LINK,
                |task_id| format!("{task_id}:{event_id_str}"),
                version,
                apply_ts,
            )
        },
    )
}
