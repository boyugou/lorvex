use super::*;

// `normalize_blocks_for_sync` was removed. The canonical
// block normalization (provider event_id strip + title neutralize)
// now lives in `lorvex_store::focus_schedule_snapshot::serialize_blocks_for_sync`,
// invoked via `lorvex_sync::payload_build::aggregate::build_aggregate_payload`.
// Anyone reaching for "what blocks ship in a sync envelope?" must go
// through the canonical builder, not a hand-rolled prep step.

/// Build and enqueue a sync event for a focus_schedule (with blocks
/// derived from sub-table). Routes through the canonical
/// aggregate builder so the envelope shape matches the apply pipeline
/// expectation byte-for-byte.
pub(super) fn enqueue_focus_schedule_sync(
    conn: &rusqlite::Connection,
    schedule_date: &str,
) -> AppResult<()> {
    if let Some(payload) = lorvex_sync::payload_build::aggregate::build_aggregate_payload(
        conn,
        ENTITY_FOCUS_SCHEDULE,
        schedule_date,
    )
    .map_err(AppError::from)?
    {
        enqueue_to_outbox_typed(
            conn,
            ENTITY_FOCUS_SCHEDULE,
            schedule_date,
            OP_UPSERT,
            &payload,
        )?;
    }
    Ok(())
}
