//! TZID resolution + ICS datetime parsing.
//!
//! ICS feeds from Outlook / Exchange commonly emit Windows display
//! names (e.g. `Pacific Standard Time`) in TZID parameters instead of
//! IANA identifiers; chrono-tz only recognizes the IANA form, so a
//! `resolve_tzid_to_iana` lookup table maps the common Windows names
//! through to their IANA equivalents. Unknown TZIDs are reported to
//! the caller-supplied [`UnknownTzidSink`] (typically writing a
//! `warn`-level row into `error_logs` on the Tauri side) and fall
//! through to UTC so events still appear, just at a possibly-wrong
//! wall-clock time.
//!
//! Per-feed `BEGIN:VTIMEZONE` blocks are consulted before the IANA /
//! Windows-shim path. The registry lives next door in
//! [`super::vtimezone::VTimezoneRegistry`]; callers without a feed-local
//! VTIMEZONE block pass `None` to skip that resolution step.

use chrono::{Duration, NaiveDate, NaiveDateTime, NaiveTime};

use super::vtimezone::VTimezoneRegistry;

/// Parsed result from an ICS datetime value (DATE or DATE-TIME),
/// preserving the original timezone semantics per RFC 5545.
#[derive(Debug)]
pub struct IcsDateTime {
    pub date: Option<String>, // YYYY-MM-DD
    pub time: Option<String>, // HH:MM
    pub all_day: bool,
    pub source_time_kind: String,    // "floating" | "utc" | "tzid"
    pub source_tzid: Option<String>, // e.g. "America/New_York"
}

/// Receiver for unknown-TZID diagnostics. The default policy on the
/// Tauri side is to write a `warn`-level row into `error_logs`
/// (best-effort, logging failures swallowed). Workflow accepts the
/// sink as a callback so this module stays free of storage / IO
/// concerns and can be exercised in tests without a database.
pub type UnknownTzidSink<'a> = &'a dyn Fn(&str);

/// No-op sink for callers that don't care about unknown-TZID
/// diagnostics (typically tests).
pub const fn noop_unknown_tzid_sink(_tzid: &str) {}

pub fn extract_tzid_from_key(key: &str) -> Option<String> {
    for param in key.split(';').skip(1) {
        if let Some(tzid) = param.strip_prefix("TZID=") {
            // Strip surrounding quotes (Outlook emits TZID="America/New_York")
            let tzid = tzid.trim_matches('"');
            return Some(tzid.to_string());
        }
    }
    None
}

