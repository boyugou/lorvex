use crate::startup_maintenance::open_db_at_path;
use lorvex_runtime::resolve_db_path;
use serde_json::json;

use crate::cli::OutputFormat;
use crate::commands::shared::render_mutation_envelope;
use crate::commands::shared::today_ymd_for_conn;
use crate::render::{render_current_focus, render_focus_cleared, render_focus_schedule};

pub(crate) mod effects;
pub(crate) use effects::{
    add_to_current_focus_with_conn, clear_current_focus_with_conn, get_focus_schedule_with_conn,
    load_current_focus_view, load_current_focus_view_for_date, propose_focus_schedule_with_conn,
    remove_from_current_focus_with_conn, save_focus_schedule_with_conn,
    set_current_focus_with_conn,
};

pub(crate) fn run_focus_set(
    date: Option<&str>,
    task_ids: &[String],
    briefing: Option<&str>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let focus = set_current_focus_with_conn(&mut conn, date, task_ids, briefing)?;
    let today_ymd = today_ymd_for_conn(&conn)?;
    match format {
        OutputFormat::Text => render_current_focus(Some(&focus), &today_ymd, &db_path, format),
        // canonical mutation envelope.
        OutputFormat::Json => {
            render_mutation_envelope("focus.set", &db_path, json!({ "current_focus": focus }))
        }
    }
}

pub(crate) fn run_focus_add(
    date: Option<&str>,
    task_ids: &[String],
    briefing: Option<&str>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let focus = add_to_current_focus_with_conn(&mut conn, date, task_ids, briefing)?;
    let today_ymd = today_ymd_for_conn(&conn)?;
    match format {
        OutputFormat::Text => render_current_focus(Some(&focus), &today_ymd, &db_path, format),
        // canonical mutation envelope.
        OutputFormat::Json => {
            render_mutation_envelope("focus.add", &db_path, json!({ "current_focus": focus }))
        }
    }
}

pub(crate) fn run_focus_remove(
    date: Option<&str>,
    task_id: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let focus = remove_from_current_focus_with_conn(&mut conn, date, task_id)?;
    let today_ymd = today_ymd_for_conn(&conn)?;
    match format {
        OutputFormat::Text => render_current_focus(focus.as_ref(), &today_ymd, &db_path, format),
        // canonical mutation envelope. `current_focus`
        // is `null` when the removal emptied the day's focus row.
        OutputFormat::Json => {
            render_mutation_envelope("focus.remove", &db_path, json!({ "current_focus": focus }))
        }
    }
}

pub(crate) fn run_focus_clear(
    date: Option<&str>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    // clear now returns the pre-clear focus row (if any)
    // so callers can surface what was just removed. Sister mutations
    // (`set_current_focus_with_conn`, `add_to_current_focus_with_conn`)
    // already returned the updated row; clear was the asymmetric
    // outlier that returned `()`.
    let cleared = clear_current_focus_with_conn(&mut conn, date)?;
    let today_ymd = today_ymd_for_conn(&conn)?;
    match format {
        // Text uses the dedicated cleared renderer so the user sees
        // "Cleared focus for <date>" instead of the generic
        // "no focus today" line that `render_current_focus(None, ...)`
        // would print.
        OutputFormat::Text => render_focus_cleared(cleared.as_ref(), &today_ymd, &db_path, format),
        // canonical mutation envelope. `current_focus`
        // is null after the clear; the pre-clear row is surfaced under
        // `cleared_focus` so scripts can audit what was removed.
        OutputFormat::Json => render_mutation_envelope(
            "focus.clear",
            &db_path,
            json!({
                "current_focus": serde_json::Value::Null,
                "cleared_focus": cleared,
            }),
        ),
    }
}

pub(crate) fn run_focus_schedule_save(
    date: Option<&str>,
    blocks_json: &str,
    rationale: Option<&str>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let schedule = save_focus_schedule_with_conn(&mut conn, date, blocks_json, rationale)?;
    match format {
        OutputFormat::Text => render_focus_schedule(Some(&schedule), &db_path, format),
        // canonical mutation envelope.
        OutputFormat::Json => render_mutation_envelope(
            "focus.schedule.save",
            &db_path,
            json!({ "focus_schedule": schedule }),
        ),
    }
}
