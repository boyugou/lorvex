use lorvex_runtime::{bump_local_change_seq, get_or_create_device_id};
use rusqlite::{Connection, OptionalExtension};

use crate::hlc_guard::lock_shared;
use crate::models::CurrentFocusView;

use super::add::apply_add;
use super::context::{CurrentFocusMutation, FocusUpdateContext};
use super::queries::load_current_focus_view_for_date;
use super::remove::apply_remove;
use super::set::apply_set;
use crate::commands::shared::{
    anchored_timezone_name_for_conn, log_cli_changelog_with_state, today_ymd_for_conn,
    validate_calendar_date,
};
use lorvex_domain::naming::ENTITY_CURRENT_FOCUS;

pub(crate) fn set_current_focus_with_conn(
    conn: &mut Connection,
    date: Option<&str>,
    task_ids: &[String],
    briefing: Option<&str>,
) -> Result<CurrentFocusView, crate::error::CliError> {
    apply_current_focus_update(
        conn,
        date,
        CurrentFocusMutation::Set {
            task_ids: task_ids.to_vec(),
            briefing: briefing.map(str::to_string),
        },
    )
    .and_then(|focus| {
        focus.ok_or_else(|| {
            crate::error::CliError::Internal("set_current_focus returned no focus".to_string())
        })
    })
}

pub(crate) fn add_to_current_focus_with_conn(
    conn: &mut Connection,
    date: Option<&str>,
    task_ids: &[String],
    briefing: Option<&str>,
) -> Result<CurrentFocusView, crate::error::CliError> {
    apply_current_focus_update(
        conn,
        date,
        CurrentFocusMutation::Add {
            task_ids: task_ids.to_vec(),
            briefing: briefing.map(str::to_string),
        },
    )
    .and_then(|focus| {
        focus.ok_or_else(|| {
            crate::error::CliError::Internal("add_to_current_focus returned no focus".to_string())
        })
    })
}

pub(crate) fn remove_from_current_focus_with_conn(
    conn: &mut Connection,
    date: Option<&str>,
    task_id: &str,
) -> Result<Option<CurrentFocusView>, crate::error::CliError> {
    apply_current_focus_update(
        conn,
        date,
        CurrentFocusMutation::Remove {
            task_id: task_id.to_string(),
        },
    )
}

fn apply_current_focus_update(
    conn: &mut Connection,
    date: Option<&str>,
    mutation: CurrentFocusMutation,
) -> Result<Option<CurrentFocusView>, crate::error::CliError> {
    let device_id = get_or_create_device_id(conn)?;
    let focus_date = match date {
        Some(date) => {
            validate_calendar_date(date)?;
            date.to_string()
        }
        None => today_ymd_for_conn(conn)?,
    };
    let now = lorvex_domain::sync_timestamp_now();
    // fell back to the numeric offset string
    // ("-08:00" / "+05:30") from `chrono::Local::now().offset()`. App
    // and MCP write IANA names via `anchored_timezone_name`, so
    // `current_focus.timezone` rows diverged across surfaces. Resolve
    // through the shared helper so every writer uses the same IANA
    // identifier.
    let timezone = anchored_timezone_name_for_conn(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;

    let before_focus = load_current_focus_view_for_date(&tx, &focus_date)?;
    let before_row_present: bool = tx
        .query_row(
            "SELECT 1 FROM current_focus WHERE date = ?1",
            [&focus_date],
            |_| Ok(()),
        )
        .optional()?
        .is_some();

    // detect Set mutations whose desired task_ids
    // (post-dedup) match the current `before_focus.task_ids` order
    // exactly AND whose briefing matches the existing one.
    // call like `set_current_focus(today, [a, b], same-briefing)`
    // when the row already held `[a, b]` with that briefing burned a
    // changelog row, an outbox envelope, and a `local_change_seq`
    // bump for a write that did not change observable state.
    if let CurrentFocusMutation::Set { task_ids, briefing } = &mutation {
        if let Some(existing) = before_focus.as_ref() {
            let mut deduped = task_ids.clone();
            deduped.dedup();
            if existing.task_ids == deduped && existing.briefing == *briefing {
                tx.rollback()?;
                return Ok(Some(existing.clone()));
            }
        }
    }

    let focus_changelog_summary = match &mutation {
        CurrentFocusMutation::Set { task_ids, .. } => {
            format!("Set current focus ({} tasks)", task_ids.len())
        }
        CurrentFocusMutation::Add { task_ids, .. } => {
            format!("Added {} task(s) to current focus", task_ids.len())
        }
        CurrentFocusMutation::Remove { task_id } => {
            format!("Removed task {task_id} from current focus")
        }
    };

    let ctx = FocusUpdateContext {
        device_id: &device_id,
        focus_date: &focus_date,
        timezone: &timezone,
        now: &now,
        before_focus,
        before_row_present,
    };
    // snapshot the pre-mutation focus before
    // `ctx.before_focus` is moved into the helpers.
    let before_json = ctx
        .before_focus
        .as_ref()
        .map(serde_json::to_value)
        .transpose()?;
    // hoist a single `lock_shared` guard for the
    // whole tx so every helper (`apply_set` / `apply_add` /
    // `apply_remove`) plus their inner outbox enqueues plus the audit
    // changelog all mint HLCs from the same counter run.
    // each helper re-acquired the process-wide HLC mutex through
    // `next_hlc_version`, so a concurrent CLI writer could interleave
    // counter values within the same focus mutation; the resulting
    // envelopes did not sort strictly-monotonically on peers.
    let mut hlc_guard = lock_shared(&tx)?;
    let after_focus = match mutation {
        CurrentFocusMutation::Set { task_ids, briefing } => {
            apply_set(&tx, &mut hlc_guard, &ctx, task_ids, briefing.as_deref())?
        }
        CurrentFocusMutation::Add { task_ids, briefing } => {
            apply_add(&tx, &mut hlc_guard, &ctx, task_ids, briefing.as_deref())?
        }
        CurrentFocusMutation::Remove { task_id } => {
            apply_remove(&tx, &mut hlc_guard, &ctx, &task_id)?
        }
    };
    let after_json = after_focus.as_ref().map(serde_json::to_value).transpose()?;

    log_cli_changelog_with_state(
        &tx,
        &mut hlc_guard,
        crate::commands::shared::CliChangelogParams {
            operation: "update",
            entity_type: ENTITY_CURRENT_FOCUS,
            entity_id: &focus_date,
            summary: &focus_changelog_summary,
            before_json,
            after_json,
        },
    )?;
    drop(hlc_guard);

    bump_local_change_seq(&tx)?;
    tx.commit()?;
    Ok(after_focus)
}