/// Map a TZID string to a canonical IANA zone name that chrono-tz can resolve.
///
/// Resolution order:
/// 1. If `tzid` parses directly as a chrono-tz `Tz`, it's already IANA —
///    return it unchanged.
/// 2. Otherwise, look it up in the Windows → IANA table.
/// 3. If neither resolves, return `None` so the caller logs and falls
///    back to UTC.
pub fn resolve_tzid_to_iana(tzid: &str) -> Option<&'static str> {
    // Fast path: already a valid IANA identifier.
    if let Ok(tz) = tzid.parse::<chrono_tz::Tz>() {
        return Some(tz.name());
    }

    let key = tzid.trim();
    match key {
        // ── North America ──────────────────────────────────────────
        "Pacific Standard Time" | "Pacific Daylight Time" => Some("America/Los_Angeles"),
        "Mountain Standard Time" | "Mountain Daylight Time" => Some("America/Denver"),
        "US Mountain Standard Time" => Some("America/Phoenix"),
        "Central Standard Time" | "Central Daylight Time" => Some("America/Chicago"),
        "Central Standard Time (Mexico)" | "Mexico Standard Time" => Some("America/Mexico_City"),
        "Canada Central Standard Time" => Some("America/Regina"),
        "Eastern Standard Time" | "Eastern Daylight Time" => Some("America/New_York"),
        "US Eastern Standard Time" => Some("America/Indianapolis"),
        "Atlantic Standard Time" => Some("America/Halifax"),
        "Newfoundland Standard Time" => Some("America/St_Johns"),
        "Alaskan Standard Time" => Some("America/Anchorage"),
        "Hawaiian Standard Time" => Some("Pacific/Honolulu"),

        // ── South America ──────────────────────────────────────────
        "SA Pacific Standard Time" => Some("America/Bogota"),
        "SA Western Standard Time" => Some("America/La_Paz"),
        "SA Eastern Standard Time" => Some("America/Cayenne"),
        "E. South America Standard Time" => Some("America/Sao_Paulo"),
        "Argentina Standard Time" => Some("America/Buenos_Aires"),
        "Pacific SA Standard Time" => Some("America/Santiago"),

        // ── Europe & Africa ────────────────────────────────────────
        "GMT Standard Time" => Some("Europe/London"),
        "Greenwich Standard Time" => Some("Atlantic/Reykjavik"),
        "W. Europe Standard Time" => Some("Europe/Berlin"),
        "Central Europe Standard Time" => Some("Europe/Budapest"),
        "Romance Standard Time" => Some("Europe/Paris"),
        "Central European Standard Time" => Some("Europe/Warsaw"),
        "E. Europe Standard Time" => Some("Europe/Chisinau"),
        "GTB Standard Time" => Some("Europe/Bucharest"),
        "FLE Standard Time" => Some("Europe/Kiev"),
        "Russian Standard Time" => Some("Europe/Moscow"),
        "Russia Time Zone 3" => Some("Europe/Samara"),
        "Turkey Standard Time" => Some("Europe/Istanbul"),
        "Israel Standard Time" => Some("Asia/Jerusalem"),
        "Egypt Standard Time" => Some("Africa/Cairo"),
        "South Africa Standard Time" => Some("Africa/Johannesburg"),
        "W. Central Africa Standard Time" => Some("Africa/Lagos"),
        "E. Africa Standard Time" => Some("Africa/Nairobi"),
        "Morocco Standard Time" => Some("Africa/Casablanca"),

        // ── Asia ───────────────────────────────────────────────────
        "Arabian Standard Time" => Some("Asia/Dubai"),
        "Arab Standard Time" => Some("Asia/Riyadh"),
        "Arabic Standard Time" => Some("Asia/Baghdad"),
        "Iran Standard Time" => Some("Asia/Tehran"),
        "Pakistan Standard Time" => Some("Asia/Karachi"),
        "India Standard Time" => Some("Asia/Kolkata"),
        "Sri Lanka Standard Time" => Some("Asia/Colombo"),
        "Nepal Standard Time" => Some("Asia/Kathmandu"),
        "Bangladesh Standard Time" => Some("Asia/Dhaka"),
        "Myanmar Standard Time" => Some("Asia/Yangon"),
        "SE Asia Standard Time" => Some("Asia/Bangkok"),
        "China Standard Time" => Some("Asia/Shanghai"),
        "North Asia Standard Time" => Some("Asia/Krasnoyarsk"),
        "North Asia East Standard Time" => Some("Asia/Irkutsk"),
        "Singapore Standard Time" => Some("Asia/Singapore"),
        "Taipei Standard Time" => Some("Asia/Taipei"),
        "Ulaanbaatar Standard Time" => Some("Asia/Ulaanbaatar"),
        "W. Mongolia Standard Time" => Some("Asia/Hovd"),
        "Tokyo Standard Time" => Some("Asia/Tokyo"),
        "Korea Standard Time" => Some("Asia/Seoul"),

        // ── Australia & Pacific ────────────────────────────────────
        "W. Australia Standard Time" => Some("Australia/Perth"),
        "Cen. Australia Standard Time" => Some("Australia/Adelaide"),
        "AUS Central Standard Time" => Some("Australia/Darwin"),
        "E. Australia Standard Time" => Some("Australia/Brisbane"),
        "AUS Eastern Standard Time" => Some("Australia/Sydney"),
        "Tasmania Standard Time" => Some("Australia/Hobart"),
        "New Zealand Standard Time" => Some("Pacific/Auckland"),
        "Fiji Standard Time" => Some("Pacific/Fiji"),
        "Samoa Standard Time" => Some("Pacific/Apia"),
        "Tonga Standard Time" => Some("Pacific/Tongatapu"),

        // ── UTC / GMT sentinels ────────────────────────────────────
        "UTC" | "Coordinated Universal Time" => Some("UTC"),
        "GMT" => Some("Etc/GMT"),

        _ => None,
    }
}

