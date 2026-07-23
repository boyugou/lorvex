//! Line-level parsers for the `BEGIN:VTIMEZONE` … `END:VTIMEZONE`
//! block + its per-property children (DTSTART, TZOFFSETFROM,
//! TZOFFSETTO, RRULE, BYDAY). Operates on the already-unfolded ICS
//! line stream produced upstream; no IO of its own.

use chrono::{NaiveDate, NaiveDateTime, NaiveTime, Weekday};

use super::types::{Observance, TimezoneRrule, VTimezoneDefinition, VTimezoneRegistry};

/// Parse every `BEGIN:VTIMEZONE` … `END:VTIMEZONE` block in the
/// already-unfolded line stream. Malformed observances are skipped
/// so a single broken block cannot poison the rest of the registry.
pub fn parse_vtimezone_blocks(unfolded_lines: &[String]) -> VTimezoneRegistry {
    let mut registry = VTimezoneRegistry::new();
    let mut i = 0;
    while i < unfolded_lines.len() {
        let line = unfolded_lines[i].trim();
        if line.eq_ignore_ascii_case("BEGIN:VTIMEZONE") {
            let (def, end) = parse_one_vtimezone(unfolded_lines, i + 1);
            if let Some((tzid, def)) = def {
                if !def.observances.is_empty() {
                    registry.by_tzid.insert(tzid, def);
                }
            }
            i = end;
        } else {
            i += 1;
        }
    }
    registry
}

/// Parse one VTIMEZONE block. Returns `(tzid, definition)` if the
/// block has a `TZID` and at least one observance, plus the line
/// index immediately after `END:VTIMEZONE`.
fn parse_one_vtimezone(
    lines: &[String],
    start: usize,
) -> (Option<(String, VTimezoneDefinition)>, usize) {
    let mut tzid: Option<String> = None;
    let mut def = VTimezoneDefinition::default();
    let mut i = start;
    while i < lines.len() {
        let line = lines[i].trim();
        if line.eq_ignore_ascii_case("END:VTIMEZONE") {
            i += 1;
            break;
        }
        if let Some(rest) = line.strip_prefix("TZID:") {
            tzid = Some(rest.trim_matches('"').to_string());
            i += 1;
            continue;
        }
        // STANDARD / DAYLIGHT sub-components.
        if line.eq_ignore_ascii_case("BEGIN:STANDARD")
            || line.eq_ignore_ascii_case("BEGIN:DAYLIGHT")
        {
            let (obs, end) = parse_one_observance(lines, i + 1);
            if let Some(obs) = obs {
                def.observances.push(obs);
            }
            i = end;
            continue;
        }
        i += 1;
    }
    match tzid {
        Some(t) => (Some((t, def)), i),
        None => (None, i),
    }
}

fn parse_one_observance(lines: &[String], start: usize) -> (Option<Observance>, usize) {
    let mut dtstart: Option<NaiveDateTime> = None;
    let mut offset_from: Option<i32> = None;
    let mut offset_to: Option<i32> = None;
    let mut rrule: Option<TimezoneRrule> = None;
    let mut i = start;

    while i < lines.len() {
        let line = lines[i].trim();
        if line.eq_ignore_ascii_case("END:STANDARD") || line.eq_ignore_ascii_case("END:DAYLIGHT") {
            i += 1;
            break;
        }

        // Property = value with optional ;-params before the colon.
        if let Some((key, value)) = line.split_once(':') {
            let prop = key.split(';').next().unwrap_or("");
            match prop.to_ascii_uppercase().as_str() {
                "DTSTART" => {
                    dtstart = parse_local_datetime(value);
                }
                "TZOFFSETFROM" => {
                    offset_from = parse_utc_offset_seconds(value);
                }
                "TZOFFSETTO" => {
                    offset_to = parse_utc_offset_seconds(value);
                }
                "RRULE" => {
                    rrule = parse_timezone_rrule(value);
                }
                _ => {}
            }
        }
        i += 1;
    }

    match (dtstart, offset_from, offset_to) {
        // `_offset_from` validates that TZOFFSETFROM was present and
        // parsed; the value itself is not retained because the
        // resolver only consumes `offset_to`.
        (Some(dtstart), Some(_offset_from), Some(offset_to)) => (
            Some(Observance {
                dtstart,
                offset_to,
                rrule,
            }),
            i,
        ),
        _ => (None, i),
    }
}

