use rusqlite::Connection;

use super::queries::read_calendar_ai_access_mode;
use crate::commands::shared::anchored_timezone_name_for_conn;
use crate::commands::shared::effects as shared;

pub(crate) fn propose_focus_schedule_with_conn(
    conn: &Connection,
    date: Option<&str>,
) -> Result<lorvex_store::focus_schedule_proposal::FocusScheduleProposal, crate::error::CliError> {
    let schedule_date = shared::resolve_date_or_today(conn, date)?;
    let access_mode = read_calendar_ai_access_mode(conn)?;
    let anchor_tz = anchored_timezone_name_for_conn(conn)?;

    lorvex_store::focus_schedule_proposal::propose_focus_schedule(
        conn,
        &schedule_date,
        &anchor_tz,
        access_mode,
    )
    .map_err(crate::error::CliError::from)
}