/// Parse an ICS datetime value (DATE or DATE-TIME), preserving timezone
/// semantics from the property key parameters (TZID) and the value suffix (Z).
///
/// `key` is the full ICS property key including params (e.g.
/// `DTSTART;TZID=America/New_York`). `value` is the raw datetime value
/// (e.g. `20260318T100000` or `20260318T100000Z`).
///
/// Thin wrapper that runs the registry-aware parser with no
/// VTIMEZONE registry and a no-op unknown-TZID sink — intended for
/// unit tests that exercise the IANA / Windows-shim lookup in
/// isolation. Production paths must use [`parse_ics_datetime_with_registry`]
/// so VTIMEZONE-first resolution applies and unknown TZIDs reach the
/// diagnostic log.
pub fn parse_ics_datetime(key: &str, value: &str) -> Result<IcsDateTime, String> {
    parse_ics_datetime_with_registry(key, value, None, &noop_unknown_tzid_sink)
}

/// Registry-aware ICS datetime parser. When a feed declares its own
/// `BEGIN:VTIMEZONE` block (surfaced through `registry`), the
/// resolver consults the registry FIRST. If a matching entry exists,
/// the wall-clock time is converted to UTC using the VTIMEZONE-derived
/// offset and emitted as `source_time_kind="utc"` (no `source_tzid`).
/// This makes downstream projection correct even when the feed's
/// TZID has no IANA equivalent (Outlook custom names, self-hosted
/// calendar servers shipping `/example.com/Custom_Zone/...`, etc.).
///
/// Resolution order, evaluated in sequence:
/// 1. Per-feed VTIMEZONE registry (via `registry`).
/// 2. chrono-tz IANA lookup (verbatim TZID).
/// 3. Windows display-name → IANA shim ([`resolve_tzid_to_iana`]).
/// 4. Unknown-TZID fallback to UTC — `unknown_tzid_sink` is invoked
///    with the raw TZID so the surface adapter can log or surface
///    the diagnostic.
///
/// Callers without a feed-local VTIMEZONE block pass `None` for
/// `registry` to skip the registry path entirely.
pub fn parse_ics_datetime_with_registry(
    key: &str,
    value: &str,
    registry: Option<&VTimezoneRegistry>,
    unknown_tzid_sink: UnknownTzidSink<'_>,
) -> Result<IcsDateTime, String> {
    let raw_tzid = extract_tzid_from_key(key);

    // VTIMEZONE blocks are consulted FIRST. If the
    // feed defines this TZID, we don't bother with chrono-tz at
    // all — we materialize the wall-clock value into a UTC
    // instant using the registry's offset at that moment.
    if let (Some(raw), Some(reg)) = (raw_tzid.as_deref(), registry) {
        if !reg.is_empty() {
            if let Some(parsed) = try_resolve_via_vtimezone(reg, raw, value)? {
                return Ok(parsed);
            }
        }
    }

    // Normalize TZID via the IANA / Windows-shim path.
    let (tzid, tzid_was_unknown) = match raw_tzid.as_deref() {
        Some(raw) => {
            if let Some(iana) = resolve_tzid_to_iana(raw) {
                (Some(iana.to_string()), false)
            } else {
                unknown_tzid_sink(raw);
                (None, true)
            }
        }
        None => (None, false),
    };

    // DATE format: YYYYMMDD (8 chars, all day).
    if value.len() == 8 {
        let parsed = NaiveDate::parse_from_str(value, "%Y%m%d")
            .map_err(|e| format!("invalid DATE value `{value}`: {e}"))?;
        return Ok(IcsDateTime {
            date: Some(parsed.format("%Y-%m-%d").to_string()),
            time: None,
            all_day: true,
            source_time_kind: "floating".to_string(),
            source_tzid: None,
        });
    }

    // DATE-TIME format: YYYYMMDDTHHMMSS or YYYYMMDDTHHMMSSZ
    if (value.len() == 15 || value.len() == 16) && value.as_bytes().get(8) == Some(&b'T') {
        let date_str = value.get(..8).ok_or_else(|| {
            format!("invalid DATE-TIME value `{value}`: non-ASCII byte in date region")
        })?;
        let time_str = value.get(9..15).ok_or_else(|| {
            format!("invalid DATE-TIME value `{value}`: non-ASCII byte in time region")
        })?;
        let parsed_date = NaiveDate::parse_from_str(date_str, "%Y%m%d")
            .map_err(|e| format!("invalid DATE-TIME date `{value}`: {e}"))?;
        let parsed_time = NaiveTime::parse_from_str(time_str, "%H%M%S")
            .map_err(|e| format!("invalid DATE-TIME time `{value}`: {e}"))?;
        let has_utc_suffix = value.len() == 16 && value.ends_with('Z');
        if value.len() == 16 && !has_utc_suffix {
            return Err(format!(
                "invalid DATE-TIME value `{value}`: trailing suffix must be `Z`"
            ));
        }

        let (source_time_kind, source_tzid) = if tzid.is_some() {
            ("tzid".to_string(), tzid)
        } else if has_utc_suffix || tzid_was_unknown {
            // Unknown-TZID fallback: treat as UTC so the projection layer
            // still emits an event rather than dropping it silently.
            ("utc".to_string(), None)
        } else {
            ("floating".to_string(), None)
        };

        return Ok(IcsDateTime {
            date: Some(parsed_date.format("%Y-%m-%d").to_string()),
            time: Some(parsed_time.format("%H:%M").to_string()),
            all_day: false,
            source_time_kind,
            source_tzid,
        });
    }

    Err(format!("invalid ICS datetime `{value}`"))
}

