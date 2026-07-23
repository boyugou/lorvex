//! Per-field RRULE parsers.
//!
//! Each function reads one RRULE key off the parsed JSON object,
//! validates it against RFC 5545 §3.3.10 + the FREQ-specific rules,
//! and returns the canonical normalized value. Errors carry the
//! caller's actual input verbatim so the validator's error text shows
//! the user what they typed, not what we coerced it to.

use super::helpers::{canonical_byday_sort_key, parse_int_array, parse_until_to_ymd};
use crate::validation::error::ValidationError;
use crate::validation::recurrence::{
    is_valid_byday_code, is_valid_byday_token_for_freq, VALID_RECURRENCE_FREQS,
};

/// Parse + validate `FREQ`. Required field; must be one of the
/// allowlisted frequencies. Returns the borrowed string slice from the
/// parent JSON object.
pub(super) fn parse_freq<'a>(
    parsed: &'a serde_json::Value,
    recurrence: &str,
) -> Result<&'a str, ValidationError> {
    let freq = parsed.get("FREQ").and_then(|v| v.as_str()).ok_or_else(|| {
        ValidationError::InvalidFormat {
            field: "recurrence",
            expected: "FREQ field (DAILY/WEEKLY/MONTHLY/YEARLY)",
            actual: recurrence.to_string(),
        }
    })?;
    if !VALID_RECURRENCE_FREQS.contains(&freq) {
        return Err(ValidationError::InvalidFormat {
            field: "recurrence",
            expected: "FREQ must be DAILY, WEEKLY, MONTHLY, or YEARLY",
            actual: freq.to_string(),
        });
    }
    Ok(freq)
}

/// Parse `INTERVAL` (default 1, must be a positive integer).
///
/// Strict typing — a fractional or string `INTERVAL` is rejected with
/// the user's actual input in the error rather than silently coerced
/// to 0 and then rejected as "must be a positive integer".
pub(super) fn parse_interval(parsed: &serde_json::Value) -> Result<i64, ValidationError> {
    let interval = if let Some(val) = parsed.get("INTERVAL") {
        val.as_i64().ok_or_else(|| ValidationError::InvalidFormat {
            field: "recurrence",
            expected: "INTERVAL must be a positive integer",
            actual: val.to_string(),
        })?
    } else {
        1
    };
    if interval < 1 {
        return Err(ValidationError::InvalidFormat {
            field: "recurrence",
            expected: "INTERVAL must be a positive integer",
            actual: interval.to_string(),
        });
    }
    Ok(interval)
}

/// Parse `BYDAY`. Must be an array; valid for `WEEKLY` (bare codes
/// only), `MONTHLY` (codes optionally prefixed with `[+-]?1..=5`), and
/// `YEARLY` (codes optionally prefixed with `[+-]?1..=53`). The
/// returned vec is sorted + deduplicated by
/// [`canonical_byday_sort_key`] so two devices that author the same
/// logical rule in different input orders converge on byte-identical
/// canonical JSON.
pub(super) fn parse_byday(
    parsed: &serde_json::Value,
    freq: &str,
) -> Result<Option<Vec<String>>, ValidationError> {
    let Some(byday_val) = parsed.get("BYDAY") else {
        return Ok(None);
    };
    let arr = byday_val
        .as_array()
        .ok_or_else(|| ValidationError::InvalidFormat {
            field: "recurrence",
            expected: "BYDAY must be an array of weekday codes",
            actual: byday_val.to_string(),
        })?;
    if !arr.is_empty() && !matches!(freq, "WEEKLY" | "MONTHLY" | "YEARLY") {
        return Err(ValidationError::InvalidFormat {
            field: "recurrence",
            expected: "BYDAY is only valid for WEEKLY, MONTHLY, or YEARLY recurrence",
            actual: format!("FREQ={freq} with BYDAY"),
        });
    }
    let mut codes: Vec<String> = Vec::with_capacity(arr.len());
    for code in arr {
        let s = code
            .as_str()
            .ok_or_else(|| ValidationError::InvalidFormat {
                field: "recurrence",
                expected: "BYDAY elements must be strings",
                actual: code.to_string(),
            })?;
        // ordinal handling (sign, magnitude, FREQ gating) lives entirely
        // inside `is_valid_byday_token_for_freq` so the rule lives in
        // one place. WEEKLY rejects every prefixed form, MONTHLY caps
        // the absolute value at 5, YEARLY caps it at 53.
        if !is_valid_byday_token_for_freq(s, freq) {
            let expected: &'static str = match freq {
                "WEEKLY" => {
                    "BYDAY codes must be MO/TU/WE/TH/FR/SA/SU (WEEKLY rejects ordinal prefixes)"
                }
                "MONTHLY" => {
                    "BYDAY codes must be MO/TU/WE/TH/FR/SA/SU, optionally prefixed with [+-]?1..=5 for MONTHLY"
                }
                "YEARLY" => {
                    "BYDAY codes must be MO/TU/WE/TH/FR/SA/SU, optionally prefixed with [+-]?1..=53 for YEARLY"
                }
                _ => "BYDAY codes must be MO/TU/WE/TH/FR/SA/SU",
            };
            return Err(ValidationError::InvalidFormat {
                field: "recurrence",
                expected,
                actual: s.to_string(),
            });
        }
        codes.push(s.to_string());
    }
    if codes.is_empty() {
        return Ok(None);
    }
    codes.sort_by_key(|code| canonical_byday_sort_key(code));
    codes.dedup();
    Ok(Some(codes))
}