/// Parse `19710101T020000` → `NaiveDateTime`. Date-only (`YYYYMMDD`)
/// is also accepted (rare in VTIMEZONE but harmless: midnight).
fn parse_local_datetime(value: &str) -> Option<NaiveDateTime> {
    // VTIMEZONE DTSTART must be local (no `Z` / TZID per RFC 5545).
    // Strip a stray `Z` defensively if present.
    let trimmed = value.trim().trim_end_matches('Z');
    if trimmed.len() == 8 {
        let date = NaiveDate::parse_from_str(trimmed, "%Y%m%d").ok()?;
        return Some(date.and_time(NaiveTime::MIN));
    }
    if trimmed.len() == 15 && trimmed.as_bytes().get(8) == Some(&b'T') {
        let date_str = trimmed.get(..8)?;
        let time_str = trimmed.get(9..15)?;
        let date = NaiveDate::parse_from_str(date_str, "%Y%m%d").ok()?;
        let time = NaiveTime::parse_from_str(time_str, "%H%M%S").ok()?;
        return Some(date.and_time(time));
    }
    None
}

/// Parse an RFC 5545 UTC offset (`+0500`, `-0430`, `+053000`) into
/// seconds east of UTC.
pub(crate) fn parse_utc_offset_seconds(value: &str) -> Option<i32> {
    let s = value.trim();
    let (sign, rest) = match s.as_bytes().first()? {
        b'+' => (1, &s[1..]),
        b'-' => (-1, &s[1..]),
        _ => return None,
    };
    let bytes = rest.as_bytes();
    if bytes.len() != 4 && bytes.len() != 6 {
        return None;
    }
    if !bytes.iter().all(u8::is_ascii_digit) {
        return None;
    }
    let hours: i32 = rest.get(..2)?.parse().ok()?;
    let minutes: i32 = rest.get(2..4)?.parse().ok()?;
    let seconds: i32 = if bytes.len() == 6 {
        rest.get(4..6)?.parse().ok()?
    } else {
        0
    };
    Some(sign * (hours * 3600 + minutes * 60 + seconds))
}

/// Parse the subset of RRULE used inside VTIMEZONE: yearly
/// transitions described as `FREQ=YEARLY;BYMONTH=<m>;BYDAY=<n>SU`.
pub(crate) fn parse_timezone_rrule(value: &str) -> Option<TimezoneRrule> {
    let mut freq: Option<&str> = None;
    let mut by_month: Option<u32> = None;
    let mut by_day: Option<(Weekday, i32)> = None;
    let mut until: Option<NaiveDateTime> = None;

    for part in value.split(';') {
        let (k, v) = part.split_once('=')?;
        let k = k.trim().to_ascii_uppercase();
        let v = v.trim();
        match k.as_str() {
            "FREQ" => {
                freq = Some(match v {
                    "YEARLY" => "YEARLY",
                    _ => return None,
                });
            }
            "BYMONTH" => by_month = v.parse().ok(),
            "BYDAY" => by_day = parse_byday_token(v),
            "UNTIL" => {
                // UNTIL in VTIMEZONE may be local or UTC; either
                // way we just need the date for comparison.
                let trimmed = v.trim_end_matches('Z');
                until = parse_local_datetime(trimmed);
            }
            _ => {}
        }
    }

    if !matches!(freq, Some("YEARLY")) {
        return None;
    }
    let by_month = by_month?;
    let by_day = by_day?;
    if !(1..=12).contains(&by_month) {
        return None;
    }
    Some(TimezoneRrule {
        by_month,
        by_day,
        until,
    })
}

/// Parse a `BYDAY` token like `2SU`, `-1SU`, or `SU`. Returns the
/// `(Weekday, ordinal)` pair. `SU` (no ordinal) is treated as
/// "every Sunday in the month" — for VTIMEZONE that does not occur
/// in practice, so we reject it and fall back to bare DTSTART.
fn parse_byday_token(token: &str) -> Option<(Weekday, i32)> {
    let t = token.trim();
    let (num_part, day_part) = split_byday(t)?;
    let weekday = match day_part.to_ascii_uppercase().as_str() {
        "SU" => Weekday::Sun,
        "MO" => Weekday::Mon,
        "TU" => Weekday::Tue,
        "WE" => Weekday::Wed,
        "TH" => Weekday::Thu,
        "FR" => Weekday::Fri,
        "SA" => Weekday::Sat,
        _ => return None,
    };
    let n = match num_part {
        "" => return None, // bare weekday (no ordinal) is not a single transition
        s => s.parse::<i32>().ok()?,
    };
    if n == 0 {
        return None;
    }
    Some((weekday, n))
}

fn split_byday(token: &str) -> Option<(&str, &str)> {
    // Find the first ASCII-alpha character — that's where the
    // weekday code begins.
    let idx = token.find(|c: char| c.is_ascii_alphabetic())?;
    Some((&token[..idx], &token[idx..]))
}
