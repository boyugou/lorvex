#[cfg(target_os = "macos")]
use std::sync::OnceLock;
#[cfg(target_os = "macos")]
use tauri::{AppHandle, Manager};

#[cfg(target_os = "macos")]
static WINDOW_RESTORE_TRACE_ENABLED: OnceLock<bool> = OnceLock::new();

const WINDOW_RESTORE_LOG_SOURCE: &str = "window.restore";

fn append_window_restore_log_with_conn(
    conn: &rusqlite::Connection,
    level: &str,
    message: &str,
    details: Option<String>,
) -> Result<(), String> {
    crate::commands::diagnostics::append_diagnostic_log_with_conn(
        conn,
        WINDOW_RESTORE_LOG_SOURCE,
        level,
        message,
        details,
    )
}

pub(in crate::window_restore) fn append_window_restore_log(
    level: &str,
    message: &str,
    details: Option<String>,
) {
    let Ok(conn) = crate::db::get_conn() else {
        return;
    };
    let _ = append_window_restore_log_with_conn(&conn, level, message, details);
}

#[cfg(target_os = "macos")]
pub(in crate::window_restore) fn append_window_restore_trace(
    message: &str,
    details_builder: impl FnOnce() -> Option<String>,
) {
    if *WINDOW_RESTORE_TRACE_ENABLED.get_or_init(|| {
        std::env::var("LORVEX_WINDOW_RESTORE_TRACE")
            .ok()
            .is_some_and(|value| {
                let normalized = value.trim().to_ascii_lowercase();
                matches!(normalized.as_str(), "1" | "true" | "yes" | "on")
            })
    }) {
        append_window_restore_log("info", message, details_builder());
    }
}

#[cfg(target_os = "macos")]
pub(in crate::window_restore) fn capture_window_restore_snapshot(app: &AppHandle) -> String {
    let describe = |label: &str| {
        if let Some(window) = app.get_webview_window(label) {
            format!(
                "{label}[visible={},minimized={},focused={}]",
                window.is_visible().unwrap_or(false),
                window.is_minimized().unwrap_or(false),
                window.is_focused().unwrap_or(false),
            )
        } else {
            format!("{label}[missing]")
        }
    };
    format!("{} {}", describe("main"), describe("popover"))
}

#[cfg(test)]
mod tests;
