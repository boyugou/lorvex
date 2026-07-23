//! Calendar-event recurrence normalizer.
//!
//! Calendar events share the bulk of the recurrence contract with
//! tasks; this module only carries the calendar-specific rules
//! layered on top of [`super::task::normalize_task_recurrence`]
//! (friendly-shorthand wrap, tighter `COUNT` cap, stricter BYDAY
//! policy on `MONTHLY`/`YEARLY`). Everything else delegates back to
//! the canonical task normalizer.

use super::{is_valid_recurrence_freq, normalize_task_recurrence, MAX_CALENDAR_RECURRENCE_COUNT};
use crate::validation::error::ValidationError;

/// domain-level calendar recurrence normalizer.
///
/// Calendar events share most of the recurrence contract with tasks
/// but layer two extra rules on top:
///
/// 1. Plain `"WEEKLY"` (etc.) is accepted as friendly shorthand and
///    wrapped to `{"FREQ":"WEEKLY","INTERVAL":1}` before delegation.
/// 2. `COUNT` is capped at [`MAX_CALENDAR_RECURRENCE_COUNT`] (365),
///    tighter than the task-side validator (no cap).
/// 3. `MONTHLY`/`YEARLY` recurrence with bare `BYDAY` weekday codes
///    (e.g. `"MO"`) is rejected unless `BYSETPOS` is also supplied.
///    Users almost always mean "first Monday" but forget the ordinal
///    prefix; silently expanding to "every Monday in the month"
///    produces surprising calendars.
///
/// Returns `Ok(None)` for empty/null input, `Ok(Some(canonical_json))`
/// on valid input, `Err(ValidationError)` on contract violation.
///
/// Living in `lorvex-domain` lets every surface (MCP, Tauri, the
/// `lorvex-sync/src/apply/aggregate/calendar_event/` apply subtree)
/// share one gate with one `ValidationError` shape. Without that,
/// the rule typically lives in `mcp-server` while the Tauri and
/// apply paths each ship their own variant, and the apply trust
/// boundary writes the peer's recurrence verbatim — a peer using
/// the task surface (`set_recurrence`) or a forked client could
/// ship a calendar event whose recurrence violated the calendar
/// contract, and the receiving device's expansion code would then
/// produce output the local boundary would refuse.
pub fn normalize_calendar_recurrence(raw: Option<&str>) -> Result<Option<String>, ValidationError> {
    let Some(raw) = raw else {
        return Ok(None);
    };
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }

    // Friendly-shorthand wrap before delegating: bare "WEEKLY" etc.
    let canonical_input = if is_valid_recurrence_freq(trimmed) {
        serde_json::json!({ "FREQ": trimmed, "INTERVAL": 1 }).to_string()
    } else {
        trimmed.to_string()
    };

    let normalized =
        normalize_task_recurrence(&canonical_input)?.ok_or(ValidationError::Empty("recurrence"))?;

    // Calendar enforces a tighter COUNT cap than the task validator,
    // and a stricter BYDAY policy on MONTHLY/YEARLY.
    //
    // Re-parse the canonical output to inspect its fields. The
    // canonical form is well-formed JSON by construction, so any
    // parse failure here is an internal invariant break — surface
    // it through `ValidationError::Message` rather than swallowing.
    let parsed: serde_json::Value = serde_json::from_str(&normalized).map_err(|e| {
        ValidationError::Message(format!(
            "canonical recurrence not parseable post-normalization: {e}"
        ))
    })?;

    if let Some(count) = parsed.get("COUNT").and_then(serde_json::Value::as_i64) {
        if count > MAX_CALENDAR_RECURRENCE_COUNT {
            return Err(ValidationError::OutOfRange {
                field: "recurrence.COUNT",
                min: 1,
                max: MAX_CALENDAR_RECURRENCE_COUNT,
                actual: count,
            });
        }
    }

    if let Some(freq) = parsed.get("FREQ").and_then(serde_json::Value::as_str) {
        if matches!(freq, "MONTHLY" | "YEARLY") {
            if let Some(byday) = parsed.get("BYDAY").and_then(serde_json::Value::as_array) {
                let has_bysetpos = parsed.get("BYSETPOS").is_some();
                if !has_bysetpos {
                    for code in byday {
                        let s = code.as_str().unwrap_or("");
                        // Bare weekday codes (MO/TU/.../SU) are
                        // exactly two characters. Anything longer
                        // carries an ordinal prefix (e.g. `1MO`,
                        // `-1FR`) and is accepted.
                        if s.len() == 2 {
                            return Err(ValidationError::Message(format!(
                                "recurrence.BYDAY {s:?} is only valid for WEEKLY; \
                                 for FREQ={freq} prefix the day with an ordinal \
                                 (e.g. \"1MO\" for first Monday, \"-1FR\" for last Friday) \
                                 or pair BYDAY with BYSETPOS"
                            )));
                        }
                    }
                }
            }
        }
    }

    Ok(Some(normalized))
}
