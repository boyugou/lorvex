use lorvex_domain::hlc_state::HlcState;
use rusqlite::Connection;

use crate::models::CurrentFocusView;

use super::super::outbox::enqueue_current_focus_payload_upsert;
use super::context::{FocusUpdateContext, CURRENT_FOCUS_TASK_IDS_MAX};
use super::queries::{load_current_focus_view_for_date, validate_focus_task_ids_exist};

pub(super) fn apply_add(
    tx: &Connection,
    hlc_state: &mut HlcState,
    ctx: &FocusUpdateContext<'_>,
    task_ids: Vec<String>,
    briefing: Option<&str>,
) -> Result<Option<CurrentFocusView>, crate::error::CliError> {
    if task_ids.is_empty() {
        return Err(crate::error::CliError::Validation(
            "focus add requires at least one task id".to_string(),
        ));
    }
    validate_focus_task_ids_exist(tx, &task_ids)?;
    let mut merged = ctx
        .before_focus
        .as_ref()
        .map(|focus| focus.task_ids.clone())
        .unwrap_or_default();
    for task_id in task_ids {
        if !merged.contains(&task_id) {
            merged.push(task_id);
        }
    }
    if merged.len() > CURRENT_FOCUS_TASK_IDS_MAX {
        return Err(crate::error::CliError::Validation(format!(
            "current focus would exceed {CURRENT_FOCUS_TASK_IDS_MAX} tasks"
        )));
    }
    let version = hlc_state.generate().to_string();
    match (ctx.before_row_present, briefing.is_some()) {
        (true, false) => {
            lorvex_store::current_focus_items::touch_current_focus_header(
                tx,
                ctx.focus_date,
                Some(&version),
                ctx.now,
            )?;
        }
        _ => {
            lorvex_store::current_focus_items::upsert_current_focus_header(
                tx,
                ctx.focus_date,
                briefing,
                ctx.timezone,
                &version,
                ctx.now,
            )?;
        }
    }
    // route through the parent-bumping helper so every
    // local-write path advances `(version, updated_at)` in lockstep
    // with the rebuilt children.
    lorvex_store::current_focus_items::materialize_focus_items_with_header_bump(
        tx,
        ctx.focus_date,
        &merged,
        &version,
        ctx.now,
    )?;
    let focus = load_current_focus_view_for_date(tx, ctx.focus_date)?
        .ok_or_else(|| std::io::Error::other("failed to load current focus after add"))?;
    enqueue_current_focus_payload_upsert(tx, hlc_state, ctx.device_id, &focus)?;
    Ok(Some(focus))
}
