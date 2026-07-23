//! IANA timezone parsing / normalization helpers and the timezone-aware
//! "today" / "today + N days" `YYYY-MM-DD` helpers used for
//! day-boundary logic across the workspace.

use chrono::{DateTime, Duration, Local, NaiveDate, Utc};
use chrono_tz::Tz;

/// Parse and validate a non-empty IANA timezone name.
pub fn parse_timezone_name(value: &str) -> Option<Tz> {
    let trimmed = value.trim();
    (!trimmed.is_empty())
        .then_some(trimmed)
        .and_then(|timezone| timezone.parse::<Tz>().ok())
}

/// Normalize a timezone name only if it is a valid IANA timezone.
///
/// Returns the trimmed string when valid; otherwise `None`.
pub fn normalize_timezone_name(value: Option<&str>) -> Option<String> {
    let trimmed = value?.trim();
    parse_timezone_name(trimmed).map(|_| trimmed.to_string())
}

/// Parse a canonical JSON string preference containing a valid IANA timezone.
///
/// Raw unquoted fallback strings and invalid timezone identifiers are rejected.
pub fn parse_json_timezone_preference(raw: Option<&str>) -> Option<String> {
    let timezone = crate::parsing::parse_json_string_preference(raw)?;
    parse_timezone_name(&timezone)?;
    Some(timezone)
}

/// Parse a stored timezone preference that must contain a valid canonical IANA
/// timezone string. Returns a typed `ValidationError` so consumers can
/// `?`-propagate through the existing `From<ValidationError>` impls
/// instead of stringifying at every boundary (#3288).
pub fn parse_required_timezone_preference(
    raw: &str,
    key: &str,
) -> Result<String, crate::validation::ValidationError> {
    let timezone = crate::parsing::parse_json_string_preference(Some(raw)).ok_or_else(|| {
        crate::validation::ValidationError::Message(format!(
            "invalid {key} preference: expected canonical JSON timezone string"
        ))
    })?;
    if parse_timezone_name(&timezone).is_some() {
        Ok(timezone)
    } else {
        Err(crate::validation::ValidationError::Message(format!(
            "invalid {key} preference: unknown timezone '{timezone}'"
        )))
    }
}

/// Resolve the anchored timezone used for calendar/day-boundary logic.
///
/// Preference order:
/// 1. Explicit validated active timezone from preferences.
/// 2. Current system IANA timezone, if resolvable and valid.
///
/// When neither source is available, callers should fail instead of silently
/// substituting `UTC`, because that would shift calendar-day boundaries and
/// mis-anchor local-time queries.
pub fn resolve_anchored_timezone_name(
    active_timezone: Option<String>,
    system_timezone_lookup: Result<String, String>,
) -> Result<String, String> {
    if let Some(active_timezone) = active_timezone {
        return Ok(active_timezone);
    }

    let timezone = system_timezone_lookup.map_err(|error| {
        format!("anchored timezone requires a resolvable system IANA timezone: {error}")
    })?;
    normalize_timezone_name(Some(&timezone)).ok_or_else(|| {
        format!("anchored timezone requires a valid IANA timezone, got '{timezone}'")
    })
}

// the bare `local_today_ymd` /
// `local_date_plus_days_ymd` helpers live here. They
// silently routed through `chrono::Local` (the host machine's
// timezone) regardless of the user's stored `PREF_TIMEZONE`, so a
// user with `America/Los_Angeles` running on a UTC-set CI/server
// box saw "today" against the host clock instead of their own —
// off by up to a calendar day for every "today / tomorrow /
// yesterday" lookup. Deleting the helpers forces every caller to
// pass an explicit timezone name (which falls back to system-local
// only when the caller passes `None`, i.e. legitimately has no
// preference). Callers that need a fallback chain (active
// preference, then system) should route through
// [`resolve_anchored_timezone_name`] so the failure surfaces as a
// typed error instead of a silent zone substitution.

/// Today's date as `YYYY-MM-DD` in the given IANA timezone, falling back to
/// system-local when the timezone name is `None` or unrecognized.
///
/// a *corrupt* (Some(invalid)) timezone preference is
/// distinct from an *unset* (None) one — `None` legitimately means
/// "no preference, use system-local", but `Some("America/Not_A_Zone")`
/// is a data-integrity failure (preference table corruption,
/// truncated import, manual DB edit). In dev builds the
/// `debug_assert!` panics so the test suite catches the case at the
/// failure site; in release we still fall back gracefully because
/// the alternative (panicking on every today-query) is worse than
/// returning a possibly-off-by-one date.
pub fn today_ymd_for_timezone_name(now: DateTime<Utc>, timezone_name: Option<&str>) -> String {
    base_date_in_timezone(now, timezone_name, "today_ymd_for_timezone_name")
        .format("%Y-%m-%d")
        .to_string()
}

/// Today + `offset_days` as `YYYY-MM-DD` in the given IANA timezone, falling
/// back to system-local when the timezone name is `None` or unrecognized.
/// See [`today_ymd_for_timezone_name`] for the corrupt-preference contract.
pub fn date_plus_days_ymd_for_timezone_name(
    now: DateTime<Utc>,
    timezone_name: Option<&str>,
    offset_days: i64,
) -> String {
    let base_date =
        base_date_in_timezone(now, timezone_name, "date_plus_days_ymd_for_timezone_name");
    (base_date + Duration::days(offset_days))
        .format("%Y-%m-%d")
        .to_string()
}

/// Resolve the calendar date `now` falls on under `timezone_name`,
/// falling back to system-local on either `None` or an unparseable
/// timezone string. Mirrors the corrupt-preference contract documented
/// on [`today_ymd_for_timezone_name`]: an explicit non-empty but
/// invalid IANA name fires a `debug_assert!` so test runs catch the
/// drift while release builds still degrade gracefully.
///
/// `caller` names the caller for the assertion message; in release it
/// is unused and compiles away with the `debug_assert!`.
fn base_date_in_timezone(
    now: DateTime<Utc>,
    timezone_name: Option<&str>,
    caller: &'static str,
) -> NaiveDate {
    if let Some(name) = timezone_name {
        if let Some(tz) = parse_timezone_name(name) {
            return now.with_timezone(&tz).date_naive();
        }
        debug_assert!(
            name.is_empty(),
            "{caller}: invalid IANA timezone '{name}'; falling back to system-local"
        );
    }
    now.with_timezone(&Local).date_naive()
}
