use lorvex_domain::hlc_state::HlcState;
use rusqlite::Connection;

use crate::models::CurrentFocusView;

use super::super::outbox::enqueue_current_focus_payload_upsert;
use super::context::{FocusUpdateContext, CURRENT_FOCUS_TASK_IDS_MAX};
use super::queries::{load_current_focus_view_for_date, validate_focus_task_ids_exist};

pub(super) fn apply_set(
    tx: &Connection,
    hlc_state: &mut HlcState,
    ctx: &FocusUpdateContext<'_>,
    mut task_ids: Vec<String>,
    briefing: Option<&str>,
) -> Result<Option<CurrentFocusView>, crate::error::CliError> {
    task_ids.dedup();
    if task_ids.is_empty() || task_ids.len() > CURRENT_FOCUS_TASK_IDS_MAX {
        return Err(crate::error::CliError::Validation(format!(
            "focus set requires between 1 and {CURRENT_FOCUS_TASK_IDS_MAX} task ids"
        )));
    }
    validate_focus_task_ids_exist(tx, &task_ids)?;
    let version = hlc_state.generate().to_string();
    lorvex_store::current_focus_items::upsert_current_focus_header(
        tx,
        ctx.focus_date,
        briefing,
        ctx.timezone,
        &version,
        ctx.now,
    )?;
    // route through the parent-bumping helper so every
    // local-write path advances `(version, updated_at)` in lockstep
    // with the rebuilt children.
    lorvex_store::current_focus_items::materialize_focus_items_with_header_bump(
        tx,
        ctx.focus_date,
        &task_ids,
        &version,
        ctx.now,
    )?;
    let focus = load_current_focus_view_for_date(tx, ctx.focus_date)?
        .ok_or_else(|| std::io::Error::other("failed to load current focus after set"))?;
    enqueue_current_focus_payload_upsert(tx, hlc_state, ctx.device_id, &focus)?;
    Ok(Some(focus))
}
