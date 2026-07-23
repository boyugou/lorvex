//! Best-effort writer for diagnostic rows in the `error_logs` table.
//!
//! Wraps [`lorvex_store::error_log::append_error_log`] with the
//! sync-layer's best-effort policy: if the INSERT fails the caller
//! has already done what it could (the underlying error path that
//! triggered the diagnostic is itself handling a failure), so we
//! swallow the secondary error rather than propagating it.
//!
//! All redaction + truncation is handled by the store-layer helper
//! so secrets in error messages never reach the DB.
//!
//! the secondary error is no longer fully silent —
//! we `debug_assert!` so a regression that breaks the diagnostic
//! INSERT (schema drift, redaction panic, etc.) blows up loudly in
//! tests / debug builds while production stays best-effort.

use rusqlite::Connection;

/// Append one row to `error_logs` with `level = 'error'`. Returns
/// nothing — failures to log are silent in release builds (see module
/// doc) but `debug_assert!` in debug/test builds so a broken
/// diagnostic write surface is caught loudly.
pub(crate) fn log_sync_error(
    conn: &Connection,
    source: &str,
    message: &str,
    details: Option<&str>,
) {
    lorvex_store::error_log::append_error_log_best_effort(conn, source, message, details, None);
}
