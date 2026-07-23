use lorvex_domain::hlc_state::HlcState;
use rusqlite::Connection;

use crate::models::CurrentFocusView;

use super::super::outbox::{
    build_current_focus_aggregate_payload, enqueue_current_focus_payload_delete,
    enqueue_current_focus_payload_upsert,
};
use super::context::FocusUpdateContext;
use super::queries::load_current_focus_view_for_date;

pub(super) fn apply_remove(
    tx: &Connection,
    hlc_state: &mut HlcState,
    ctx: &FocusUpdateContext<'_>,
    task_id: &str,
) -> Result<Option<CurrentFocusView>, crate::error::CliError> {
    // surface "no current focus row for this date" as
    // a typed `CliError::NotFound` so the exit code is 66 (EX_NOINPUT)
    // instead of the IO-class 74 produced by `io::Error::other`.
    let existing = ctx.before_focus.as_ref().ok_or_else(|| {
        crate::error::CliError::NotFound(format!("no current focus exists for {}", ctx.focus_date))
    })?;
    let mut remaining = existing.task_ids.clone();
    let original_len = remaining.len();
    remaining.retain(|value| value != task_id);
    if remaining.len() == original_len {
        return Err(crate::error::CliError::NotFound(format!(
            "task '{task_id}' is not in current focus for {}",
            ctx.focus_date
        )));
    }
    if remaining.is_empty() {
        // capture the pre-delete aggregate before
        // the cascade runs so the tombstone payload carries the full
        // header + children — see `enqueue_current_focus_payload_delete`.
        let pre_delete_payload = build_current_focus_aggregate_payload(tx, ctx.focus_date)?;
        lorvex_store::current_focus_items::delete_current_focus(tx, ctx.focus_date)?;
        enqueue_current_focus_payload_delete(
            tx,
            hlc_state,
            ctx.device_id,
            ctx.focus_date,
            &pre_delete_payload,
        )?;
        Ok(None)
    } else {
        // bumping `(version, updated_at)` together with
        // the child rebuild keeps peer LWW gates in sync after a
        // remove. The previous `touch_current_focus_header(..., None,
        // ...)` left `version` stale and the rebuilt children
        // disagreed with the parent.
        let version = hlc_state.generate().to_string();
        lorvex_store::current_focus_items::materialize_focus_items_with_header_bump(
            tx,
            ctx.focus_date,
            &remaining,
            &version,
            ctx.now,
        )?;
        let focus = load_current_focus_view_for_date(tx, ctx.focus_date)?
            .ok_or_else(|| std::io::Error::other("failed to load current focus after remove"))?;
        enqueue_current_focus_payload_upsert(tx, hlc_state, ctx.device_id, &focus)?;
        Ok(Some(focus))
    }
}
