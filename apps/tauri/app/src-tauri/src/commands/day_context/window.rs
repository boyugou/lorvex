use crate::error::{AppError, AppResult};

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct TrailingDayWindowUtcBounds {
    pub(crate) from_day: String,
    pub(crate) to_day: String,
    pub(crate) start_utc: String,
    pub(crate) end_utc: String,
}

/// Maximum number of consecutive skipped local days to probe when looking for
/// the earliest valid local instant. Real-world date-line skips (e.g.
/// Pacific/Apia 2011-12-30) span exactly one day; we cap at 3 for defense.
const MAX_SKIPPED_DAY_FALLBACK: i64 = 3;

/// Returns the earliest UTC instant corresponding to the start of `day` in
/// `timezone`. If the entire local day was skipped (e.g. Pacific/Apia skipped
/// 2011-12-30 when it crossed the international date line), this falls back
/// to the START of the next valid local day so that callers receive a
/// deterministic UTC boundary instead of an error.
fn first_valid_utc_for_local_day<Tz: chrono::TimeZone>(
    day: chrono::NaiveDate,
    timezone: &Tz,
) -> Option<chrono::DateTime<chrono::Utc>> {
    for day_offset in 0..=MAX_SKIPPED_DAY_FALLBACK {
        let probe_day = day.checked_add_signed(chrono::Duration::days(day_offset))?;
        if let Some(value) = first_valid_utc_on(probe_day, timezone) {
            return Some(value);
        }
    }
    None
}

fn first_valid_utc_on<Tz: chrono::TimeZone>(
    day: chrono::NaiveDate,
    timezone: &Tz,
) -> Option<chrono::DateTime<chrono::Utc>> {
    // Issue #2389 note: deliberately not routed through
    // `lorvex_domain::dst::resolve_local_datetime`. This function
    // probes a whole 24-hour local day looking for the FIRST valid
    // wall-clock instant — that's the opposite policy from the
    // per-call-site DST guard, which rejects user-supplied skipped
    // times. Midnight is never in a real-world DST gap (gaps live at
    // 02:00 / 03:00), so the `None` branches below only matter for
    // rare date-line skips like Pacific/Apia 2011-12-30, where the
    // per-minute probe is specifically what we want.
    let midnight = day.and_hms_opt(0, 0, 0)?;
    for minute_offset in 0..(24 * 60) {
        let candidate = midnight + chrono::Duration::minutes(i64::from(minute_offset));
        match timezone.from_local_datetime(&candidate) {
            chrono::LocalResult::Single(value) => return Some(value.with_timezone(&chrono::Utc)),
            chrono::LocalResult::Ambiguous(first, second) => {
                let first_utc = first.with_timezone(&chrono::Utc);
                let second_utc = second.with_timezone(&chrono::Utc);
                return Some(if first_utc <= second_utc {
                    first_utc
                } else {
                    second_utc
                });
            }
            chrono::LocalResult::None => continue,
        }
    }
    None
}

fn utc_start_of_day_for_timezone_name(day: &str, timezone_name: Option<&str>) -> AppResult<String> {
    let parsed_day = chrono::NaiveDate::parse_from_str(day, "%Y-%m-%d")
        .map_err(|_| AppError::Validation(format!("invalid local day boundary '{day}'")))?;
    let utc_value =
        if let Some(timezone) = timezone_name.and_then(lorvex_domain::parse_timezone_name) {
            first_valid_utc_for_local_day(parsed_day, &timezone)
        } else {
            first_valid_utc_for_local_day(parsed_day, &chrono::Local)
        }
        .ok_or_else(|| {
            AppError::Internal(format!(
                "could not resolve UTC boundary for local day '{day}': \
                 every probed day was skipped by the timezone"
            ))
        })?;

    // Use the canonical fractional `Z` form so day-boundary strings compare
    // correctly against timestamp columns written through `sync_timestamp_now`.
    Ok(lorvex_domain::format_sync_timestamp(utc_value))
}

pub(crate) fn trailing_day_window_bounds_for_conn(
    conn: &rusqlite::Connection,
    span_days: i64,
) -> AppResult<TrailingDayWindowUtcBounds> {
    trailing_day_window_bounds_for_conn_at(conn, chrono::Utc::now(), span_days)
}