/// Parse `BYSETPOS`. Per RFC 5545 §3.3.10, integers in
/// `-366..=-1 ∪ 1..=366`. Selects the Nth occurrence in a
/// frequency-defined set (the set is built by combining the other BY*
/// parts). Only meaningful for MONTHLY/YEARLY.
pub(super) fn parse_bysetpos(
    parsed: &serde_json::Value,
    freq: &str,
) -> Result<Option<Vec<i64>>, ValidationError> {
    let Some(val) = parsed.get("BYSETPOS") else {
        return Ok(None);
    };
    if matches!(freq, "DAILY" | "WEEKLY") {
        return Err(ValidationError::InvalidFormat {
            field: "recurrence",
            expected: "BYSETPOS is only supported for MONTHLY/YEARLY recurrence",
            actual: format!("FREQ={freq} with BYSETPOS"),
        });
    }
    let arr = val
        .as_array()
        .ok_or_else(|| ValidationError::InvalidFormat {
            field: "recurrence",
            expected: "BYSETPOS must be an array of integers in -366..=-1 ∪ 1..=366",
            actual: val.to_string(),
        })?;
    let mut positions: Vec<i64> = Vec::with_capacity(arr.len());
    for item in arr {
        let n = item
            .as_i64()
            .ok_or_else(|| ValidationError::InvalidFormat {
                field: "recurrence",
                expected: "BYSETPOS entries must be integers",
                actual: item.to_string(),
            })?;
        if n == 0 || !(-366..=366).contains(&n) {
            return Err(ValidationError::InvalidFormat {
                field: "recurrence",
                expected: "BYSETPOS entries must be in -366..=-1 ∪ 1..=366",
                actual: n.to_string(),
            });
        }
        positions.push(n);
    }
    if positions.is_empty() {
        return Ok(None);
    }
    // canonicalize: sort + dedup (negatives precede positives under
    // default i64 ordering, which matches the iCalendar reading order
    // for "Nth from end" → "Nth from start").
    positions.sort_unstable();
    positions.dedup();
    Ok(Some(positions))
}

/// Parse `BYMONTH`. Month-of-year filter, integers in `1..=12`.
///
/// -H2:
/// silently rejected the most common YEARLY modifier in real calendar
/// feeds (Apple/Google leap-year birthdays land as
/// `FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29`). Only meaningful for
/// non-DAILY frequencies — RFC 5545 §3.3.10 explicitly forbids
/// `BYMONTH` on `FREQ=DAILY` because the daily expansion has no
/// month-of-year boundary to filter against.
pub(super) fn parse_bymonth(
    parsed: &serde_json::Value,
    freq: &str,
) -> Result<Option<Vec<i64>>, ValidationError> {
    let Some(val) = parsed.get("BYMONTH") else {
        return Ok(None);
    };
    if freq == "DAILY" {
        return Err(ValidationError::InvalidFormat {
            field: "recurrence",
            expected: "BYMONTH is only valid for WEEKLY/MONTHLY/YEARLY recurrence",
            actual: format!("FREQ={freq} with BYMONTH"),
        });
    }
    let months = parse_int_array(val, 1, 12)?;
    if months.is_empty() {
        Ok(None)
    } else {
        Ok(Some(months))
    }
}

/// Parse `WKST`. Week-start weekday. Only meaningful for WEEKLY rules
/// with INTERVAL > 1, but RFC 5545 §3.3.10 permits it on every FREQ.
pub(super) fn parse_wkst(parsed: &serde_json::Value) -> Result<Option<String>, ValidationError> {
    let Some(val) = parsed.get("WKST") else {
        return Ok(None);
    };
    let s = val.as_str().ok_or_else(|| ValidationError::InvalidFormat {
        field: "recurrence",
        expected: "WKST must be a weekday code",
        actual: val.to_string(),
    })?;
    if !is_valid_byday_code(s) {
        return Err(ValidationError::InvalidFormat {
            field: "recurrence",
            expected: "WKST must be MO/TU/WE/TH/FR/SA/SU",
            actual: s.to_string(),
        });
    }
    Ok(Some(s.to_string()))
}

