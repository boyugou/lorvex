//! Shared timezone resolution from the DB `preferences` table.
//!
//! Both the MCP server and the Tauri app delegate here instead of owning
//! independent DB-to-timezone lookup implementations.

use chrono::{DateTime, Local, NaiveDate, TimeZone, Utc};
use lorvex_store::StoreError;
use rusqlite::{Connection, OptionalExtension};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TrailingDayWindowUtcBounds {
    pub from_day: String,
    pub to_day: String,
    pub start_utc: String,
    pub end_utc: String,
}

const MAX_SKIPPED_DAY_FALLBACK: i64 = 3;

/// Read the `timezone` preference from the database and validate it.
///
/// Returns `Ok(None)` when no timezone preference is stored,
/// or `Ok(Some(name))` with the validated IANA timezone name.
pub fn active_timezone_name(conn: &Connection) -> Result<Option<String>, StoreError> {
    let raw_value = conn
        .query_row(
            "SELECT value FROM preferences WHERE key = ?1",
            rusqlite::params![lorvex_domain::preference_keys::PREF_TIMEZONE],
            |row| row.get::<_, String>(0),
        )
        .optional()?;
    match raw_value {
        Some(raw) => Ok(Some(lorvex_domain::parse_required_timezone_preference(
            &raw,
            lorvex_domain::preference_keys::PREF_TIMEZONE,
        )?)),
        None => Ok(None),
    }
}

/// Resolve an anchored timezone name: prefer the DB preference, fall back
/// to the system timezone, and error if neither is available.
pub fn anchored_timezone_name(conn: &Connection) -> Result<String, StoreError> {
    let active = active_timezone_name(conn)?;
    let system = iana_time_zone::get_timezone().map_err(|error| error.to_string());
    lorvex_domain::resolve_anchored_timezone_name(active, system).map_err(StoreError::Validation)
}

/// Today's date as `YYYY-MM-DD` in the user's configured timezone.
pub fn today_ymd_for_conn(conn: &Connection) -> Result<String, StoreError> {
    today_ymd_for_conn_at(conn, chrono::Utc::now())
}

pub fn today_ymd_for_conn_at(
    conn: &Connection,
    now: chrono::DateTime<chrono::Utc>,
) -> Result<String, StoreError> {
    let timezone = anchored_timezone_name(conn)?;
    Ok(lorvex_domain::today_ymd_for_timezone_name(
        now,
        Some(timezone.as_str()),
    ))
}

/// A date offset by `days` from today, as `YYYY-MM-DD`, in the user's
/// configured timezone.
pub fn date_plus_days_ymd_for_conn(conn: &Connection, days: i64) -> Result<String, StoreError> {
    date_plus_days_ymd_for_conn_at(conn, chrono::Utc::now(), days)
}

/// A date offset by `days` from a specific UTC instant (testable).
fn date_plus_days_ymd_for_conn_at(
    conn: &Connection,
    now: DateTime<Utc>,
    days: i64,
) -> Result<String, StoreError> {
    // same fix as today_ymd_for_conn_at — use the
    // anchored resolver instead of allowing a silent OS-tz fallback.
    let timezone = anchored_timezone_name(conn)?;
    Ok(lorvex_domain::date_plus_days_ymd_for_timezone_name(
        now,
        Some(timezone.as_str()),
        days,
    ))
}

fn first_valid_utc_for_local_day<Tz: TimeZone>(
    day: NaiveDate,
    timezone: &Tz,
) -> Option<DateTime<Utc>> {
    for day_offset in 0..=MAX_SKIPPED_DAY_FALLBACK {
        let probe_day = day.checked_add_signed(chrono::Duration::days(day_offset))?;
        if let Some(value) = first_valid_utc_on(probe_day, timezone) {
            return Some(value);
        }
    }
    None
}

fn first_valid_utc_on<Tz: TimeZone>(day: NaiveDate, timezone: &Tz) -> Option<DateTime<Utc>> {
    let midnight = day.and_hms_opt(0, 0, 0)?;
    for minute_offset in 0..(24 * 60) {
        let candidate = midnight + chrono::Duration::minutes(i64::from(minute_offset));
        match timezone.from_local_datetime(&candidate) {
            chrono::LocalResult::Single(value) => return Some(value.with_timezone(&Utc)),
            chrono::LocalResult::Ambiguous(first, second) => {
                let first_utc = first.with_timezone(&Utc);
                let second_utc = second.with_timezone(&Utc);
                return Some(if first_utc <= second_utc {
                    first_utc
                } else {
                    second_utc
                });
            }
            chrono::LocalResult::None => (),
        }
    }
    None
}

fn utc_start_of_day_for_timezone_name(
    day: &str,
    timezone_name: &str,
) -> Result<String, StoreError> {
    let parsed_day = lorvex_domain::time::parse_iso_date(day)
        .map_err(|_| StoreError::Validation(format!("invalid local day boundary '{day}'")))?;
    let utc_value = lorvex_domain::parse_timezone_name(timezone_name)
        .map_or_else(
            || first_valid_utc_for_local_day(parsed_day, &Local),
            |timezone| first_valid_utc_for_local_day(parsed_day, &timezone),
        )
        .ok_or_else(|| {
            StoreError::Validation(format!(
                "could not resolve UTC boundary for local day '{day}': \
             every probed day was skipped by the timezone"
            ))
        })?;

    Ok(lorvex_domain::format_sync_timestamp(utc_value))
}

pub fn trailing_day_window_utc_bounds_for_conn(
    conn: &Connection,
    span_days: i64,
) -> Result<TrailingDayWindowUtcBounds, StoreError> {
    trailing_day_window_utc_bounds_for_conn_at(conn, Utc::now(), span_days)
}

pub fn trailing_day_window_utc_bounds_for_conn_at(
    conn: &Connection,
    now: DateTime<Utc>,
    span_days: i64,
) -> Result<TrailingDayWindowUtcBounds, StoreError> {
    if span_days < 1 {
        return Err(StoreError::Validation(
            "trailing day window must cover at least one day".to_string(),
        ));
    }

    let timezone = anchored_timezone_name(conn)?;
    let to_day = lorvex_domain::today_ymd_for_timezone_name(now, Some(timezone.as_str()));
    let from_day = date_plus_days_ymd_for_conn_at(conn, now, -(span_days - 1))?;
    let next_day = date_plus_days_ymd_for_conn_at(conn, now, 1)?;

    Ok(TrailingDayWindowUtcBounds {
        start_utc: utc_start_of_day_for_timezone_name(&from_day, &timezone)?,
        end_utc: utc_start_of_day_for_timezone_name(&next_day, &timezone)?,
        from_day,
        to_day,
    })
}

#[cfg(test)]
mod tests;
