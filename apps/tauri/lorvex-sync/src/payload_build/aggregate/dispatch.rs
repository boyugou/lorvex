//! Dispatcher + registry for the aggregate-payload builder.
//!
//! The closed set of aggregate roots whose canonical sync payload must
//! embed materialized child rows lives here, alongside the typed gate
//! and the dispatch entry point. Each per-aggregate builder lives in a
//! sibling module and is invoked from [`build_aggregate_payload`].

use rusqlite::Connection;
use serde_json::Value;

use lorvex_domain::naming::EntityKind;
use lorvex_store::StoreError;

use super::calendar_event::build_calendar_event_payload;
use super::current_focus::build_current_focus_payload;
use super::daily_review::build_daily_review_payload;
use super::focus_schedule::build_focus_schedule_payload;

/// Entity kinds whose canonical sync payload MUST embed materialized
/// child rows. Used by callers that want to assert "I'm enqueueing an
/// aggregate root with children — did the canonical builder handle
/// it?" — see the debug-assert in
/// `lorvex_sync::outbox_enqueue::read_entity_snapshot`.
pub const AGGREGATE_ROOT_KINDS_WITH_EMBEDDED_CHILDREN: &[EntityKind] = &[
    EntityKind::CurrentFocus,
    EntityKind::FocusSchedule,
    EntityKind::DailyReview,
    EntityKind::CalendarEvent,
];

/// Returns `true` when `kind` is an aggregate root whose sync payload
/// must carry embedded child collection rows. Callers that hold a
/// runtime `&str` should parse via [`EntityKind::parse`] at the
/// boundary and feed the result here.
pub const fn kind_is_aggregate_root_with_embedded_children(kind: EntityKind) -> bool {
    matches!(
        kind,
        EntityKind::CurrentFocus
            | EntityKind::FocusSchedule
            | EntityKind::DailyReview
            | EntityKind::CalendarEvent
    )
}

/// Build the canonical sync payload for an aggregate root.
///
/// Returns:
///
/// * `Ok(Some(Value))` — the entity is one of the registered aggregates
///   whose payload requires child enrichment AND a row was found.
///   Parent header columns + the appropriate child arrays.
/// * `Ok(None)` — either (a) the entity_type is NOT in
///   `AGGREGATE_ROOT_KINDS_WITH_EMBEDDED_CHILDREN` (caller falls back to the
///   bare-columns pragma reader), or (b) the entity_type IS registered
///   but the parent header row is missing for `entity_id`. The two
///   cases are distinguished by `kind_is_aggregate_root_with_embedded_children`.
/// * `Err(_)` — a SQL or serialization failure, OR a `StoreError::Invariant`
///   raised when `entity_type` is registered in
///   `AGGREGATE_ROOT_KINDS_WITH_EMBEDDED_CHILDREN` but no dispatch arm exists
///   below. That second case is a programmer error — adding a new
///   aggregate to the registry without a builder arm will hard-fail on
///   first enqueue rather than silently degrade to the bare-columns
///   reader (the original #2938 bug shape).
///
/// The `entity_id` is the natural key in the parent table:
/// * `current_focus` / `focus_schedule` / `daily_review` — the date.
/// * `calendar_event` — the event UUID.
///
/// This function MUST NOT include a top-level `version` field — the
/// outbox pipeline inserts the canonical envelope `version` at write
/// time. We deliberately omit it here so callers cannot accidentally
/// ship a stale local version; mirroring the bare-columns reader's
/// behavior of writing the `version` column verbatim is incorrect for
/// these aggregates.
///
/// `merge_payload_with_shadow` is **not** invoked here. Aggregate
/// payloads are always sent with the freshly-built header + child
/// columns; forward-compat preservation for these entities lands at
/// the envelope layer (`lorvex_sync::outbox_enqueue::enqueue_payload_*`
/// invokes `merge_payload_with_shadow` against the canonicalized
/// envelope payload before persisting). The export pipeline runs
/// `merge_payload_with_shadow_indexed` per row at write-out time;
/// aggregate-rooted exports therefore pick up shadow extras through
/// the same export-side merge, not through this builder. Callers that
/// produce aggregate payloads outside the export and outbox pipelines
/// must layer the shadow merge themselves.
pub fn build_aggregate_payload(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
) -> Result<Option<Value>, StoreError> {
    // Non-aggregate types are an explicit, well-typed Ok(None) so the
    // caller (e.g. `lorvex_sync::outbox_enqueue::read_entity_snapshot`)
    // can fall through to the bare-columns reader. The registry is the
    // single source of truth for "does this type have embedded children?".
    let Some(kind) = EntityKind::parse(entity_type) else {
        return Ok(None);
    };
    if !kind_is_aggregate_root_with_embedded_children(kind) {
        return Ok(None);
    }
    match kind {
        EntityKind::CurrentFocus => build_current_focus_payload(conn, entity_id),
        EntityKind::FocusSchedule => build_focus_schedule_payload(conn, entity_id),
        EntityKind::DailyReview => build_daily_review_payload(conn, entity_id),
        EntityKind::CalendarEvent => {
            let typed_event_id = lorvex_domain::EventId::from_trusted(entity_id.to_string());
            build_calendar_event_payload(conn, &typed_event_id)
        }
        // this arm is statically unreachable
        // because the `kind_is_aggregate_root_with_embedded_children`
        // gate above narrows `kind` to exactly the four arms enumerated.
        // We still surface the same `StoreError::Invariant` shape
        // Issue #2938 codified — so a future maintainer who widens the
        // registry without extending the dispatch sees a typed,
        // diagnostic error instead of a silent bare-columns fallback.
        other => Err(StoreError::Invariant(format!(
            "entity_type {} is registered in \
             AGGREGATE_ROOT_KINDS_WITH_EMBEDDED_CHILDREN but has no builder arm \
             in build_aggregate_payload — add the dispatch arm before \
             registering a new aggregate root",
            other.as_str()
        ))),
    }
}
