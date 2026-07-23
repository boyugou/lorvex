//! Typed readers and validators for device-local state rows.
//!
//! `device_state` is intentionally local-only, but several runtimes read
//! the same keys. Keep per-key parsing here so Tauri, MCP, and CLI cannot
//! drift on value contracts.

use lorvex_domain::{preference_keys::DEV_CALENDAR_AI_ACCESS_MODE, CalendarAiAccessMode};
use rusqlite::{Connection, OptionalExtension};
use thiserror::Error;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum DeviceStateValueError {
    #[error("device_state '{key}' must contain valid JSON string: {message}")]
    InvalidJson { key: &'static str, message: String },
    #[error("device_state '{key}' must contain a JSON string")]
    ExpectedString { key: &'static str },
    #[error("device_state '{key}' contains invalid value '{value}'")]
    InvalidValue { key: &'static str, value: String },
}

#[derive(Debug, Error)]
pub enum DeviceStateReadError {
    #[error(transparent)]
    Sql(#[from] rusqlite::Error),
    #[error(transparent)]
    Value(#[from] DeviceStateValueError),
}

pub fn validate_calendar_ai_access_mode_json_value(
    value: &serde_json::Value,
) -> Result<CalendarAiAccessMode, DeviceStateValueError> {
    let mode = value
        .as_str()
        .ok_or(DeviceStateValueError::ExpectedString {
            key: DEV_CALENDAR_AI_ACCESS_MODE,
        })?;
    CalendarAiAccessMode::parse_strict(mode).ok_or_else(|| DeviceStateValueError::InvalidValue {
        key: DEV_CALENDAR_AI_ACCESS_MODE,
        value: mode.to_string(),
    })
}

pub fn parse_calendar_ai_access_mode_state(
    raw: &str,
) -> Result<CalendarAiAccessMode, DeviceStateValueError> {
    let parsed: serde_json::Value =
        serde_json::from_str(raw).map_err(|error| DeviceStateValueError::InvalidJson {
            key: DEV_CALENDAR_AI_ACCESS_MODE,
            message: error.to_string(),
        })?;
    validate_calendar_ai_access_mode_json_value(&parsed)
}

/// Read the local `calendar_ai_access_mode` row.
///
/// Missing rows use the domain default (`BusyOnly`). Malformed rows are
/// surfaced as value errors instead of silently falling back, because a bad
/// privacy setting should be fixed at the writer boundary rather than ignored
/// by planning readers.
pub fn read_calendar_ai_access_mode(
    conn: &Connection,
) -> Result<CalendarAiAccessMode, DeviceStateReadError> {
    let raw = conn
        .query_row(
            "SELECT value FROM device_state WHERE key = ?1",
            [DEV_CALENDAR_AI_ACCESS_MODE],
            |row| row.get::<_, String>(0),
        )
        .optional()?;

    raw.map_or_else(
        || Ok(CalendarAiAccessMode::default_mode()),
        |value| parse_calendar_ai_access_mode_state(&value).map_err(DeviceStateReadError::from),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn setup() -> Connection {
        crate::open_db_in_memory().expect("open in-memory db")
    }

    #[test]
    fn read_calendar_ai_access_mode_defaults_when_missing() {
        let conn = setup();

        let mode = read_calendar_ai_access_mode(&conn).expect("read default mode");

        assert_eq!(mode, CalendarAiAccessMode::default_mode());
    }

    #[test]
    fn read_calendar_ai_access_mode_accepts_full_details() {
        let conn = setup();
        conn.execute(
            "INSERT INTO device_state (key, value) VALUES (?1, ?2)",
            [DEV_CALENDAR_AI_ACCESS_MODE, "\"full_details\""],
        )
        .expect("seed full-details mode");

        let mode = read_calendar_ai_access_mode(&conn).expect("read full-details mode");

        assert_eq!(mode, CalendarAiAccessMode::FullDetails);
    }

    #[test]
    fn read_calendar_ai_access_mode_rejects_legacy_allow_deny_values() {
        for legacy_value in ["allow", "deny"] {
            let conn = setup();
            conn.execute(
                "INSERT INTO device_state (key, value) VALUES (?1, ?2)",
                [
                    DEV_CALENDAR_AI_ACCESS_MODE,
                    &serde_json::to_string(legacy_value).expect("serialize legacy value"),
                ],
            )
            .expect("seed legacy mode");

            let error = read_calendar_ai_access_mode(&conn)
                .expect_err("legacy allow/deny values should be rejected");

            assert!(
                error.to_string().contains(legacy_value),
                "unexpected error: {error}"
            );
        }
    }
}
