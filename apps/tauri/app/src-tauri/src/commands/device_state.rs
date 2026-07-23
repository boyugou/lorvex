use crate::db::{get_conn, get_read_conn};
use crate::error::{AppError, AppResult};
use lorvex_domain::validation::{KV_KEY_MAX_CHARS, KV_VALUE_MAX_BYTES};
use lorvex_runtime::bump_local_change_seq;
use rusqlite::params;

use super::{with_immediate_transaction, OptionalExt};

fn validate_device_state_inputs(key: &str, value: &str) -> AppResult<()> {
    if key.is_empty() {
        return Err(AppError::Validation(
            "device_state key must not be empty".to_string(),
        ));
    }
    let key_char_count = key.chars().count();
    if key_char_count > KV_KEY_MAX_CHARS {
        return Err(AppError::Validation(format!(
            "device_state key length {} exceeds maximum {KV_KEY_MAX_CHARS}",
            key_char_count
        )));
    }
    if value.len() > KV_VALUE_MAX_BYTES {
        return Err(AppError::Validation(format!(
            "device_state value length {} exceeds maximum {KV_VALUE_MAX_BYTES}",
            value.len()
        )));
    }
    Ok(())
}

fn validate_device_state_value_for_key(key: &str, value: &serde_json::Value) -> AppResult<()> {
    if key == lorvex_domain::preference_keys::DEV_CALENDAR_AI_ACCESS_MODE {
        lorvex_store::device_state::validate_calendar_ai_access_mode_json_value(value)
            .map_err(|error| AppError::Validation(error.to_string()))?;
    }
    Ok(())
}

fn get_device_state_with_conn(conn: &rusqlite::Connection, key: &str) -> AppResult<Option<String>> {
    conn.prepare_cached("SELECT value FROM device_state WHERE key = ?1")
        .map_err(AppError::from)?
        .query_row(params![key], |row| row.get::<_, String>(0))
        .optional()
        .map_err(AppError::from)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn get_device_state(key: String) -> Result<Option<String>, String> {
    let conn = get_read_conn()?;
    get_device_state_with_conn(&conn, &key).map_err(String::from)
}

fn set_device_state_with_conn(
    conn: &rusqlite::Connection,
    key: &str,
    value: &str,
) -> AppResult<()> {
    validate_device_state_inputs(key, value)?;
    let parsed = crate::commands::parse_canonical_json_value(value, "device_state value")?;
    if parsed.is_null() {
        conn.prepare_cached("DELETE FROM device_state WHERE key = ?1")
            .map_err(AppError::from)?
            .execute(params![key])
            .map_err(AppError::from)?;
        return Ok(());
    }
    validate_device_state_value_for_key(key, &parsed)?;

    let canonical_value = serde_json::to_string(&parsed).map_err(AppError::from)?;

    conn.prepare_cached(
        "INSERT INTO device_state (key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = ?2",
    )
    .map_err(AppError::from)?
    .execute(params![key, canonical_value])
    .map_err(AppError::from)?;

    Ok(())
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn set_device_state(key: String, value: String) -> Result<(), String> {
    let conn = get_conn()?;
    // bundle the upsert + `bump_local_change_seq` into a
    // single transaction so a sibling MCP writer can't observe the
    // changed-seq tick without the row that triggered it (or vice versa).
    with_immediate_transaction(&conn, |conn| -> AppResult<()> {
        set_device_state_with_conn(conn, &key, &value)?;
        bump_local_change_seq(conn).map_err(AppError::from)?;
        Ok(())
    })
    .map_err(String::from)?;
    crate::event_bus::emit_data_changed(crate::event_bus::Entity::Preference);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    use crate::test_support::test_conn;

    fn setup() -> rusqlite::Connection {
        test_conn()
    }

    #[test]
    fn set_device_state_with_conn_clears_existing_row_on_json_null() {
        let conn = setup();
        conn.execute(
            "INSERT INTO device_state (key, value) VALUES ('transient_panel_state', '{\"open\":true}')",
            [],
        )
        .expect("seed device_state row");

        set_device_state_with_conn(&conn, "transient_panel_state", "null")
            .expect("clear device state row");

        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM device_state WHERE key = 'transient_panel_state'",
                [],
                |row| row.get(0),
            )
            .expect("count device_state rows after clear");
        assert_eq!(count, 0);
    }

    #[test]
    fn set_device_state_with_conn_rejects_malformed_json_value() {
        let conn = setup();

        let error = set_device_state_with_conn(&conn, "calendar_ai_access_mode", "{bad-json")
            .expect_err("malformed device_state json should be rejected");

        match error {
            AppError::Serialization(message) => {
                assert!(
                    message.contains("device_state value"),
                    "unexpected serialization error: {message}"
                );
            }
            other => panic!("expected serialization error, got {other:?}"),
        }
    }

    #[test]
    fn set_device_state_with_conn_stores_canonical_json_value() {
        let conn = setup();

        set_device_state_with_conn(&conn, "calendar_ai_access_mode", " \n \"full_details\" \n ")
            .expect("store device_state value");

        let stored: String = conn
            .query_row(
                "SELECT value FROM device_state WHERE key = 'calendar_ai_access_mode'",
                [],
                |row| row.get(0),
            )
            .expect("load stored device_state");
        assert_eq!(stored, "\"full_details\"");
    }

    #[test]
    fn set_device_state_with_conn_counts_key_limit_as_chars() {
        let conn = setup();
        let key = "é".repeat(lorvex_domain::validation::KV_KEY_MAX_CHARS);

        set_device_state_with_conn(&conn, &key, "true")
            .expect("multibyte key at the character limit should be accepted");

        let stored: String = conn
            .query_row(
                "SELECT value FROM device_state WHERE key = ?1",
                [&key],
                |row| row.get(0),
            )
            .expect("load stored multibyte device_state key");
        assert_eq!(stored, "true");
    }

    #[test]
    fn set_device_state_with_conn_rejects_values_over_byte_limit() {
        let conn = setup();
        let value = format!(
            "\"{}\"",
            "x".repeat(lorvex_domain::validation::KV_VALUE_MAX_BYTES)
        );

        let error = set_device_state_with_conn(&conn, "transient_panel_state", &value)
            .expect_err("device_state values over the byte limit should be rejected");

        match error {
            AppError::Validation(message) => assert!(
                message.contains("device_state value") && message.contains("exceeds maximum"),
                "unexpected validation error: {message}"
            ),
            other => panic!("expected validation error, got {other:?}"),
        }
    }

    #[test]
    fn set_device_state_with_conn_rejects_invalid_calendar_ai_access_mode_values() {
        let conn = setup();

        for value in ["\"allow\"", "\"deny\""] {
            let error = set_device_state_with_conn(&conn, "calendar_ai_access_mode", value)
                .expect_err("invalid calendar_ai_access_mode should be rejected");
            let message = error.to_string();
            assert!(
                message.contains("calendar_ai_access_mode"),
                "unexpected error for {value}: {message}"
            );
        }

        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM device_state WHERE key = 'calendar_ai_access_mode'",
                [],
                |row| row.get(0),
            )
            .expect("count rejected calendar_ai_access_mode rows");
        assert_eq!(count, 0);
    }
}
