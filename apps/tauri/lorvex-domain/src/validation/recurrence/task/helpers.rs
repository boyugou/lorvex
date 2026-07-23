//! File-private helpers used by the per-field recurrence parsers.
//!
//! Three small utilities that the field parsers all reach for:
//!
//! - [`parse_int_array`] — JSON array → `Vec<i64>` with range clamp,
//!   sort + dedup. The sort+dedup makes two devices that author the
//!   same logical rule in different input orders converge on
//!   byte-identical canonical JSON, which is what LWW + the version
//!   stamp depend on (#2978-H2).
//! - [`canonical_byday_sort_key`] — total-order key for BYDAY tokens
//!   so `["FR","MO"]` and `["MO","FR"]` canonicalize identically.
//! - [`parse_until_to_ymd`] — accept the three RFC 5545 UNTIL forms
//!   and return our canonical `YYYY-MM-DD`.

use crate::validation::error::ValidationError;

/// Parse a JSON array of integers into a `Vec<i64>` constrained to
/// `lo..=hi`. Used by BYMONTH (and reused freely by future BY* fields
/// that share the same shape).
///
/// canonicalize the resulting vector with sort + dedup so two
/// devices that author logically-identical rules in different input
/// orders (`{BYMONTH:[2,8]}` vs `{BYMONTH:[8,2]}`) emit byte-identical
/// canonical JSON. Without this, the version-stamp / outbox payload /
/// peer apply path would diverge across devices for the same logical
/// rule, defeating LWW on every subsequent edit and producing
/// divergent `recurrence_end_date` derived values. Sort first so
/// `dedup` can collapse runs of equal entries; the resulting vec is
/// strictly ascending and unique.
pub(super) fn parse_int_array(
    val: &serde_json::Value,
    lo: i64,
    hi: i64,
) -> Result<Vec<i64>, ValidationError> {
    let arr = val
        .as_array()
        .ok_or_else(|| ValidationError::InvalidFormat {
            field: "recurrence",
            expected: "BYMONTH must be an array of integers in 1..=12",
            actual: val.to_string(),
        })?;
    let mut out = Vec::with_capacity(arr.len());
    for item in arr {
        let n = item
            .as_i64()
            .ok_or_else(|| ValidationError::InvalidFormat {
                field: "recurrence",
                expected: "BYMONTH entries must be integers",
                actual: item.to_string(),
            })?;
        if !(lo..=hi).contains(&n) {
            return Err(ValidationError::InvalidFormat {
                field: "recurrence",
                expected: "BYMONTH entries must be in 1..=12",
                actual: n.to_string(),
            });
        }
        out.push(n);
    }
    out.sort_unstable();
    out.dedup();
    Ok(out)
}

/// Canonical sort key for a single BYDAY token.
///
/// Returns `(ordinal, weekday_index)` where `ordinal` defaults to 0
/// when the token has no signed prefix, and `weekday_index` follows
/// MO=0..SU=6 (the RFC 5545 §3.3.10 ordering). This produces a stable
/// total order so two devices that emit the same logical BYDAY set in
/// different input orders converge on byte-identical canonical JSON.
///
/// Token shape: optional sign (`+`/`-`), optional 1..=53 magnitude,
/// then the two-letter weekday code. Tokens that fail to parse fall
/// back to `(i32::MAX, 7)` so they sort to the tail — they should
/// have been rejected upstream by `is_valid_byday_token_for_freq`.
pub(super) fn canonical_byday_sort_key(token: &str) -> (i32, u8) {
    if token.len() < 2 {
        return (i32::MAX, 7);
    }
    let (prefix, code) = token.split_at(token.len() - 2);
    let weekday = match code {
        "MO" => 0,
        "TU" => 1,
        "WE" => 2,
        "TH" => 3,
        "FR" => 4,
        "SA" => 5,
        "SU" => 6,
        _ => return (i32::MAX, 7),
    };
    let ordinal: i32 = if prefix.is_empty() {
        0
    } else {
        prefix.parse::<i32>().unwrap_or(i32::MAX)
    };
    (ordinal, weekday)
}

/// Parse the three RFC 5545–accepted UNTIL forms into our canonical
/// `YYYY-MM-DD`. `Some` on success; `None` if the shape doesn't match
/// any of the three. Returns the date portion of any DATE-TIME — we
/// don't preserve the time-of-day on storage; the rule is "valid
/// through this day in the calendar's anchor zone", matching how the
/// projection engine has always treated UNTIL.
pub(super) fn parse_until_to_ymd(s: &str) -> Option<String> {
    // Canonical hyphenated form (`YYYY-MM-DD`) — go through the
    // workspace's canonical parser so any future tightening (e.g.
    // rejecting leading whitespace or trailing junk) is shared with
    // every other date-string call site.
    if let Ok(date) = crate::time::parse_iso_date(s) {
        return Some(date.format("%Y-%m-%d").to_string());
    }
    // RFC 5545 DATE form (`YYYYMMDD`). Stays as a direct chrono call
    // because `parse_iso_date` is the *storage* shape and this branch
    // is the explicit RFC-compatibility layer for ingest.
    if let Ok(date) = chrono::NaiveDate::parse_from_str(s, "%Y%m%d") {
        return Some(date.format("%Y-%m-%d").to_string());
    }
    // RFC 5545 DATE-TIME form (`YYYYMMDDTHHMMSSZ`). The 'Z' is
    // required for the UNTIL-DATE-TIME variant per RFC 5545 §3.3.10.
    if let Ok(dt) = chrono::NaiveDateTime::parse_from_str(s, "%Y%m%dT%H%M%SZ") {
        return Some(dt.date().format("%Y-%m-%d").to_string());
    }
    None
}
