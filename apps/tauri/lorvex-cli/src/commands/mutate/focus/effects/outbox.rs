use lorvex_domain::hlc_state::HlcState;
use lorvex_domain::naming::{ENTITY_CURRENT_FOCUS, ENTITY_FOCUS_SCHEDULE};
use lorvex_sync::outbox_enqueue::enqueue_payload_delete;
use rusqlite::Connection;
use serde_json::json;

use crate::models::{CurrentFocusView, FocusScheduleView};

pub(super) fn enqueue_current_focus_payload_upsert(
    conn: &Connection,
    hlc_state: &mut HlcState,
    device_id: &str,
    focus: &CurrentFocusView,
) -> Result<(), crate::error::CliError> {
    crate::commands::shared::effects::enqueue_aggregate_root_upsert(
        conn,
        hlc_state,
        device_id,
        ENTITY_CURRENT_FOCUS,
        &focus.date,
    )
}

pub(super) fn enqueue_focus_schedule_payload_upsert(
    conn: &Connection,
    hlc_state: &mut HlcState,
    device_id: &str,
    schedule: &FocusScheduleView,
) -> Result<(), crate::error::CliError> {
    crate::commands::shared::effects::enqueue_aggregate_root_upsert(
        conn,
        hlc_state,
        device_id,
        ENTITY_FOCUS_SCHEDULE,
        &schedule.date,
    )
}

/// ship the FULL pre-delete `current_focus`
/// aggregate (header + child task_ids + computed `tasks` summaries)
/// as the tombstone payload.
/// `{date: <date>}`, so peers that missed the matching upsert had
/// no way to reconstruct briefing/timezone/created_at for
/// restore-from-trash flows. Same loss class as #2818 / #2903 /
/// #2928-H1 / #2969-H3 (matching tag rename fix).
///
/// The caller MUST capture the aggregate via
/// `build_current_focus_aggregate_payload` BEFORE the cascade DELETE
/// runs in the same tx — once the row is gone the builder returns
/// `None` and the tombstone would degrade back to the empty shape.
pub(super) fn enqueue_current_focus_payload_delete(
    conn: &Connection,
    hlc_state: &mut HlcState,
    device_id: &str,
    date: &str,
    payload: &serde_json::Value,
) -> Result<(), crate::error::CliError> {
    let version = hlc_state.generate().to_string();
    enqueue_payload_delete(
        conn,
        ENTITY_CURRENT_FOCUS,
        date,
        payload,
        crate::commands::shared::bare_outbox_ctx(&version, device_id),
    )?;
    Ok(())
}

/// build the canonical pre-delete aggregate
/// payload for `current_focus`. Returns the full builder output when
/// the row exists, falls back to a minimal `{"date": …}` when the
/// row vanished (defensive — should not happen since callers capture
/// inside the same tx).
pub(super) fn build_current_focus_aggregate_payload(
    conn: &Connection,
    date: &str,
) -> Result<serde_json::Value, crate::error::CliError> {
    let payload = lorvex_sync::payload_build::aggregate::build_aggregate_payload(
        conn,
        ENTITY_CURRENT_FOCUS,
        date,
    )?;
    Ok(payload.unwrap_or_else(|| json!({ "date": date })))
}