/// Attempt to resolve a DATE-TIME value via the per-feed VTIMEZONE
/// registry. Returns:
/// - `Ok(Some(parsed))` if `tzid` is defined in the registry and the
///   value parses cleanly. The wall-clock instant is shifted to UTC
///   using the offset the registry reports at that local time, and
///   the result is emitted as `source_time_kind="utc"`.
/// - `Ok(None)` if the registry has no definition for `tzid` (so the
///   caller falls back to the IANA / Windows-shim path).
/// - `Err(_)` only on a structurally invalid value — the caller will
///   surface the same error it would for any malformed datetime.
///
/// `value` may be a DATE (`YYYYMMDD`) or DATE-TIME (`YYYYMMDDTHHMMSS`).
/// All-day DATE values intentionally bypass the registry — they have
/// no time-of-day to convert and stay floating per RFC 5545.
fn try_resolve_via_vtimezone(
    registry: &VTimezoneRegistry,
    raw_tzid: &str,
    value: &str,
) -> Result<Option<IcsDateTime>, String> {
    // All-day values stay floating; the registry only governs
    // datetime resolution.
    if value.len() == 8 {
        return Ok(None);
    }
    if (value.len() != 15 && value.len() != 16) || value.as_bytes().get(8) != Some(&b'T') {
        return Ok(None);
    }
    // A `Z` suffix means the value is already UTC; the registry
    // offset would be wrong to apply.
    if value.len() == 16 && value.ends_with('Z') {
        return Ok(None);
    }

    let date_str = value
        .get(..8)
        .ok_or_else(|| format!("invalid DATE-TIME value `{value}`"))?;
    let time_str = value
        .get(9..15)
        .ok_or_else(|| format!("invalid DATE-TIME value `{value}`"))?;
    let parsed_date = NaiveDate::parse_from_str(date_str, "%Y%m%d")
        .map_err(|e| format!("invalid DATE-TIME date `{value}`: {e}"))?;
    let parsed_time = NaiveTime::parse_from_str(time_str, "%H%M%S")
        .map_err(|e| format!("invalid DATE-TIME time `{value}`: {e}"))?;
    let local_naive = NaiveDateTime::new(parsed_date, parsed_time);

    let Some(offset_seconds) = registry.offset_seconds_at(raw_tzid, local_naive) else {
        return Ok(None);
    };

    // wall-clock + offset_to(seconds east of UTC) → UTC by subtracting
    // the offset. e.g., 10:00 EDT (offset -14400) → 14:00 UTC.
    let utc_naive = local_naive - Duration::seconds(offset_seconds as i64);

    Ok(Some(IcsDateTime {
        date: Some(utc_naive.date().format("%Y-%m-%d").to_string()),
        time: Some(utc_naive.time().format("%H:%M").to_string()),
        all_day: false,
        source_time_kind: "utc".to_string(),
        source_tzid: None,
    }))
}
