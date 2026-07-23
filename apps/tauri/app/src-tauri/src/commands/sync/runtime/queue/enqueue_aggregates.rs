use super::enqueue_core::enqueue_to_outbox_typed;
use super::enqueue_imports::*;

/// rebuild the `current_focus` aggregate payload
/// (header columns + materialized child task_ids) from the live DB row
/// and enqueue an upsert envelope so peers see the rewired plan.
/// Delegates to the canonical aggregate builder shared with every
/// other current_focus enqueue site (seed, MCP changelog funnel, CLI
/// lifecycle).
pub(crate) fn enqueue_current_focus_upsert_for_date(
    conn: &rusqlite::Connection,
    date: &str,
) -> AppResult<()> {
    enqueue_aggregate_root_for_date(conn, ENTITY_CURRENT_FOCUS, date)
}

/// rebuild the `focus_schedule` aggregate payload
/// (header columns + serialized blocks) and enqueue an upsert envelope.
pub(crate) fn enqueue_focus_schedule_upsert_for_date(
    conn: &rusqlite::Connection,
    date: &str,
) -> AppResult<()> {
    enqueue_aggregate_root_for_date(conn, lorvex_domain::naming::ENTITY_FOCUS_SCHEDULE, date)
}

/// Shared core for the `current_focus` and `focus_schedule` date-keyed
/// aggregate enqueues. Both surfaces build the same canonical aggregate
/// payload via [`lorvex_sync::payload_build::aggregate::build_aggregate_payload`]
/// and route through the standard outbox writer.
fn enqueue_aggregate_root_for_date(
    conn: &rusqlite::Connection,
    entity_type: &'static str,
    date: &str,
) -> AppResult<()> {
    debug_assert!(
        lorvex_domain::naming::EntityKind::parse(entity_type).is_some_and(
            lorvex_sync::payload_build::aggregate::kind_is_aggregate_root_with_embedded_children
        ),
        "enqueue_aggregate_root_for_date called with non-aggregate type {entity_type:?}"
    );
    let Some(payload) =
        lorvex_sync::payload_build::aggregate::build_aggregate_payload(conn, entity_type, date)
            .map_err(AppError::from)?
    else {
        // No parent header row for this date — silently skip.
        return Ok(());
    };
    enqueue_to_outbox_typed(conn, entity_type, date, OP_UPSERT, &payload)
}
