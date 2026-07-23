use crate::db::get_read_conn;
use crate::error::{AppError, AppResult};

#[tauri::command]
pub fn export_calendar_ics(from: String, to: String) -> Result<String, String> {
    export_calendar_ics_inner(from, to).map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
fn export_calendar_ics_inner(from: String, to: String) -> AppResult<String> {
    lorvex_domain::validate_export_range(&from, &to)
        .map_err(|error| AppError::Validation(error.to_string()))?;

    let conn = get_read_conn()?;
    let rows = lorvex_store::repositories::calendar_event_export::list_calendar_events_for_ics(
        &conn, &from, &to,
    )?;
    let events: Vec<_> = rows.iter().map(|row| row.as_ics_event()).collect();

    lorvex_domain::export_calendar_ics(&events)
        .map_err(|error| AppError::Validation(error.to_string()))
}
