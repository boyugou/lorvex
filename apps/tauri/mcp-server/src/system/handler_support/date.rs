use crate::error::McpError;
use lorvex_domain::validation::validate_date_format;
use lorvex_workflow::timezone::today_ymd_for_conn;
use rusqlite::{Connection, OptionalExtension};

pub(crate) fn resolve_optional_date(
    conn: &Connection,
    value: Option<String>,
) -> Result<String, McpError> {
    match value {
        None => Ok(today_ymd_for_conn(conn)?),
        Some(d) => {
            validate_date_format(&d)?;
            Ok(d)
        }
    }
}

pub(crate) fn canonicalize_reminder_timestamp(raw: &str) -> Result<String, McpError> {
    lorvex_domain::canonicalize_rfc3339_instant(raw).ok_or_else(|| {
        McpError::Validation(format!(
            "Invalid reminder timestamp '{raw}'. Must be a valid RFC 3339 datetime (e.g. 2025-12-01T09:00:00Z)."
        ))
    })
}

/// resolve the (HH:MM, IANA-tz) pair that anchors a
/// reminder's local wall-clock at the moment of creation. Pulls the
/// active `PREF_TIMEZONE` and converts the UTC RFC-3339 reminder
/// timestamp into that zone. Returns `(None, None)` when the
/// timezone preference is absent / malformed or the timestamp
/// can't be parsed — the caller writes NULL anchor columns and the
/// reminder keeps pure absolute-UTC semantics.
pub(crate) fn resolve_reminder_local_anchor(
    conn: &Connection,
    reminder_at_rfc3339: &str,
) -> Result<(Option<String>, Option<String>), McpError> {
    Ok(
        lorvex_workflow::reminder_anchor::resolve_task_reminder_local_anchor(
            conn,
            reminder_at_rfc3339,
        )?,
    )
}

pub(crate) fn resolve_list_name(
    conn: &Connection,
    list_id: &str,
) -> Result<Option<String>, McpError> {
    Ok(conn
        .query_row("SELECT name FROM lists WHERE id = ?", [list_id], |row| {
            row.get::<_, String>(0)
        })
        .optional()?)
}
