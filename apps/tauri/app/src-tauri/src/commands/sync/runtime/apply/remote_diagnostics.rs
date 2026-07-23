use super::ApplyRemoteSyncResult;

pub(super) fn duration_ms_saturating(duration: std::time::Duration) -> i64 {
    i64::try_from(duration.as_millis()).unwrap_or(i64::MAX)
}

pub(super) fn record_sync_apply_cycle_best_effort(
    _conn: &rusqlite::Connection,
    _started_at: &str,
    _completed_at: &str,
    _duration_ms: i64,
    _received: i64,
    _result: Option<&ApplyRemoteSyncResult>,
    _error: Option<&str>,
) {
}

pub(super) fn persist_sync_apply_runtime_warning(
    conn: &rusqlite::Connection,
    source: &str,
    message: &str,
    details: impl Into<String>,
) {
    let _ = crate::commands::diagnostics::append_error_log_internal(
        conn,
        source,
        message,
        Some(details.into()),
        Some("warn".to_string()),
    );
}
