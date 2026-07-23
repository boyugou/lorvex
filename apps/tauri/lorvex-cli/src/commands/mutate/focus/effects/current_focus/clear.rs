use lorvex_domain::naming::ENTITY_CURRENT_FOCUS;
use lorvex_runtime::{bump_local_change_seq, get_or_create_device_id};
use rusqlite::{Connection, OptionalExtension};

use crate::hlc_guard::lock_shared;
use crate::models::CurrentFocusView;

use super::super::outbox::{
    build_current_focus_aggregate_payload, enqueue_current_focus_payload_delete,
};
use super::queries::load_current_focus_view_for_date;
use crate::commands::shared::{
    log_cli_changelog_with_state, today_ymd_for_conn, validate_calendar_date,
};

/// Returns the focus row that was just cleared (or
/// `None` if nothing was active for `date`). The previous shape
/// returned `()`, which broke symmetry with the sister mutations
/// (`set` / `add` / `remove`) that all return `Option<CurrentFocusView>`
/// — callers that wanted to render the cleared row (or assert on it
/// in tests) had to make a separate `load_current_focus_view` call
/// before invoking clear.
///
/// Do NOT pre-read the focus row outside the transaction the apply
/// opens. The apply captures the pre-state INSIDE the tx and threads
/// it back via `before_focus` so a racing apply on another thread
/// cannot mutate `current_focus` between the read and the apply's
/// tx-begin and leave the caller with a "cleared" row that reflects
/// pre-race state while the actual cleared row is something
/// different.
pub(crate) fn clear_current_focus_with_conn(
    conn: &mut Connection,
    date: Option<&str>,
) -> Result<Option<CurrentFocusView>, crate::error::CliError> {
    let resolved_date = match date {
        Some(date) => {
            validate_calendar_date(date)?;
            date.to_string()
        }
        None => today_ymd_for_conn(conn)?,
    };
    apply_current_focus_clear(conn, &resolved_date)
}

/// dedicated clear path that captures the pre-clear
/// focus row inside the same tx the cascade DELETE runs in, then
/// returns it. This collapses the two-step "read → mutate" pattern
/// the previous shape used into a single atomic operation, closing
/// the race window where a concurrent peer apply could mutate
/// `current_focus` between the read and the mutate.
///
/// Hoist a single `lock_shared` guard for the whole tx so every HLC
/// stamp the clear emits — the tombstone envelope and the
/// audit-changelog row (`log_cli_changelog_with_state`) — share one
/// counter run. Re-locking inside the same tx would interleave this
/// clear's stamps with concurrent CLI writers and produce HLCs that
/// are not strictly-monotonic across the clear's own emissions.
fn apply_current_focus_clear(
    conn: &mut Connection,
    focus_date: &str,
) -> Result<Option<CurrentFocusView>, crate::error::CliError> {
    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    // Pre-clear snapshot, captured inside the immediate tx so a
    // concurrent peer apply cannot interleave between read and delete.
    let before_focus = load_current_focus_view_for_date(&tx, focus_date)?;
    let before_row_present: bool = tx
        .query_row(
            "SELECT 1 FROM current_focus WHERE date = ?1",
            [focus_date],
            |_| Ok(()),
        )
        .optional()?
        .is_some();
    // Short-circuit when there's nothing to clear so the audit
    // trail isn't polluted with a no-op `update` row and the
    // local change seq doesn't bump for a write that never
    // happened. Without this guard the DELETE is a no-op, the
    // outbox enqueue is gated by `before_row_present`, but the
    // changelog row would still claim the focus was cleared.
    if !before_row_present {
        tx.rollback()?;
        return Ok(None);
    }
    let mut hlc_guard = lock_shared(&tx)?;
    // Capture the FULL pre-delete aggregate (header row + child
    // task_ids + computed `tasks` summaries) inside this tx so the
    // tombstone envelope ships peers an actionable payload. Shipping
    // only `{date}` would leave peers that missed the matching upsert
    // with no path to reconstruct briefing/timezone/created_at for
    // restore-from-trash flows.
    let pre_delete_payload = build_current_focus_aggregate_payload(&tx, focus_date)?;
    lorvex_store::current_focus_items::delete_current_focus(&tx, focus_date)?;
    enqueue_current_focus_payload_delete(
        &tx,
        &mut hlc_guard,
        &device_id,
        focus_date,
        &pre_delete_payload,
    )?;
    let before_json = before_focus
        .as_ref()
        .map(serde_json::to_value)
        .transpose()?;
    log_cli_changelog_with_state(
        &tx,
        &mut hlc_guard,
        crate::commands::shared::CliChangelogParams {
            operation: "update",
            entity_type: ENTITY_CURRENT_FOCUS,
            entity_id: focus_date,
            summary: "Cleared current focus",
            before_json,
            after_json: None,
        },
    )?;
    drop(hlc_guard);
    bump_local_change_seq(&tx)?;
    tx.commit()?;
    Ok(before_focus)
}