pub(crate) fn trailing_day_window_bounds_for_conn_at(
    conn: &rusqlite::Connection,
    now: chrono::DateTime<chrono::Utc>,
    span_days: i64,
) -> AppResult<TrailingDayWindowUtcBounds> {
    if span_days < 1 {
        return Err(AppError::Validation(
            "trailing day window must cover at least one day".to_string(),
        ));
    }

    let timezone = lorvex_workflow::timezone::active_timezone_name(conn)?;
    let to_day = lorvex_domain::today_ymd_for_timezone_name(now, timezone.as_deref());
    let from_day = lorvex_domain::date_plus_days_ymd_for_timezone_name(
        now,
        timezone.as_deref(),
        -(span_days - 1),
    );
    let next_day = lorvex_domain::date_plus_days_ymd_for_timezone_name(now, timezone.as_deref(), 1);

    Ok(TrailingDayWindowUtcBounds {
        start_utc: utc_start_of_day_for_timezone_name(&from_day, timezone.as_deref())?,
        end_utc: utc_start_of_day_for_timezone_name(&next_day, timezone.as_deref())?,
        from_day,
        to_day,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Pacific/Apia skipped the whole calendar day 2011-12-30 when Samoa
    /// crossed the international date line at 00:00 local on the 30th. The
    /// window helper must not error on that day — it should instead return
    /// the first valid instant of the following (31st) local day.
    #[test]
    fn first_valid_utc_falls_back_across_skipped_apia_day() {
        let tz = lorvex_domain::parse_timezone_name("Pacific/Apia")
            .expect("chrono-tz resolves Pacific/Apia");
        let skipped = chrono::NaiveDate::from_ymd_opt(2011, 12, 30).unwrap();
        let resolved = first_valid_utc_for_local_day(skipped, &tz).expect("fallback returns Some");
        // The next valid local day in Apia after the skip is 2011-12-31.
        // Its local midnight is 2011-12-30T10:00:00Z in UTC (UTC+14).
        let expected = chrono::DateTime::parse_from_rfc3339("2011-12-30T10:00:00Z")
            .unwrap()
            .with_timezone(&chrono::Utc);
        assert_eq!(resolved, expected);
    }

    #[test]
    fn first_valid_utc_non_skipped_day_returns_local_midnight() {
        let tz = lorvex_domain::parse_timezone_name("America/Los_Angeles").unwrap();
        let day = chrono::NaiveDate::from_ymd_opt(2026, 3, 15).unwrap();
        let resolved = first_valid_utc_for_local_day(day, &tz).unwrap();
        // 2026-03-15 LA is PDT (UTC-7) -> local midnight is 07:00Z.
        let expected = chrono::DateTime::parse_from_rfc3339("2026-03-15T07:00:00Z")
            .unwrap()
            .with_timezone(&chrono::Utc);
        assert_eq!(resolved, expected);
    }

    /// Regression: `utc_start_of_day_for_timezone_name` must emit the
    /// canonical fractional `Z` form (`"T00:00:00.000Z"`) so downstream
    /// SQL WHERE clauses that lex-compare against canonical timestamp
    /// columns (`completed_at`, etc.) correctly include rows at or just
    /// past the boundary. A non-fractional `"T00:00:00Z"` lex-sorts
    /// AFTER `"T00:00:00.000Z"` at position 19 (`.` < `Z`), so
    /// `WHERE col >= start_of_day` would exclude rows recorded at
    /// exactly local midnight — tasks completed at the boundary would
    /// drop out of the "completed today" overview count and the
    /// weekly review window.
    #[test]
    fn utc_start_of_day_emits_canonical_fractional_format_for_lex_compat() {
        let result = utc_start_of_day_for_timezone_name("2026-03-15", Some("UTC"))
            .expect("utc timezone always resolves");
        assert!(
            result.contains(".000"),
            "start-of-day cutoff must include fractional zeros for lex \
             compatibility with canonical timestamp columns; got: {result}"
        );
        assert!(
            result.ends_with('Z'),
            "start-of-day cutoff must end with `Z` to match sync_timestamp_now format; got: {result}"
        );

        // Boundary check: a canonical row at exactly this cutoff time must
        // satisfy `column >= cutoff` via SQL string comparison, which requires
        // both sides to share the fractional-second prefix format.
        let column_exact_midnight = "2026-03-15T00:00:00.000Z";
        assert!(
            column_exact_midnight >= result.as_str(),
            "a row at exact midnight must be >= the cutoff via lex comparison; \
             column={column_exact_midnight}, cutoff={result}"
        );

        let column_next_millisecond = "2026-03-15T00:00:00.001Z";
        assert!(
            column_next_millisecond >= result.as_str(),
            "a row 1ms past midnight must be >= the cutoff via lex comparison; \
             column={column_next_millisecond}, cutoff={result}"
        );
    }
}
