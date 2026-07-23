#[cfg(desktop)]
pub use parse::parse_opened_url_result;
pub use queue::{acknowledge_pending_payload, enqueue_pending, take_pending_payload};
pub use target::{DeepLinkTarget, DeepLinkTargetPayload};

pub const DEEP_LINK_OPEN_EVENT: &str = "deep-link://open";
const DEEP_LINK_LOG_SOURCE: &str = "deep_link";

/// Cap on the slug component of a deep-link URL (e.g. the
/// `list:<slug>` segment in `lorvex://list/<slug>`). Sized to match
/// the canonical title cap so a slug that round-trips through
/// `validate_title` stays valid as a deep-link target.
pub(super) const MAX_LIST_SLUG_LENGTH: usize = lorvex_domain::validation::MAX_TITLE_LENGTH;

fn append_deep_link_log_with_conn(
    conn: &rusqlite::Connection,
    level: &str,
    source_suffix: &str,
    message: &str,
    details: Option<String>,
) -> Result<(), String> {
    let source = compose_deep_link_source(source_suffix);
    crate::commands::diagnostics::append_diagnostic_log_with_conn(
        conn, &source, level, message, details,
    )
}

pub(crate) fn append_deep_link_log(
    level: &str,
    source_suffix: &str,
    message: &str,
    details: Option<String>,
) {
    let Ok(conn) = crate::db::get_conn() else {
        return;
    };
    let _ = append_deep_link_log_with_conn(&conn, level, source_suffix, message, details);
}

fn compose_deep_link_source(source_suffix: &str) -> String {
    if source_suffix.trim().is_empty() {
        DEEP_LINK_LOG_SOURCE.to_string()
    } else {
        format!("{DEEP_LINK_LOG_SOURCE}.{source_suffix}")
    }
}

pub(crate) mod parse;
mod queue;
mod target;

#[cfg(test)]
mod tests;

#[cfg(test)]
mod diagnostics_tests {
    use super::*;
    use crate::test_support::test_conn;

    #[test]
    fn append_deep_link_log_with_conn_persists_structured_diagnostic() {
        let conn = test_conn();

        append_deep_link_log_with_conn(
            &conn,
            "Warning",
            "opened_url",
            "Deep link diagnostic token=message-secret",
            Some("stage=test token=details-secret".to_string()),
        )
        .expect("append deep-link diagnostic");

        let row: (String, String, String, Option<String>) = conn
            .query_row(
                "SELECT source, level, message, details FROM error_logs",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .expect("read diagnostic row");

        assert_eq!(row.0, "deep_link.opened_url");
        assert_eq!(row.1, "warn");
        assert_eq!(row.2, "Deep link diagnostic token=[REDACTED]");
        assert_eq!(row.3.as_deref(), Some("stage=test token=[REDACTED]"));
    }
}
