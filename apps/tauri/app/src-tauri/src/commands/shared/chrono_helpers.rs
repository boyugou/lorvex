//! Time / date helpers used by IPC handlers.

/// Test-only convenience: today's date in the host machine's
/// timezone. The bare `local_today_ymd` /
/// `local_date_plus_days_ymd` helpers in `lorvex-domain` are gone
/// because production callers were silently using `chrono::Local`
/// regardless of the user's stored preference. Tests legitimately
/// want "today on the box that ran cargo test" — naming the helper
/// `..._for_test` keeps that intent visible.
#[cfg(test)]
pub(crate) fn today_ymd_local_for_test() -> String {
    lorvex_domain::today_ymd_for_timezone_name(chrono::Utc::now(), None)
}

/// Test-only companion to [`today_ymd_local_for_test`].
#[cfg(test)]
pub(crate) fn date_plus_days_ymd_local_for_test(days: i64) -> String {
    lorvex_domain::date_plus_days_ymd_for_timezone_name(chrono::Utc::now(), None, days)
}

pub(crate) fn parse_rfc3339_utc(value: &str) -> Option<chrono::DateTime<chrono::Utc>> {
    chrono::DateTime::parse_from_rfc3339(value)
        .ok()
        .map(|dt| dt.with_timezone(&chrono::Utc))
}

/// Canonical sync timestamp format used across write paths.
/// Fixed millisecond precision keeps lexical and temporal ordering
/// aligned (see `lorvex-domain/src/time/sync_timestamp.rs`).
pub(crate) use lorvex_domain::sync_timestamp_now;
