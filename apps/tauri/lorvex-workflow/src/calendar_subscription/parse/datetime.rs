use super::super::tzid::{parse_ics_datetime_with_registry, IcsDateTime, UnknownTzidSink};
use super::super::vtimezone::VTimezoneRegistry;

/// turn a single EXDATE/RDATE value into the
/// canonical `YYYY-MM-DD` form using the same TZID resolution path
/// DTSTART uses. Returns None for malformed values so the caller can
/// silently skip them — matching the surrounding "ignore one bad
/// EXDATE / RDATE rather than fail the whole feed" policy.
///
/// Both the registry-aware path and the chrono-tz / Windows-shim
/// fallback convert wall-clock-in-zone to UTC before emitting the
/// date. That guarantees the recurrence engine — which matches
/// exceptions against UTC instances — sees the right anchor even
/// when the local time crosses midnight in UTC.
pub(super) fn normalize_ics_datetime_to_date(
    key: &str,
    raw_value: &str,
    registry: Option<&VTimezoneRegistry>,
    unknown_tzid_sink: UnknownTzidSink<'_>,
) -> Option<String> {
    let parsed =
        parse_ics_datetime_with_registry(key, raw_value, registry, unknown_tzid_sink).ok()?;
    // The registry path already shifts to UTC and emits source_time_kind
    // = "utc". The chrono-tz path returns source_time_kind = "tzid"
    // with the wall-clock date untouched — we have to do the shift here
    // ourselves so EXDATE/RDATE collate to the same UTC instant
    // DTSTART would.
    if parsed.source_time_kind == "tzid" && !parsed.all_day {
        if let Some(utc) = shift_wall_clock_to_utc_via_chrono_tz(&parsed) {
            return Some(utc);
        }
    }
    parsed.date
}

/// canonicalize a RECURRENCE-ID value so the
/// composite UID + RECURRENCE-ID key is stable across feeds that
/// describe the same overridden occurrence using different time
/// representations.
///
/// Resolution order mirrors `normalize_ics_datetime_to_date`:
/// 1. Through the per-feed VTIMEZONE registry / IANA shim → emit
///    `YYYYMMDDTHHMMSSZ` (UTC) so floating, TZID, and Z-suffixed
///    forms all collapse to the same string.
/// 2. All-day DATE-only forms → emit the bare `YYYYMMDD` per RFC 5545.
/// 3. Anything we can't parse → return the raw value untouched, so the
///    override at least addresses _something_ rather than vanishing.
pub(super) fn normalize_recurrence_id(
    key: &str,
    raw_value: &str,
    registry: Option<&VTimezoneRegistry>,
    unknown_tzid_sink: UnknownTzidSink<'_>,
) -> String {
    let Ok(parsed) = parse_ics_datetime_with_registry(key, raw_value, registry, unknown_tzid_sink)
    else {
        return raw_value.to_string();
    };
    if parsed.all_day {
        return parsed
            .date
            .as_deref()
            .map_or_else(|| raw_value.to_string(), |d| d.replace('-', ""));
    }
    // Materialize TZID-anchored times into UTC so two feeds describing
    // the same overridden instant collapse to the same composite key.
    if parsed.source_time_kind == "tzid" {
        if let Some(utc_date) = shift_wall_clock_to_utc_via_chrono_tz(&parsed) {
            // Re-derive the time-of-day in UTC. The shift helper only
            // returns the date; we need the full datetime here.
            if let Some(wire) = format_recurrence_id_utc(&parsed, &utc_date) {
                return wire;
            }
        }
    }
    match (parsed.date.as_deref(), parsed.time.as_deref()) {
        (Some(date), Some(time)) => {
            let date_compact = date.replace('-', "");
            let time_compact = time.replace(':', "") + "00";
            if parsed.source_time_kind == "utc" {
                format!("{date_compact}T{time_compact}Z")
            } else {
                format!("{date_compact}T{time_compact}")
            }
        }
        _ => raw_value.to_string(),
    }
}

/// Helper: when chrono-tz can resolve the parsed TZID, shift the
/// wall-clock instant to UTC and return the UTC date as `YYYY-MM-DD`.
/// Returns None when the TZID is unknown to chrono-tz, when the local
/// time is ambiguous (DST overlap), or when the date/time fields are
/// missing.
fn shift_wall_clock_to_utc_via_chrono_tz(parsed: &IcsDateTime) -> Option<String> {
    use chrono::TimeZone;

    let tzid = parsed.source_tzid.as_deref()?;
    let tz: chrono_tz::Tz = tzid.parse().ok()?;
    let date_str = parsed.date.as_deref()?;
    let time_str = parsed.time.as_deref()?;
    let date = chrono::NaiveDate::parse_from_str(date_str, "%Y-%m-%d").ok()?;
    let time = chrono::NaiveTime::parse_from_str(time_str, "%H:%M").ok()?;
    let local = chrono::NaiveDateTime::new(date, time);
    // `from_local_datetime` returns `LocalResult::Single` on the common
    // path; for ambiguous (fall-back DST overlap) or none (spring-forward
    // gap) cases we deliberately decline to guess and fall through to
    // the raw wall-clock value.
    let local_dt = match tz.from_local_datetime(&local) {
        chrono::LocalResult::Single(dt) => dt,
        chrono::LocalResult::Ambiguous(earliest, _) => earliest,
        chrono::LocalResult::None => return None,
    };
    let utc = local_dt.with_timezone(&chrono::Utc);
    Some(utc.format("%Y-%m-%d").to_string())
}

/// Helper: derive the full UTC RECURRENCE-ID wire form
/// (`YYYYMMDDTHHMMSSZ`) when the chrono-tz UTC date is known.
fn format_recurrence_id_utc(parsed: &IcsDateTime, _utc_date: &str) -> Option<String> {
    use chrono::TimeZone;
    let tzid = parsed.source_tzid.as_deref()?;
    let tz: chrono_tz::Tz = tzid.parse().ok()?;
    let date_str = parsed.date.as_deref()?;
    let time_str = parsed.time.as_deref()?;
    let date = chrono::NaiveDate::parse_from_str(date_str, "%Y-%m-%d").ok()?;
    let time = chrono::NaiveTime::parse_from_str(time_str, "%H:%M").ok()?;
    let local = chrono::NaiveDateTime::new(date, time);
    let local_dt = match tz.from_local_datetime(&local) {
        chrono::LocalResult::Single(dt) => dt,
        chrono::LocalResult::Ambiguous(earliest, _) => earliest,
        chrono::LocalResult::None => return None,
    };
    let utc = local_dt.with_timezone(&chrono::Utc);
    Some(utc.format("%Y%m%dT%H%M%SZ").to_string())
}
