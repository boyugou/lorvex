use crate::commands::sync_timestamp_now;
use crate::db::{get_conn, get_read_conn};
use crate::error::{AppError, AppResult};
use lorvex_domain::preference_keys::DEV_ERROR_LOGS_LAST_VIEWED_AT;
use rusqlite::params;
use serde::{Deserialize, Serialize};

use super::super::shared::{clamp_limit, rows_from_query, MAX_ERROR_LOG_LIMIT};
use super::super::OptionalExt;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ErrorLogEntry {
    pub id: String,
    pub source: String,
    pub level: String,
    pub message: String,
    pub details: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ClearErrorLogsResult {
    pub deleted: usize,
}

/// structured replacement for `eprintln!` in
/// best-effort cleanup paths (popover dismiss, auxiliary window hide,
/// etc.). Acquires a DB connection, writes one row to `error_logs`,
/// and silently swallows any failure — the caller has no way to
/// recover from a logging failure during a UI-side cleanup, but
/// neither do we want the diagnostic to vanish into stderr where
/// production builds discard it.
///
/// Use this from `Drop` impls, panic handlers, and any code path
/// where `?` propagation would be wrong but losing the diagnostic
/// would also be wrong.
pub(crate) fn append_error_log_best_effort(
    source: &str,
    message: &str,
    details: Option<String>,
    level: Option<String>,
) {
    let Ok(conn) = get_conn() else {
        // DB pool is unreachable (early startup, post-shutdown). The
        // diagnostic is lost, but a stderr write would also be lost in
        // a release bundle; nothing to do.
        return;
    };
    let _ = append_error_log_internal(&conn, source, message, details, level);
}

pub(crate) fn try_append_error_log_best_effort(
    source: &str,
    message: &str,
    details: Option<String>,
    level: Option<String>,
) {
    let Ok(Some(conn)) = crate::db::try_get_conn() else {
        // The writer may already be held by the command whose error
        // is being converted into an IPC response. This path must not
        // block or re-enter the writer mutex, otherwise the diagnostic
        // logger can prevent the original error from reaching Tauri.
        return;
    };
    let _ = append_error_log_internal(&conn, source, message, details, level);
}

/// Typed-level wrapper around [`append_error_log_internal`] that
/// matches the per-module `append_*_log_with_conn` signature most
/// callers want: source, typed level, message, optional details.
///
/// the per-module wrappers (`menu_i18n`,
/// `desktop_close_policy`, `runtime_status`, `window_restore`,
/// `desktop_shell`, `deep_link`) all open-coded
/// `Some(level.to_string())` plus
/// the same source/message/details forwarding. Drift hazard:
/// `append_error_log_internal`'s signature couldn't change
/// without touching every wrapper. This helper centralizes that
/// shape; per-module wrappers shrink to one-line delegations that
/// only carry the local `*_LOG_SOURCE` constant.
pub(crate) fn append_diagnostic_log_with_conn(
    conn: &rusqlite::Connection,
    source: &str,
    level: &str,
    message: &str,
    details: Option<String>,
) -> Result<(), String> {
    append_error_log_internal(conn, source, message, details, Some(level.to_string()))
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
pub(crate) fn append_error_log_internal(
    conn: &rusqlite::Connection,
    source: &str,
    message: &str,
    details: Option<String>,
    level: Option<String>,
) -> Result<(), String> {
    // Delegate to the canonical store-layer writer so redaction +
    // truncation contracts stay uniform across CLI, Tauri,
    // mcp-server, and lorvex-sync. This wrapper exists only to map
    // the shared rusqlite::Error into the App-surface String shape
    // that Tauri commands return.
    lorvex_store::error_log::append_error_log(
        conn,
        source,
        message,
        details.as_deref(),
        level.as_deref(),
    )
    .map_err(|e| format!("error_logs append failed: {e}"))
}

pub(crate) fn read_error_logs(
    conn: &rusqlite::Connection,
    limit: Option<i64>,
    since_iso: Option<&str>,
) -> AppResult<Vec<ErrorLogEntry>> {
    let lim = clamp_limit(limit, 200, 1, MAX_ERROR_LOG_LIMIT);
    let since_trimmed = since_iso.map(str::trim).filter(|s| !s.is_empty());
    // time-window filter: when `since_iso` is supplied,
    // restrict results to rows with `created_at >= since_iso`. Both
    // values are RFC3339 UTC written by `sync_timestamp_now()`, so
    // lexicographic comparison is correct. Invalid / empty values are
    // silently dropped — a filter only narrows the view.
    if let Some(since) = since_trimmed {
        rows_from_query(
            conn,
            "SELECT id, source, level, message, details, created_at
             FROM error_logs
             WHERE created_at >= ?1
             ORDER BY created_at DESC
             LIMIT ?2",
            params![since, lim],
            error_log_row_mapper,
        )
    } else {
        rows_from_query(
            conn,
            "SELECT id, source, level, message, details, created_at
             FROM error_logs
             ORDER BY created_at DESC
             LIMIT ?1",
            params![lim],
            error_log_row_mapper,
        )
    }
}

fn error_log_row_mapper(row: &rusqlite::Row<'_>) -> rusqlite::Result<ErrorLogEntry> {
    Ok(ErrorLogEntry {
        id: row.get(0)?,
        source: row.get(1)?,
        level: row.get(2)?,
        message: row.get(3)?,
        details: row.get(4)?,
        created_at: row.get(5)?,
    })
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn append_error_log(
    source: String,
    message: String,
    details: Option<String>,
    level: Option<String>,
) -> Result<(), String> {
    let conn = get_conn()?;
    append_error_log_internal(&conn, &source, &message, details, level)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn get_error_logs(
    limit: Option<i64>,
    since_iso: Option<String>,
) -> Result<Vec<ErrorLogEntry>, String> {
    let conn = get_read_conn()?;
    read_error_logs(&conn, limit, since_iso.as_deref()).map_err(String::from)
}

#[tauri::command]
pub fn clear_error_logs() -> Result<ClearErrorLogsResult, String> {
    let conn = get_conn()?;
    let deleted = conn
        .execute("DELETE FROM error_logs", [])
        .map_err(AppError::from)
        .map_err(String::from)?;
    Ok(ClearErrorLogsResult { deleted })
}

/// Count of `error_logs` rows written after the user last opened
/// Settings → Data → Diagnostics on this device (#2253).
///
/// The last-viewed timestamp is read from `device_state` under
/// [`DEV_ERROR_LOGS_LAST_VIEWED_AT`]. When absent — fresh install or
/// a user who has never opened the panel — every existing row counts
/// as unseen, which is the right default: the badge should appear
/// immediately for a user who has accumulated errors before the
/// feature shipped. Both sides of the comparison are RFC3339 UTC from
/// `sync_timestamp_now()`, so lexicographic `>` is correct.
pub(crate) fn read_unseen_error_log_count(conn: &rusqlite::Connection) -> AppResult<i64> {
    // Unwrap the device_state JSON scalar: stored via the canonical
    // JSON writer in `device_state.rs`, so a RFC3339 string lives as
    // a quoted JSON string like `"2026-04-19T12:34:56Z"`. Anything
    // else (malformed write, legacy row) is treated as "never viewed"
    // so the badge surfaces instead of silently suppressing.
    let raw: Option<String> = conn
        .query_row(
            "SELECT value FROM device_state WHERE key = ?1",
            params![DEV_ERROR_LOGS_LAST_VIEWED_AT],
            |row| row.get(0),
        )
        .optional()
        .map_err(AppError::from)?;
    let last_viewed = raw.and_then(|v| serde_json::from_str::<String>(&v).ok());

    let count: i64 = if let Some(ts) = last_viewed {
        conn.query_row(
            "SELECT COUNT(*) FROM error_logs WHERE created_at > ?1",
            params![ts],
            |row| row.get(0),
        )
        .map_err(AppError::from)?
    } else {
        conn.query_row("SELECT COUNT(*) FROM error_logs", [], |row| row.get(0))
            .map_err(AppError::from)?
    };
    Ok(count)
}

#[tauri::command]
pub fn get_unseen_error_log_count() -> Result<i64, String> {
    let conn = get_read_conn()?;
    read_unseen_error_log_count(&conn).map_err(String::from)
}

#[tauri::command]
pub fn mark_error_logs_viewed() -> Result<(), String> {
    let conn = get_conn()?;
    // Store as a canonical JSON string so it round-trips through
    // `get_device_state` without the caller having to know the
    // encoding. `sync_timestamp_now()` is the same RFC3339 UTC format
    // used by `error_logs.created_at`, so comparisons stay
    // lexicographic and monotonic.
    let now = sync_timestamp_now();
    let canonical = serde_json::to_string(&now)
        .map_err(AppError::from)
        .map_err(String::from)?;
    conn.execute(
        "INSERT INTO device_state (key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = ?2",
        params![DEV_ERROR_LOGS_LAST_VIEWED_AT, canonical],
    )
    .map_err(AppError::from)
    .map_err(String::from)?;
    Ok(())
}
