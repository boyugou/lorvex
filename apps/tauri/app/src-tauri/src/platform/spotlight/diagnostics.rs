/// persist a Spotlight/Jump-List indexing failure to
/// error_logs so it surfaces in Settings → Diagnostics. Previously
/// every failure went to eprintln! — invisible on macOS release (no
/// console) and on Windows (windows_subsystem=windows). User would
/// search for a task in Spotlight, not find it, and have no trace of
/// why. Open a fresh DB connection on the calling thread (indexing
/// runs fire-and-forget from IPC); fall through to eprintln! only if
/// the DB itself is unreachable.
pub(super) fn log_spotlight_error(context: &str, message: &str) {
    let detail = format!("{context}: {message}");
    if let Ok(conn) = crate::db::get_conn() {
        let _ = crate::commands::diagnostics::append_error_log_internal(
            &conn,
            "platform.spotlight",
            &detail,
            None,
            Some("warn".to_string()),
        );
    }
}

/// a structured one-shot warning with a distinct
/// `source` tag so diagnostics UIs can surface platform-feature-
/// unavailable states separately from transient spotlight errors.
/// Currently only consumed by the Windows Jump List circuit breaker;
/// gate to Windows so macOS doesn't emit dead-code warnings.
#[cfg(target_os = "windows")]
pub(super) fn log_spotlight_warning(source: &str, message: &str) {
    if let Ok(conn) = crate::db::get_conn() {
        let _ = crate::commands::diagnostics::append_error_log_internal(
            &conn,
            source,
            message,
            None,
            Some("warn".to_string()),
        );
    }
}
