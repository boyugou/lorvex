pub(super) use crate::{
    commands::hide_popover_window,
    db,
    desktop_close_policy::{resolve_desktop_close_action, DesktopCloseAction},
    tray_geometry::{
        clamp_tray_popover_position_to_monitor, find_monitor_containing_physical_point,
        rect_to_physical_bounds, TRAY_POPOVER_LOGICAL_WIDTH, TRAY_POPOVER_LOGICAL_X_MARGIN,
        TRAY_POPOVER_LOGICAL_Y_MARGIN,
    },
    window_restore::{focus_main_window, focus_primary_window},
    window_space::{apply_auxiliary_window_space_state, AuxiliaryWindowKind, AuxiliaryWindowState},
};
pub(super) use tauri::{
    menu::{MenuBuilder, MenuItemBuilder},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Emitter, Manager,
};

pub(super) const DESKTOP_SHELL_LOG_SOURCE: &str = "desktop_shell";

pub(super) fn append_desktop_shell_log_with_conn(
    conn: &rusqlite::Connection,
    level: &str,
    source_suffix: &str,
    message: &str,
    details: Option<String>,
) -> Result<(), String> {
    let source = compose_desktop_shell_source(source_suffix);
    crate::commands::diagnostics::append_diagnostic_log_with_conn(
        conn, &source, level, message, details,
    )
}

pub(super) fn append_desktop_shell_log(
    level: &str,
    source_suffix: &str,
    message: &str,
    details: Option<String>,
) {
    let Ok(conn) = db::get_conn() else {
        return;
    };
    let _ = append_desktop_shell_log_with_conn(&conn, level, source_suffix, message, details);
}

fn compose_desktop_shell_source(source_suffix: &str) -> String {
    if source_suffix.trim().is_empty() {
        DESKTOP_SHELL_LOG_SOURCE.to_string()
    } else {
        format!("{DESKTOP_SHELL_LOG_SOURCE}.{source_suffix}")
    }
}

mod app_menu;
mod popover;
mod tray;

pub(crate) use app_menu::{build_app_menu, handle_menu_event};
pub(crate) use popover::{
    hide_auxiliary_desktop_windows, install_popover_close_to_hide,
    install_popover_dismiss_on_main_focus,
};
pub(crate) use tray::setup_system_tray;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::test_conn;

    #[test]
    fn append_desktop_shell_log_with_conn_persists_structured_diagnostic() {
        let conn = test_conn();

        append_desktop_shell_log_with_conn(
            &conn,
            "Warning",
            "tray.popover_show",
            "Desktop shell diagnostic token=message-secret",
            Some("stage=test token=details-secret".to_string()),
        )
        .expect("append desktop shell diagnostic");

        let row: (String, String, String, Option<String>) = conn
            .query_row(
                "SELECT source, level, message, details FROM error_logs",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .expect("read diagnostic row");

        assert_eq!(row.0, "desktop_shell.tray.popover_show");
        assert_eq!(row.1, "warn");
        assert_eq!(row.2, "Desktop shell diagnostic token=[REDACTED]");
        assert_eq!(row.3.as_deref(), Some("stage=test token=[REDACTED]"));
    }
}
