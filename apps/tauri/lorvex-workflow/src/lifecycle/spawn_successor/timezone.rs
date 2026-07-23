//! Resolve today's date in the user's configured timezone.
//!
//! Fallback rules match `lorvex_domain::today_ymd_for_timezone_name`:
//! missing preference → system local; malformed preference → typed
//! `StoreError::Validation`.

use rusqlite::{Connection, OptionalExtension};

use lorvex_store::StoreError;

pub(super) fn today_ymd_in_user_timezone(
    conn: &Connection,
    now: &str,
) -> Result<String, StoreError> {
    let now_dt = chrono::DateTime::parse_from_rfc3339(now)
        .map(|dt| dt.with_timezone(&chrono::Utc))
        .map_err(|_| {
            StoreError::Validation(format!("completion timestamp must be valid RFC3339: {now}"))
        })?;

    let raw_tz: Option<String> = conn
        .query_row(
            "SELECT value FROM preferences WHERE key = 'timezone'",
            [],
            |row| row.get(0),
        )
        .optional()?;

    // If a preference exists but is malformed, surface the validation
    // error rather than silently falling back. If the preference is
    // absent, hand `None` to the canonical helper which uses the
    // system-local timezone.
    let timezone_name: Option<String> = match raw_tz.as_deref() {
        None => None,
        Some(raw) => Some(lorvex_domain::parse_required_timezone_preference(
            raw, "timezone",
        )?),
    };

    Ok(lorvex_domain::today_ymd_for_timezone_name(
        now_dt,
        timezone_name.as_deref(),
    ))
}
