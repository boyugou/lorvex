use crate::contract::ProposeDailyScheduleArgs;
use crate::error::McpError;
use crate::runtime::cancellation::check_cancelled;
use crate::system::handler_support::{read_calendar_ai_access_mode, resolve_optional_date};
use lorvex_workflow::timezone::active_timezone_name;
use rusqlite::Connection;
use tokio_util::sync::CancellationToken;

pub(crate) fn propose_daily_schedule(
    conn: &Connection,
    args: ProposeDailyScheduleArgs,
    ct: &CancellationToken,
) -> Result<String, McpError> {
    let ProposeDailyScheduleArgs { date } = args;

    // Keep MCP cancellation around the DB-heavy shared planner without
    // duplicating the planner's slot/block algorithm in this crate.
    check_cancelled(ct)?;
    let date = resolve_optional_date(conn, date)?;
    let access_mode = read_calendar_ai_access_mode(conn)?;
    let anchor_tz = active_timezone_name(conn)?;
    let anchor_tz_str = anchor_tz.as_deref().unwrap_or("UTC");

    check_cancelled(ct)?;
    let proposal = lorvex_store::focus_schedule_proposal::propose_focus_schedule(
        conn,
        &date,
        anchor_tz_str,
        access_mode,
    )?;
    check_cancelled(ct)?;

    Ok(serde_json::to_string_pretty(&proposal)?)
}
