//! Shared JSON-payload extraction helpers for every apply submodule.
//!
//! `optional_i64` / `optional_bool_as_i64` set was redefined in six
//! places across `apply::*` (`aggregate::helpers`, `day_scoped::mod`,
//! `changelog::mod`, `blob::mod`, `child::helpers`, `edge::helpers`).
//! A drift in the "absent vs null vs empty" semantics in one copy was
//! a known footgun and a future helper added to one site would not
//! propagate.
//!
//! Every helper here returns `Result<_, ApplyError>` so callers funnel
//! through the canonical `?` propagation and the typed
//! `ApplyError::InvalidPayload` variant. Empty-string-as-absent
//! semantics match every consumer that uses these helpers; the
//! tri-state `optional_str_preserving_empty` (and its `_i64` sibling)
//! lives in `aggregate::helpers` because the partial-update upsert
//! shape that needs it is currently unique to the aggregate path.
//!
//! Aggregate-specific helpers (`split_partial_*`, `nullable_str_or_clear`,
//! `optional_object_array`, `tombstone_*`) stay in
//! `aggregate::helpers` because they are not consumed elsewhere.

use super::ApplyError;

/// Look up `key` in the JSON object and return the inner string slice
/// when present and string-shaped. Returns `None` for missing key,
/// JSON null, or non-string values; the caller decides whether
/// to surface a typed error or a fallback.
pub(crate) fn str_field<'a>(val: &'a serde_json::Value, key: &str) -> Option<&'a str> {
    val.get(key).and_then(|v| v.as_str())
}

/// Look up `key` in the JSON object and return the inner i64 when
/// present and integer-shaped. Returns `None` for missing key, JSON
/// null, or non-integer values.
pub(crate) fn i64_field(val: &serde_json::Value, key: &str) -> Option<i64> {
    val.get(key).and_then(serde_json::Value::as_i64)
}

pub(crate) fn required_str<'a>(
    val: &'a serde_json::Value,
    key: &str,
    entity: &str,
) -> Result<&'a str, ApplyError> {
    str_field(val, key).ok_or_else(|| {
        ApplyError::InvalidPayload(format!("{entity} payload: {key} must be a string"))
    })
}

pub(crate) fn required_i64(
    val: &serde_json::Value,
    key: &str,
    entity: &str,
) -> Result<i64, ApplyError> {
    i64_field(val, key).ok_or_else(|| {
        ApplyError::InvalidPayload(format!("{entity} payload: {key} must be an integer"))
    })
}

/// Legacy helper: accepts absent, null, AND empty-string all as `None`.
///
/// Used everywhere a column treats `""` as "unset" on both write and
/// read paths — the empty string has no distinct meaning. For nullable
/// string columns where an explicit empty write must round-trip as a
/// user-intended clear (issue #2308), prefer
/// `aggregate::helpers::optional_str_preserving_empty` instead.
pub(crate) fn optional_str<'a>(
    val: &'a serde_json::Value,
    key: &str,
    entity: &str,
) -> Result<Option<&'a str>, ApplyError> {
    match val.get(key) {
        None | Some(serde_json::Value::Null) => Ok(None),
        Some(value) => match value.as_str() {
            // Treat empty strings as absent so downstream NULL semantics and
            // `!value.is_empty()` guards agree. Older devices serialize
            // "unset" as "" rather than omitting the field.
            Some("") => Ok(None),
            Some(s) => Ok(Some(s)),
            None => Err(ApplyError::InvalidPayload(format!(
                "{entity} payload: {key} must be a string when present"
            ))),
        },
    }
}

pub(crate) fn required_nullable_str<'a>(
    val: &'a serde_json::Value,
    key: &str,
    entity: &str,
) -> Result<Option<&'a str>, ApplyError> {
    match val.get(key) {
        None => Err(ApplyError::InvalidPayload(format!(
            "{entity} payload: {key} is required and must be a string or null"
        ))),
        Some(serde_json::Value::Null) => Ok(None),
        Some(value) => value.as_str().map(Some).ok_or_else(|| {
            ApplyError::InvalidPayload(format!("{entity} payload: {key} must be a string or null"))
        }),
    }
}

pub(crate) fn optional_i64(
    val: &serde_json::Value,
    key: &str,
    entity: &str,
) -> Result<Option<i64>, ApplyError> {
    match val.get(key) {
        None | Some(serde_json::Value::Null) => Ok(None),
        Some(value) => value
            .as_i64()
            .ok_or_else(|| {
                ApplyError::InvalidPayload(format!(
                    "{entity} payload: {key} must be an integer when present"
                ))
            })
            .map(Some),
    }
}

/// Accept JSON booleans at the sync boundary and store them in
/// SQLite's integer-bool columns. Missing/null optional fields keep
/// the SQL default.
pub(crate) fn optional_bool_as_i64(
    val: &serde_json::Value,
    key: &str,
    entity: &str,
) -> Result<Option<i64>, ApplyError> {
    match val.get(key) {
        None | Some(serde_json::Value::Null) => Ok(None),
        Some(serde_json::Value::Bool(b)) => Ok(Some(i64::from(*b))),
        _ => Err(ApplyError::InvalidPayload(format!(
            "{entity} payload: {key} must be a boolean when present"
        ))),
    }
}

pub(crate) fn required_bool_as_i64(
    val: &serde_json::Value,
    key: &str,
    entity: &str,
) -> Result<i64, ApplyError> {
    match val.get(key) {
        Some(serde_json::Value::Bool(b)) => Ok(i64::from(*b)),
        _ => Err(ApplyError::InvalidPayload(format!(
            "{entity} payload: {key} must be a boolean"
        ))),
    }
}
