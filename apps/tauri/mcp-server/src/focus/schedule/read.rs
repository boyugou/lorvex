use crate::contract::GetSavedFocusScheduleArgs;
use crate::error::McpError;
use crate::focus::schedule::shared::normalize_focus_schedule_row;
use crate::json_row::query_one_as_json;
use crate::system::handler_support::resolve_optional_date;
use rusqlite::Connection;
use serde_json::json;

pub(crate) fn get_saved_focus_schedule(
    conn: &Connection,
    args: GetSavedFocusScheduleArgs,
) -> Result<String, McpError> {
    let date = resolve_optional_date(conn, args.date)?;

    let row = query_one_as_json(
        conn,
        "SELECT * FROM focus_schedule WHERE date = ?",
        [date.clone()],
    )?;

    match row {
        Some(row) => {
            let normalized = normalize_focus_schedule_row(conn, row)?;
            Ok(serde_json::to_string(&normalized)?)
        }
        None => Ok(serde_json::to_string(&json!({
            "date": date,
            "schedule": null,
            "message": format!("No saved focus schedule found for {date}")
        }))?),
    }
}
