//! Task recurrence-rule normalizer.
//!
//! [`normalize_task_recurrence`] is the canonical normalizer for task
//! recurrence rules: every write surface (task create / update /
//! batch_update / set_recurrence, the Tauri update path, and the
//! calendar normalizer's delegation) routes through this function.
//! Output has stable key order, defaults applied, and unknown keys
//! rejected.
//!
//! The shared helpers and the `RecurrenceWarning` diagnostic enum
//! live in the parent module so the calendar normalizer can reuse
//! them without going through a re-export.
//!
//! Folder layout:
//!
//! - `mod.rs` (this file) — the public API + the orchestrator that
//!   walks each RRULE field in order, assembles the canonical JSON,
//!   and emits any non-fatal warnings.
//! - `fields.rs` — per-field parsers, one function per RRULE key.
//! - `helpers.rs` — `parse_int_array`, `canonical_byday_sort_key`,
//!   `parse_until_to_ymd`.
//! - `warnings.rs` — `emit_warnings` (BYMONTHDAY skip + leap-year
//!   birthday detection).

mod fields;
mod helpers;
mod warnings;

use crate::validation::error::ValidationError;
use crate::validation::recurrence::RecurrenceWarning;

/// Known keys in the task recurrence JSON schema.
///
/// extended with the RFC 5545 §3.3.10 keys that real-world calendar
/// feeds emit and that the prior allowlist silently rejected:
///
/// - `BYSETPOS` — pick the Nth occurrence inside a frequency-defined
///   set (e.g. "first weekday of the month" combined with `BYDAY`).
/// - `WKST` — week-start day used by `WEEKLY` rules with `INTERVAL > 1`
///   to determine which week boundaries the rule advances over.
///
/// extended with `BYMONTH` (RFC 5545 §3.3.10's `1..=12` month-of-year
/// filter, the most common modifier on `FREQ=YEARLY` rules — leap-year
/// birthdays land here as `FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29`).
/// of legitimate `BYMONTH=*` rules were silently rejected at the
/// validator boundary.
const KNOWN_RECURRENCE_KEYS: &[&str] = &[
    "FREQ",
    "INTERVAL",
    "BYDAY",
    "BYMONTH",
    "BYMONTHDAY",
    "BYSETPOS",
    "WKST",
    "UNTIL",
    "COUNT",
];

/// Validate and normalize a task recurrence rule string.
///
/// Returns `Ok(None)` for empty/null input (no recurrence).
/// Returns `Ok(Some(canonical_json))` for valid input — the canonical
/// JSON has stable key order, defaults applied, and unknown keys
/// rejected.
///
/// callers that want to surface non-fatal observations
/// (e.g. `BYMONTHDAY=31` skipping short months) should use
/// [`normalize_task_recurrence_with_warnings`] instead.
pub fn normalize_task_recurrence(recurrence: &str) -> Result<Option<String>, ValidationError> {
    normalize_task_recurrence_with_warnings(recurrence).map(|outcome| outcome.map(|(c, _)| c))
}

/// Variant of [`normalize_task_recurrence`] that also returns any
/// non-fatal [`RecurrenceWarning`]s observed while validating the
/// rule.
pub fn normalize_task_recurrence_with_warnings(
    recurrence: &str,
) -> Result<Option<(String, Vec<RecurrenceWarning>)>, ValidationError> {
    if recurrence.trim().is_empty() {
        return Ok(None);
    }
    let parsed: serde_json::Value =
        serde_json::from_str(recurrence).map_err(|_| ValidationError::InvalidFormat {
            field: "recurrence",
            expected: "JSON object with FREQ field",
            actual: recurrence.to_string(),
        })?;
    let obj = parsed
        .as_object()
        .ok_or_else(|| ValidationError::InvalidFormat {
            field: "recurrence",
            expected: "JSON object",
            actual: recurrence.to_string(),
        })?;

    // Reject unknown keys.
    for key in obj.keys() {
        if !KNOWN_RECURRENCE_KEYS.contains(&key.as_str()) {
            return Err(ValidationError::InvalidFormat {
                field: "recurrence",
                expected:
                    "only FREQ/INTERVAL/BYDAY/BYMONTH/BYMONTHDAY/BYSETPOS/WKST/UNTIL/COUNT keys allowed",
                actual: format!("unknown key '{key}'"),
            });
        }
    }

    let freq = fields::parse_freq(&parsed, recurrence)?;
    let interval = fields::parse_interval(&parsed)?;
    let byday = fields::parse_byday(&parsed, freq)?;
    let bysetpos = fields::parse_bysetpos(&parsed, freq)?;
    let bymonth = fields::parse_bymonth(&parsed, freq)?;
    let wkst = fields::parse_wkst(&parsed)?;
    let bymonthday = fields::parse_bymonthday(&parsed, freq)?;
    let until = fields::parse_until(&parsed)?;
    let count = fields::parse_count(&parsed)?;

    // COUNT and UNTIL are mutually exclusive.
    if count.is_some() && until.is_some() {
        return Err(ValidationError::InvalidFormat {
            field: "recurrence",
            expected: "COUNT and UNTIL are mutually exclusive",
            actual: "both COUNT and UNTIL present".to_string(),
        });
    }

    // Build canonical JSON with stable key order.
    let mut canonical = serde_json::Map::new();
    canonical.insert(
        "FREQ".to_string(),
        serde_json::Value::String(freq.to_string()),
    );
    canonical.insert("INTERVAL".to_string(), serde_json::json!(interval));
    if let Some(ref days) = byday {
        canonical.insert("BYDAY".to_string(), serde_json::json!(days));
    }
    // BYMONTH ahead of BYMONTHDAY mirrors RFC 5545's "broader filter
    // first" expansion order so a YEARLY birthday rule reads
    // `FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29` rather than having
    // BYMONTHDAY shadow the month filter.
    if let Some(ref months) = bymonth {
        canonical.insert("BYMONTH".to_string(), serde_json::json!(months));
    }
    if let Some(ref days) = bymonthday {
        canonical.insert("BYMONTHDAY".to_string(), serde_json::json!(days));
    }
    if let Some(ref positions) = bysetpos {
        canonical.insert("BYSETPOS".to_string(), serde_json::json!(positions));
    }
    if let Some(ref date) = until {
        canonical.insert("UNTIL".to_string(), serde_json::Value::String(date.clone()));
    }
    if let Some(c) = count {
        canonical.insert("COUNT".to_string(), serde_json::json!(c));
    }
    if let Some(ref start) = wkst {
        canonical.insert("WKST".to_string(), serde_json::Value::String(start.clone()));
    }

    let warnings = warnings::emit_warnings(freq, bymonthday.as_deref(), bymonth.as_deref());

    Ok(Some((
        serde_json::Value::Object(canonical).to_string(),
        warnings,
    )))
}
