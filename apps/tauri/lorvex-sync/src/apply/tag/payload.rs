use super::*;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

pub(super) fn str_field<'a>(val: &'a serde_json::Value, key: &str) -> Option<&'a str> {
    val.get(key).and_then(|v| v.as_str())
}

/// Tri-state optional string for nullable tag columns where "explicit
/// clear" must be distinguishable from "field absent". Mirrors the
/// identical helper in `aggregate.rs`.
///
/// * `Patch::Unset` — key absent from the JSON payload.
/// * `Patch::Clear` — key present as JSON `null` or empty string
///   (older peers serialize "clear" as `""`, newer peers as `null`).
/// * `Patch::Set(s)` — key present with a non-empty string value.
pub(super) fn optional_str_preserving_empty<'a>(
    val: &'a serde_json::Value,
    key: &str,
) -> Result<lorvex_domain::Patch<&'a str>, ApplyError> {
    use lorvex_domain::Patch;
    match val.get(key) {
        None => Ok(Patch::Unset),
        Some(serde_json::Value::Null) => Ok(Patch::Clear),
        Some(value) => match value.as_str() {
            Some("") => Ok(Patch::Clear),
            Some(s) => Ok(Patch::Set(s)),
            None => Err(ApplyError::InvalidPayload(format!(
                "tag payload: {key} must be a string when present"
            ))),
        },
    }
}

/// Flatten the tri-state result to a nullable SQL binding: both "absent"
/// and "explicit clear" collapse to `None` (SQL NULL).
#[inline]
pub(super) const fn nullable_str_or_clear<'a>(
    val: &lorvex_domain::Patch<&'a str>,
) -> Option<&'a str> {
    val.as_bind_value().copied()
}

pub(super) fn required_str<'a>(
    val: &'a serde_json::Value,
    key: &str,
) -> Result<&'a str, ApplyError> {
    str_field(val, key)
        .ok_or_else(|| ApplyError::InvalidPayload(format!("tag payload: {key} must be a string")))
}
