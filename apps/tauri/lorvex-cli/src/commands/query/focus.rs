use crate::startup_maintenance::open_db_at_path;
use lorvex_runtime::resolve_db_path;

use crate::cli::OutputFormat;
use crate::commands::mutate::focus::{
    get_focus_schedule_with_conn, load_current_focus_view, load_current_focus_view_for_date,
    propose_focus_schedule_with_conn,
};
use crate::commands::shared::today_ymd_for_conn;
use crate::render::{render_current_focus, render_focus_schedule, render_focus_schedule_proposal};

pub(crate) fn run_focus_show(
    date: Option<&str>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let focus = match date {
        Some(date) => {
            lorvex_domain::validation::validate_date_format(date)?;
            load_current_focus_view_for_date(&conn, date)?
        }
        None => load_current_focus_view(&conn)?,
    };
    let today_ymd = today_ymd_for_conn(&conn)?;
    render_current_focus(focus.as_ref(), &today_ymd, &db_path, format)
}

pub(crate) fn run_focus_schedule_get(
    date: Option<&str>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let schedule = get_focus_schedule_with_conn(&conn, date)?;
    render_focus_schedule(schedule.as_ref(), &db_path, format)
}

pub(crate) fn run_focus_schedule_propose(
    date: Option<&str>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let proposal = propose_focus_schedule_with_conn(&conn, date)?;
    render_focus_schedule_proposal(&proposal, &db_path, format)
}
