//! Task and calendar recurrence-rule normalization.
//!
//! `normalize_task_recurrence` is the SINGLE canonical normalizer for
//! task recurrence rules — every write surface (create, update,
//! batch_update, set_recurrence, Tauri update) calls it and stores the
//! returned canonical string. Output has stable key order, defaults
//! applied, and unknown keys rejected.
//!
//! Layout:
//!
//! - `mod.rs` (this file) — shared allowlists, the `RecurrenceWarning`
//!   diagnostic enum, and the small membership-test helpers
//!   (`is_valid_recurrence_freq`, `is_valid_byday_code`,
//!   `is_valid_byday_token_for_freq`) consumed by the calendar
//!   shorthand wrap and by RFC 5545–adjacent plumbing.
//! - `task/` — `normalize_task_recurrence` /
//!   `normalize_task_recurrence_with_warnings` and their per-field
//!   parsers + helpers + warning emitter (see `task/mod.rs` for the
//!   sub-module layout).
//! - `calendar.rs` — `normalize_calendar_recurrence`, which delegates
//!   back to the task normalizer with two extra calendar-only rules
//!   (a tighter `COUNT` cap and a stricter `BYDAY` policy).

mod calendar;
mod task;

pub use calendar::normalize_calendar_recurrence;
pub use task::{normalize_task_recurrence, normalize_task_recurrence_with_warnings};

/// Valid FREQ values for task recurrence rules.
///
/// `pub(super)` so the `task` submodule can membership-test against
/// the same allowlist that backs [`is_valid_recurrence_freq`] —
/// keeping the four-element list in exactly one place.
pub(super) const VALID_RECURRENCE_FREQS: &[&str] = &["DAILY", "WEEKLY", "MONTHLY", "YEARLY"];

/// canonical FREQ allowlist exposed for surfaces that
/// need membership testing without re-running the full normalizer
/// (e.g. the calendar friendly-shorthand wrap that converts a bare
/// `"WEEKLY"` into `{"FREQ":"WEEKLY","INTERVAL":1}` before
/// delegating). Hoisting prevents the same four-element allowlist
/// from drifting across the Tauri / MCP / CLI calendar entry points.
pub fn is_valid_recurrence_freq(value: &str) -> bool {
    VALID_RECURRENCE_FREQS.contains(&value)
}

const VALID_BYDAY_CODES: &[&str] = &["MO", "TU", "WE", "TH", "FR", "SA", "SU"];

/// A non-fatal observation produced while normalizing a recurrence
/// rule. Returned alongside `Ok(canonical)` so the
/// apply / export pipeline can surface "this rule is technically
/// valid but its expansion will silently skip months / produce no
/// occurrences" to the user instead of letting the AI assistant or a
/// peer device wonder why a `MONTHLY;BYMONTHDAY=31` series only
/// appears seven times a year.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RecurrenceWarning {
    /// `FREQ=MONTHLY;BYMONTHDAY=29|30|31` skips the months whose last
    /// day is before the requested day-of-month. RFC 5545 §3.3.10
    /// leaves the behavior implementation-defined; chrono's expansion
    /// (and most external calendars) drop those months entirely.
    /// Carries the canonical day so the warning carries enough
    /// information to be rendered or compared.
    BymonthdaySkipsMonths { day: i64 },
    /// `FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29` is a
    /// well-formed rule that legitimately fires only on Feb 29 of
    /// leap years (skipping 2100/2200/2300 because of the Gregorian
    /// century rule). Emitted in place of `BymonthdaySkipsMonths`
    /// for that exact shape so the diagnostic surface can spell out
    /// the leap-year cadence instead of leaning on the generic
    /// "skips months" copy.
    LeapYearBirthday,
}

/// Shared cap on `COUNT` for calendar-event recurrence rules. Every
/// calendar surface (Tauri create/update validation, CLI calendar
/// normalizer, MCP server contract) routes through this single
/// constant so the bound stays single-sourced. Tasks (the canonical
/// recurrence consumer) intentionally do NOT cap COUNT because
/// monthly/yearly task series legitimately exceed 365 instances; the
/// cap exists for calendar events whose UI grid renders one row per
/// occurrence.
pub const MAX_CALENDAR_RECURRENCE_COUNT: i64 = 365;

/// Canonical BYDAY weekday-code allowlist. Every
/// caller (task `set_recurrence`, calendar recurrence normalizer,
/// future RFC-5545 plumbing) routes here so the seven-code match
/// lives in exactly one place.
pub fn is_valid_byday_code(code: &str) -> bool {
    VALID_BYDAY_CODES.contains(&code)
}

/// Validate an RFC 5545 §3.3.10 BYDAY token in the context of a given
/// `FREQ`. Tokens may carry an optional ordinal prefix
/// `[+-]?[1-9][0-9]?` followed by a 2-letter weekday code
/// (e.g. `1MO` = first Monday of the period, `-1FR` = last Friday).
///
/// The absolute-value range depends on the caller's `FREQ`:
///
/// - `MONTHLY` → `1..=5` (a calendar month contains at most five
///   same-weekdays; a `10MO` rule would silently drop on expansion
///   because no calendar month has a 10th Monday).
/// - `YEARLY` → `1..=53` (a calendar year contains at most 53
///   same-weekdays).
/// - `WEEKLY` → ordinal prefixes are rejected outright; RFC 5545 has
///   no "first MO inside a week" concept. Bare codes only.
/// - any other FREQ → bare codes only (callers gate on FREQ before
///   reaching here, this is defense in depth).
///
/// Prefixed forms like `1MO` or `-1FR` are accepted for the monthly
/// and yearly cases so imports of "first/last weekday of month" rules
/// validate.
pub fn is_valid_byday_token_for_freq(token: &str, freq: &str) -> bool {
    let bytes = token.as_bytes();
    if bytes.len() < 2 {
        return false;
    }
    // Find the split between ordinal and weekday code: weekday code
    // is always the last two ASCII chars.
    let split = token.len() - 2;
    let prefix = &token[..split];
    let code = &token[split..];
    if !is_valid_byday_code(code) {
        return false;
    }
    if prefix.is_empty() {
        return true;
    }
    // RFC 5545: WEEKLY rules cannot carry an ordinal-prefixed BYDAY
    // (no "first MO inside a week" notion). The token-level helper
    // owns this rule so every caller — including the calendar
    // normalize path — routes through one check.
    if freq == "WEEKLY" {
        return false;
    }
    // Optional sign followed by an ordinal in `1..=max_for_freq`.
    // Reject leading zeros and multi-sign garbage.
    let (sign_stripped, _negative) = match prefix.as_bytes()[0] {
        b'+' => (&prefix[1..], false),
        b'-' => (&prefix[1..], true),
        _ => (prefix, false),
    };
    if sign_stripped.is_empty() {
        return false;
    }
    // Reject leading zero (`01MO`) — RFC requires no leading zero.
    if sign_stripped.len() > 1 && sign_stripped.as_bytes()[0] == b'0' {
        return false;
    }
    let Ok(ord) = sign_stripped.parse::<i32>() else {
        return false;
    };
    let max_ord: i32 = match freq {
        "MONTHLY" => 5,
        "YEARLY" => 53,
        // Any FREQ that is not MONTHLY/YEARLY (DAILY, HOURLY, ...) has
        // no defined ordinal-BYDAY semantics in RFC 5545. The caller
        // is expected to gate before reaching here; this branch is
        // defense in depth.
        _ => return false,
    };
    (1..=max_ord).contains(&ord)
}
