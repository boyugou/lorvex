use crate::contract::ExportCalendarIcsArgs;
use crate::error::McpError;
use rusqlite::Connection;

pub(crate) fn export_calendar_ics(
    conn: &Connection,
    args: ExportCalendarIcsArgs,
) -> Result<String, McpError> {
    let ExportCalendarIcsArgs { from, to } = args;
    lorvex_domain::validate_export_range(&from, &to)
        .map_err(|error| McpError::Validation(error.to_string()))?;

    let rows = lorvex_store::repositories::calendar_event_export::list_calendar_events_for_ics(
        conn, &from, &to,
    )?;
    let events: Vec<_> = rows.iter().map(|row| row.as_ics_event()).collect();

    lorvex_domain::export_calendar_ics(&events)
        .map_err(|error| McpError::UserMessage(format!("Error: {error}")))
}