/// Parse `BYMONTHDAY` into a sorted, deduped array of month-days.
///
/// Canonical output is always an array (`[1, 15]` — "1st and 15th of
/// the month"), each entry an integer in `-31..=-1 ∪ 1..=31`. Negative
/// values count from the end of the month ("-1" = last day). A bare
/// scalar (`15`) is accepted for back-compat with rules stored before
/// the array form and normalizes to the single-element array `[15]`.
/// An empty array is treated as absent (`None`). Only valid on
/// MONTHLY/YEARLY.
///
/// Range pinned to match `lorvex_domain::calendar_ics`, which accepts
/// the full RFC range when serializing RRULEs — keeping the task
/// validator narrower would let calendar-event RRULEs round-trip
/// values that the matching task validator then rejects.
pub(super) fn parse_bymonthday(
    parsed: &serde_json::Value,
    freq: &str,
) -> Result<Option<Vec<i64>>, ValidationError> {
    let Some(val) = parsed.get("BYMONTHDAY") else {
        return Ok(None);
    };
    let mut days: Vec<i64> = if let Some(scalar) = val.as_i64() {
        vec![scalar]
    } else if let Some(arr) = val.as_array() {
        let mut xs = Vec::with_capacity(arr.len());
        for item in arr {
            let n = item
                .as_i64()
                .ok_or_else(|| ValidationError::InvalidFormat {
                    field: "recurrence",
                    expected: "BYMONTHDAY entries must be integers",
                    actual: item.to_string(),
                })?;
            xs.push(n);
        }
        xs
    } else {
        return Err(ValidationError::InvalidFormat {
            field: "recurrence",
            expected: "BYMONTHDAY must be an integer or array of integers in -31..=31, excluding 0",
            actual: val.to_string(),
        });
    };
    for &day in &days {
        if day == 0 || !(-31..=31).contains(&day) {
            return Err(ValidationError::InvalidFormat {
                field: "recurrence",
                expected: "BYMONTHDAY must be an integer in -31..=31, excluding 0",
                actual: day.to_string(),
            });
        }
    }
    if days.is_empty() {
        return Ok(None);
    }
    if freq != "MONTHLY" && freq != "YEARLY" {
        return Err(ValidationError::InvalidFormat {
            field: "recurrence",
            expected: "BYMONTHDAY is only valid for MONTHLY/YEARLY recurrence",
            actual: format!("FREQ={freq} with BYMONTHDAY"),
        });
    }
    days.sort_unstable();
    days.dedup();
    Ok(Some(days))
}

/// Parse `UNTIL`. Accepts either RFC 5545 DATE (`YYYYMMDD`),
/// DATE-TIME (`YYYYMMDDTHHMMSSZ`), or our canonical `YYYY-MM-DD`.
/// imported calendar feed with a legitimate `UNTIL=20261231T235959Z`
/// was rejected at sync apply time. RFC 5545 §3.3.10 explicitly
/// allows both forms; normalize to the canonical `YYYY-MM-DD`
/// (date-only) for storage so downstream engines that expect that
/// shape don't have to branch.
pub(super) fn parse_until(parsed: &serde_json::Value) -> Result<Option<String>, ValidationError> {
    let Some(val) = parsed.get("UNTIL") else {
        return Ok(None);
    };
    let s = val.as_str().ok_or_else(|| ValidationError::InvalidFormat {
        field: "recurrence",
        expected: "UNTIL must be a YYYY-MM-DD or RFC5545 DATE-TIME string",
        actual: val.to_string(),
    })?;
    let canonical = parse_until_to_ymd(s).ok_or_else(|| ValidationError::InvalidFormat {
        field: "recurrence",
        expected: "UNTIL must be YYYY-MM-DD, YYYYMMDD, or YYYYMMDDTHHMMSSZ",
        actual: s.to_string(),
    })?;
    Ok(Some(canonical))
}

/// Parse `COUNT`. Positive integer.
pub(super) fn parse_count(parsed: &serde_json::Value) -> Result<Option<i64>, ValidationError> {
    let Some(val) = parsed.get("COUNT") else {
        return Ok(None);
    };
    let c = val.as_i64().ok_or_else(|| ValidationError::InvalidFormat {
        field: "recurrence",
        expected: "COUNT must be a positive integer",
        actual: val.to_string(),
    })?;
    if c < 1 {
        return Err(ValidationError::InvalidFormat {
            field: "recurrence",
            expected: "COUNT must be a positive integer",
            actual: c.to_string(),
        });
    }
    Ok(Some(c))
}
