//! Flexible date-string normalization for task-create due / planned dates.
//!
//! Accepts `YYYY-MM-DD`, `today`/`tomorrow`/`yesterday`, RFC 3339 datetimes,
//! and a handful of common locale-friendly formats (`%Y/%m/%d`, `%m/%d/%Y`,
//! `%b %d, %Y`, etc.). Resolves relative tokens and timezone-bearing
//! datetimes through the active preference timezone, falling back to the
//! process-local zone when no preference is configured.

use chrono::{DateTime, Local, LocalResult, NaiveDate, NaiveDateTime, Utc};
use lorvex_store::StoreError;
use rusqlite::Connection;

pub(crate) fn normalize_due_date_input_for_conn(
    conn: &Connection,
    value: String,
) -> Result<String, StoreError> {
    let timezone_name = crate::timezone::active_timezone_name(conn)?;
    let timezone = timezone_name
        .as_deref()
        .and_then(lorvex_domain::parse_timezone_name);
    let now = Utc::now();
    let today = lorvex_domain::today_ymd_for_timezone_name(now, timezone_name.as_deref());
    let tomorrow =
        lorvex_domain::date_plus_days_ymd_for_timezone_name(now, timezone_name.as_deref(), 1);
    let yesterday =
        lorvex_domain::date_plus_days_ymd_for_timezone_name(now, timezone_name.as_deref(), -1);

    let trimmed = value.trim();
    if trimmed.is_empty() {
        return Err(StoreError::Validation(
            "due_date must be a non-empty date string".to_string(),
        ));
    }
    match trimmed.to_ascii_lowercase().as_str() {
        "today" => return Ok(today),
        "tomorrow" => return Ok(tomorrow),
        "yesterday" => return Ok(yesterday),
        _ => {}
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
        return Err(StoreError::Validation(format!(
            "'{trimmed}' is not a valid calendar date"
        )));
    }
    if let Some(parsed) = timezone
        .as_ref()
        .and_then(|tz| parse_flexible_due_date_for_timezone(trimmed, tz))
        .or_else(|| parse_flexible_due_date_for_timezone(trimmed, &Local))
    {
        return Ok(parsed);
    }
    Err(StoreError::Validation(format!(
        "Invalid due_date '{value}'. Expected YYYY-MM-DD, today, tomorrow, yesterday, an RFC3339 datetime, or a common date format"
    )))
}

fn parse_flexible_due_date_for_timezone<Tz: chrono::TimeZone>(
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
    // Route naive datetimes through the user timezone so an evening
    // local time near midnight produces the right local date instead
    // of the implicit UTC date. The caller passes the user's IANA
    // zone; interpret the typed value as a wall clock in that zone.
    for fmt in ["%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M"] {
        if let Ok(naive) = NaiveDateTime::parse_from_str(value, fmt) {
            return Some(
                match timezone.from_local_datetime(&naive) {
                    LocalResult::Single(zoned) => zoned.date_naive(),
                    LocalResult::Ambiguous(earliest, _latest) => earliest.date_naive(),
                    LocalResult::None => naive.date(),
                }
                .format("%Y-%m-%d")
                .to_string(),
            );
        }
    }
    for format in [
        "%Y/%m/%d",
        "%Y.%m.%d",
        "%m/%d/%Y",
        "%m-%d-%Y",
        "%m.%d.%Y",
        "%b %d, %Y",
        "%B %d, %Y",
    ] {
        if let Ok(date) = NaiveDate::parse_from_str(value, format) {
            return Some(date.format("%Y-%m-%d").to_string());
        }
    }
    None
}
