pub(crate) fn normalize_date_input_for_timezone<Tz: chrono::TimeZone>(
    value: &str,
    timezone: &Tz,
) -> Option<String> {
    let trimmed = value.trim();
    if lorvex_domain::validation::validate_date_format(trimmed).is_ok() {
        return Some(trimmed.to_string());
    }

    if let Ok(rfc3339) = chrono::DateTime::parse_from_rfc3339(trimmed) {
        return Some(
            rfc3339
                .with_timezone(timezone)
                .date_naive()
                .format("%Y-%m-%d")
                .to_string(),
        );
    }

    for format in [
        "%Y-%m-%dT%H:%M",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%Y-%m-%d %H:%M:%S",
    ] {
        if let Ok(parsed) = chrono::NaiveDateTime::parse_from_str(trimmed, format) {
            // Interpret naive datetime in the user's timezone, then extract the date.
            // Without this, a user in UTC-8 receiving "2025-01-01T01:00" gets Jan 1
            // when the local date is still Dec 31.
            //
            // Issue #2389 note: we deliberately do NOT route this through
            // `lorvex_domain::dst::resolve_local_datetime`. This helper
            // only extracts a Y-M-D day for query bounds from a
            // user-supplied datetime string (e.g. `until_date`). Any DST
            // resolution from `.earliest()` — even a silent snap in a
            // gap — lands on the same local calendar day, which is all
            // the caller needs. Real DST-gap validation is enforced at
            // the calendar event create/update path, not on a
            // bounds-only date extraction.
            let local_date = timezone
                .from_local_datetime(&parsed)
                .earliest()
                .map_or_else(|| parsed.date(), |dt| dt.date_naive());
            return Some(local_date.format("%Y-%m-%d").to_string());
        }
    }

    None
}

fn normalize_date_input(value: &str) -> Option<String> {
    normalize_date_input_for_timezone(value, &chrono::Local)
}

pub(crate) fn normalize_date_input_for_conn(
    conn: &rusqlite::Connection,
    value: &str,
) -> Result<String, String> {
    let timezone = lorvex_workflow::timezone::active_timezone_name(conn)
        .map_err(|e| String::from(crate::error::AppError::from(e)))?;
    timezone
        .as_deref()
        .and_then(lorvex_domain::parse_timezone_name)
        .and_then(|tz| normalize_date_input_for_timezone(value, &tz))
        .or_else(|| normalize_date_input(value))
        .ok_or_else(|| "until_date must be a valid YYYY-MM-DD date".to_string())
}
