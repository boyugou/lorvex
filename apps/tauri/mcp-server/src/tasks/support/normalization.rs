use crate::contract::DUE_DATE_ALLOWED_INPUT_SUMMARY;
use crate::error::McpError;
use crate::time::{date_plus_days_ymd_for_timezone_name, today_ymd_for_timezone_name};
use chrono::{DateTime, Local, NaiveDate, NaiveDateTime, Utc};
use lorvex_domain::Patch;
use lorvex_workflow::timezone::active_timezone_name;
use rusqlite::Connection;

pub(super) fn parse_flexible_due_date_for_timezone<Tz: chrono::TimeZone>(
    value: &str,
    timezone: &Tz,
) -> Option<String> {
    if let Ok(date) = DateTime::parse_from_rfc3339(value) {
        return Some(
            date.with_timezone(timezone)
                .date_naive()
                .format("%Y-%m-%d")
                .to_string(),
        );
    }
    if let Ok(date) = NaiveDateTime::parse_from_str(value, "%Y-%m-%d %H:%M:%S") {
        return Some(date.date().format("%Y-%m-%d").to_string());
    }
    if let Ok(date) = NaiveDateTime::parse_from_str(value, "%Y-%m-%d %H:%M") {
        return Some(date.date().format("%Y-%m-%d").to_string());
    }
    let formats = [
        "%Y/%m/%d",
        "%Y.%m.%d",
        "%m/%d/%Y",
        "%m-%d-%Y",
        "%m.%d.%Y",
        "%b %d, %Y",
        "%B %d, %Y",
    ];
    for format in formats {
        if let Ok(date) = NaiveDate::parse_from_str(value, format) {
            return Some(date.format("%Y-%m-%d").to_string());
        }
    }
    None
}

fn parse_flexible_due_date(value: &str) -> Option<String> {
    parse_flexible_due_date_for_timezone(value, &Local)
}

fn normalize_due_date_input_for_timezone_name(
    value: String,
    timezone_name: Option<&str>,
) -> Result<String, McpError> {
    let timezone = timezone_name.and_then(lorvex_domain::parse_timezone_name);
    // always route through the tz-aware helpers,
    // passing `timezone_name` straight through. The helpers
    // themselves fall back to system-local when the name is `None`,
    // so the caller no longer has to branch — and the bare
    // `local_today_ymd` / `local_date_plus_days_ymd` helpers (which
    // ignored the user's stored preference outright) are gone.
    let today = today_ymd_for_timezone_name(Utc::now(), timezone_name);
    let tomorrow = date_plus_days_ymd_for_timezone_name(Utc::now(), timezone_name, 1);
    let yesterday = date_plus_days_ymd_for_timezone_name(Utc::now(), timezone_name, -1);

    let trimmed = value.trim();
    if trimmed.is_empty() {
        return Err(McpError::Validation(
            "due_date must be a non-empty date string".to_string(),
        ));
    }
    let lowered = trimmed.to_ascii_lowercase();
    if lowered == "today" {
        return Ok(today);
    }
    if lowered == "tomorrow" {
        return Ok(tomorrow);
    }
    if lowered == "yesterday" {
        return Ok(yesterday);
    }
    if trimmed.len() == 10
        && trimmed
            .chars()
            .enumerate()
            .all(|(idx, ch)| matches!(idx, 4 | 7) || ch.is_ascii_digit())
        && &trimmed[4..5] == "-"
        && &trimmed[7..8] == "-"
    {
        if NaiveDate::parse_from_str(trimmed, "%Y-%m-%d").is_ok() {
            return Ok(trimmed.to_string());
        }
        return Err(McpError::Validation(format!(
            "'{trimmed}' is not a valid calendar date"
        )));
    }
    if let Some(parsed) = timezone
        .as_ref()
        .and_then(|tz| parse_flexible_due_date_for_timezone(trimmed, tz))
        .or_else(|| parse_flexible_due_date(trimmed))
    {
        return Ok(parsed);
    }
    Err(McpError::Validation(format!(
        "Invalid due_date '{value}'. Expected {DUE_DATE_ALLOWED_INPUT_SUMMARY}"
    )))
}

#[cfg(test)]
pub(crate) fn normalize_due_date_input(value: String) -> Result<String, McpError> {
    normalize_due_date_input_for_timezone_name(value, None)
}

pub(crate) fn normalize_due_date_input_for_conn(
    conn: &Connection,
    value: String,
) -> Result<String, McpError> {
    let timezone = active_timezone_name(conn)?;
    normalize_due_date_input_for_timezone_name(value, timezone.as_deref())
}

#[allow(dead_code)]
pub(crate) fn normalize_nullable_due_date_patch_for_conn(
    conn: &Connection,
    patch: Patch<String>,
) -> Result<Patch<String>, McpError> {
    patch.try_map(|value| normalize_due_date_input_for_conn(conn, value))
}

#[allow(dead_code)]
pub(crate) fn normalize_task_priority(value: Option<u8>) -> Result<Option<u8>, McpError> {
    match value {
        None => Ok(None),
        Some(1..=3) => Ok(value),
        Some(other) => Err(McpError::Validation(format!(
            "Invalid priority '{other}'. Expected one of: 1, 2, 3"
        ))),
    }
}

#[cfg(test)]
pub(crate) fn recurrence_base_date_for_conn_at(
    conn: &Connection,
    due_date: Option<&str>,
    now: DateTime<Utc>,
) -> Result<String, McpError> {
    match due_date {
        Some(value) => Ok(value.to_string()),
        None => {
            let timezone = active_timezone_name(conn)?;
            Ok(today_ymd_for_timezone_name(now, timezone.as_deref()))
        }
    }
}
