//! Tray icon visibility IPC.
//!
//! The hide path runs a preflight that blocks the user from hiding the
//! tray icon while the desktop-close-action preference is set to
//! `hide_to_tray` — losing the tray in that mode would leave no way to
//! re-summon the app after closing the main window.

use crate::db::{get_db, get_read_conn};
use crate::error::{AppError, AppResult};

use crate::commands::diagnostics::append_error_log_internal;

pub(super) fn parse_desktop_close_action_state(
    raw: Option<&str>,
) -> AppResult<Option<&'static str>> {
    let Some(raw) = raw else {
        return Ok(None);
    };
    let parsed = crate::commands::parse_canonical_json_value(raw, "desktop_close_action")?;
    let value = parsed.as_str().ok_or_else(|| {
        AppError::Validation("desktop_close_action must be a JSON string".to_string())
    })?;
    match value {
        "quit" => Ok(Some("quit")),
        "hide_to_tray" => Ok(Some("hide_to_tray")),
        _ => Err(AppError::Validation(format!(
            "desktop_close_action must be 'quit' or 'hide_to_tray'; got '{value}'"
        ))),
    }
}

pub(super) fn load_desktop_close_action_state(
    conn: &rusqlite::Connection,
) -> AppResult<Option<&'static str>> {
    use rusqlite::OptionalExtension;

    let raw: Option<String> = conn
        .query_row(
            "SELECT value FROM device_state WHERE key = ?1",
            rusqlite::params![lorvex_domain::preference_keys::DEV_DESKTOP_CLOSE_ACTION],
            |row| row.get(0),
        )
        .optional()
        .map_err(AppError::from)?;
    parse_desktop_close_action_state(raw.as_deref())
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn set_tray_icon_visibility(app: tauri::AppHandle, visible: bool) -> Result<(), String> {
    #[cfg(desktop)]
    {
        let result = (|| -> AppResult<()> {
            if !visible {
                // pure read of the desktop close-action
                // preference — no mutation, no transaction. Use
                // `get_read_conn` so we don't take the writer mutex
                // and serialize this preflight check behind every
                // pending write.
                let conn = get_read_conn()?;
                let close_action = load_desktop_close_action_state(&conn)?;
                let hide_to_tray_effective = close_action.map_or_else(
                    || {
                        #[cfg(target_os = "macos")]
                        {
                            true
                        }
                        #[cfg(not(target_os = "macos"))]
                        {
                            false
                        }
                    },
                    |value| value == "hide_to_tray",
                );
                if hide_to_tray_effective {
                    return Err(AppError::Validation(
                        "Cannot hide tray icon while desktop close action is hide_to_tray"
                            .to_string(),
                    ));
                }
            }

            let Some(tray) = app.tray_by_id("lorvex-tray") else {
                return Err(AppError::NotFound("Tray icon not initialized".to_string()));
            };
            tray.set_visible(visible)?;
            Ok(())
        })();

        if let Err(error) = result.as_ref() {
            if let Ok(pool) = get_db() {
                if let Ok(conn) = pool.writer_result() {
                    let _ = append_error_log_internal(
                        &conn,
                        "settings.tray_icon",
                        "Tray icon visibility update failed",
                        Some(format!("requested_visible={visible} error={error}")),
                        Some("warn".to_string()),
                    );
                }
            }
        }

        result.map_err(String::from)
    }

    #[cfg(not(desktop))]
    {
        let _ = (app, visible);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::{load_desktop_close_action_state, parse_desktop_close_action_state};
    use crate::error::AppError;
    use rusqlite::hooks::{AuthAction, AuthContext, Authorization};

    use crate::test_support::test_conn;

    fn setup() -> rusqlite::Connection {
        test_conn()
    }

    #[test]
    fn parse_desktop_close_action_state_accepts_canonical_json_string() {
        let parsed = parse_desktop_close_action_state(Some("\"hide_to_tray\""))
            .expect("parse desktop_close_action");
        assert_eq!(parsed, Some("hide_to_tray"));
    }

    #[test]
    fn parse_desktop_close_action_state_rejects_raw_string() {
        let error = parse_desktop_close_action_state(Some("hide_to_tray"))
            .expect_err("raw string should be rejected");
        match error {
            AppError::Serialization(message) => {
                assert!(message.contains("desktop_close_action"));
            }
            other => panic!("expected serialization error, got {other:?}"),
        }
    }

    #[test]
    fn parse_desktop_close_action_state_rejects_unknown_value() {
        let error = parse_desktop_close_action_state(Some("\"something_else\""))
            .expect_err("unknown close action should be rejected");
        match error {
            AppError::Validation(message) => {
                assert!(message.contains("desktop_close_action"));
            }
            other => panic!("expected validation error, got {other:?}"),
        }
    }

    #[test]
    fn load_desktop_close_action_state_surfaces_lookup_failures() {
        let conn = setup();
        conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
            AuthAction::Read {
                table_name: "device_state",
                ..
            } => Authorization::Deny,
            _ => Authorization::Allow,
        }))
        .expect("install authorizer");

        let error = load_desktop_close_action_state(&conn)
            .expect_err("device_state lookup failure should surface");

        match error {
            AppError::Sql(_) => {}
            other => panic!("expected sql error, got {other:?}"),
        }
    }
}
