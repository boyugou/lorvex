//! Translation from internal SQLite/Rust error strings to user-facing
//! IPC messages, with unmatched cases persisted as structured
//! diagnostics for later triage.

const UNMATCHED_DB_ERROR_SOURCE: &str = "shared.sanitize_db_error.unmatched";
const UNMATCHED_DB_ERROR_MESSAGE: &str = "Unmatched database error sanitized for IPC";

/// Translates internal error strings into user-friendly messages.
/// Known SQLite/Rust internals are mapped to friendly messages; unrecognized
/// errors are persisted as structured diagnostics and returned with a generic message.
pub(crate) fn sanitize_db_error(error: impl std::fmt::Display) -> String {
    sanitize_db_error_with_logger(error, append_unmatched_db_error_log_best_effort)
}

fn sanitize_db_error_with_logger(
    error: impl std::fmt::Display,
    log_unmatched: impl FnOnce(&str),
) -> String {
    let raw = error.to_string();
    if let Some(friendly) = lorvex_store::error_sanitize::sanitize_sqlite_error(&raw) {
        return friendly;
    }
    log_unmatched(&raw);
    generic_internal_db_error_message()
}

fn append_unmatched_db_error_log_best_effort(raw: &str) {
    crate::commands::diagnostics::try_append_error_log_best_effort(
        UNMATCHED_DB_ERROR_SOURCE,
        UNMATCHED_DB_ERROR_MESSAGE,
        Some(unmatched_db_error_details(raw)),
        Some("error".to_string()),
    );
}

#[cfg(test)]
fn append_unmatched_db_error_log(conn: &rusqlite::Connection, raw: &str) {
    let _ = crate::commands::diagnostics::append_error_log_internal(
        conn,
        UNMATCHED_DB_ERROR_SOURCE,
        UNMATCHED_DB_ERROR_MESSAGE,
        Some(unmatched_db_error_details(raw)),
        Some("error".to_string()),
    );
}

fn unmatched_db_error_details(raw: &str) -> String {
    let redacted = lorvex_domain::diagnostics::redact_diagnostic_text(raw);
    format!("error={redacted}")
}

fn generic_internal_db_error_message() -> String {
    "An internal error occurred. Please try again or report a bug.".to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unmatched_db_error_diagnostic_is_redacted_before_persistence() {
        let conn = crate::test_support::test_conn();
        append_unmatched_db_error_log(
            &conn,
            "database error near /Users/alice/Lorvex.sqlite: Authorization: Bearer eyJhbGciOi.deadbeef.xyz",
        );

        let row: (String, String, String, String) = conn
            .query_row(
                "SELECT source, level, message, details
                 FROM error_logs
                 WHERE source = 'shared.sanitize_db_error.unmatched'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .expect("read unmatched DB sanitizer diagnostic");

        assert_eq!(row.0, UNMATCHED_DB_ERROR_SOURCE);
        assert_eq!(row.1, "error");
        assert_eq!(row.2, UNMATCHED_DB_ERROR_MESSAGE);
        assert!(row.3.contains("error="));
        assert!(!row.3.contains("eyJhbGciOi.deadbeef.xyz"));
        assert!(row.3.contains("[REDACTED]"));
    }

    #[test]
    fn sanitize_db_error_keeps_generic_message_for_unmatched_errors() {
        let message = sanitize_db_error_with_logger("totally unknown database failure", |_| {});

        assert_eq!(
            message,
            "An internal error occurred. Please try again or report a bug."
        );
    }
}
