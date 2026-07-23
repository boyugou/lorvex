//! Helpers for reading device-local state values.

use crate::error::McpError;
use lorvex_domain::CalendarAiAccessMode;
use rusqlite::Connection;

/// Read the `calendar_ai_access_mode` setting from `device_state`.
///
/// Returns `CalendarAiAccessMode::BusyOnly` when the key is absent.
/// Surfaces database failures and malformed stored values instead of silently
/// degrading to a different mode.
pub(crate) fn read_calendar_ai_access_mode(
    conn: &Connection,
) -> Result<CalendarAiAccessMode, McpError> {
    lorvex_store::device_state::read_calendar_ai_access_mode(conn).map_err(|error| match error {
        lorvex_store::device_state::DeviceStateReadError::Sql(error) => {
            McpError::Sql(Box::new(error))
        }
        lorvex_store::device_state::DeviceStateReadError::Value(error) => {
            McpError::Validation(error.to_string())
        }
    })
}

#[cfg(test)]
mod tests;
