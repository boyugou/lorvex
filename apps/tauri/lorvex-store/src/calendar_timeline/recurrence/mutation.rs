use super::parse::{
    days_in_month, parse_freq, parse_positive_count, parse_required_ymd, parse_rule_object,
};
use crate::error::StoreError;
use chrono::Datelike;
use serde_json::Value;

/// For MONTHLY/YEARLY rules without an explicit BYMONTHDAY, inject the
/// day-of-month from the task's due date so that "monthly on the 15th"
/// stays anchored to the 15th across recurrence cycles.
///
/// When the anchor day is the *last* day of its own month (Jan-31,
/// Apr-30, Feb-28/29) the injected value is `BYMONTHDAY=-1`
/// (count-from-end) rather than the literal day, so the friendly
/// month-end series (Jan31->Feb28->Mar31->Apr30) survives short months
/// while staying RFC 5545-faithful and exportable — a positive
/// month-end day would instead *skip* months it lacks at expansion. Any
/// non-month-end day is injected verbatim (and therefore skips months it
/// lacks). The value is written as the one-element array form
/// (`[15]` / `[-1]`) so the stored canonical rule matches the
/// normalizer's array wire shape.
///
/// Returns `Ok(None)` if the rule doesn't need injection (not MONTHLY/YEARLY,
/// BYMONTHDAY already present, or the rule uses BYDAY/BYSETPOS positional
/// filters that would be corrupted by an added month-day constraint).
///
/// emit canonical (sorted-keys) JSON via the
/// domain-level canonicalizer instead of `Value::to_string()`. The
/// latter happens to produce sorted output today only because
/// `serde_json::Map` aliases `BTreeMap` when the workspace keeps
/// `serde_json` default features ON; a future feature unification
/// flipping `preserve_order` would silently make this writer emit
/// insertion-order JSON, diverging from `normalize_task_recurrence`
/// and creating payload-shadow churn (the next outbox enqueue would
/// re-canonicalize and the content hash would flip on every cycle).
pub fn inject_bymonthday(
    recurrence_json: &str,
    due_date_ymd: &str,
) -> Result<Option<String>, StoreError> {
    let mut rule = parse_rule_object(recurrence_json)?;
    let freq = parse_freq(&rule)?;
    if freq != "MONTHLY" && freq != "YEARLY" {
        return Ok(None);
    }
    if !rule.get("BYMONTHDAY").is_none_or(Value::is_null) {
        return Ok(None);
    }
    if !rule.get("BYDAY").is_none_or(Value::is_null)
        || !rule.get("BYSETPOS").is_none_or(Value::is_null)
    {
        return Ok(None);
    }
    let date = parse_required_ymd(due_date_ymd, "due_date")?;
    let is_last_day_of_month = days_in_month(date.year(), date.month()) == Some(date.day());
    let injected: i64 = if is_last_day_of_month {
        -1
    } else {
        i64::from(date.day())
    };
    // BYMONTHDAY is canonically an array; inject the single anchor as a
    // one-element array so the stored rule matches the normalizer's wire shape.
    rule["BYMONTHDAY"] = Value::Array(vec![Value::from(injected)]);
    let canonical = lorvex_domain::canonical_json::canonicalize_json(&rule).map_err(|e| {
        StoreError::Serialization(format!(
            "canonicalize recurrence after BYMONTHDAY inject: {e}"
        ))
    })?;
    Ok(Some(canonical))
}

/// Decrement the COUNT field in a recurrence JSON for a spawned successor.
///
/// Returns:
/// - `Ok(Some(json))` with COUNT decremented when count > 1
/// - `Ok(None)` when count == 1 (last occurrence — caller should clear recurrence)
/// - `Ok(Some(original))` unchanged when no COUNT key is present
///
/// Surface `COUNT <= 0` as an Invariant break instead of silently
/// treating it as "last occurrence". The upstream MCP/Tauri
/// validators reject `COUNT<1` at the boundary, but apply-pipeline
/// peer payloads can land in `tasks.recurrence` without going
/// through those gates (a forked peer shipping `COUNT=0` directly).
/// A `count <= 1` branch that folded `COUNT=0` into "clear the
/// recurrence" would emit no diagnostic — users' recurring series
/// would quietly disappear on the receiving device. Read the COUNT
/// field directly (bypassing `parse_count`'s strict validator,
/// which would conflate this with a generic Validation error) so
/// `COUNT<1` produces a typed `StoreError::Invariant` carrying the
/// offending value.
///
/// Also emits canonical (sorted-keys) JSON via the domain
/// canonicalizer instead of `Value::to_string()` — see
/// `inject_bymonthday` for the rationale (M4 / preserve_order
/// feature unification).
pub fn decrement_recurrence_count(recurrence_json: &str) -> Result<Option<String>, StoreError> {
    let mut rule = parse_rule_object(recurrence_json)?;

    // Defensive read: surface COUNT<1 as Invariant before delegating
    // to parse_count (which would route it through the generic
    // Validation error path, masking the "peer bypassed validation"
    // signal).
    if let Some(value) = rule.get("COUNT") {
        if let Some(raw_count) = value.as_i64() {
            if raw_count < 1 {
                return Err(StoreError::Invariant(format!(
                    "recurrence COUNT={raw_count} violates invariant (expected >= 1) — \
                     a peer payload bypassed validation; refusing to silently clear \
                     the recurrence series"
                )));
            }
        }
    }

    match parse_positive_count(&rule)? {
        Some(1) => Ok(None),
        Some(count) => {
            rule["COUNT"] = Value::from(count - 1);
            let canonical =
                lorvex_domain::canonical_json::canonicalize_json(&rule).map_err(|e| {
                    StoreError::Serialization(format!(
                        "canonicalize recurrence after COUNT decrement: {e}"
                    ))
                })?;
            Ok(Some(canonical))
        }
        None => Ok(Some(recurrence_json.to_string())),
    }
}
