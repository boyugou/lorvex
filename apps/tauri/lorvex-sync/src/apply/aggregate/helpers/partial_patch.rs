//! JSON field extraction for partial-patch envelopes — the
//! "absent vs null vs empty string" tri-state plumbing every
//! aggregate handler needs to distinguish "field absent from
//! envelope" (preserve existing column) from "explicit clear" or
//! "set to value." Includes the Unicode-hygiene scrubber
//! re-exports so every inbound text field flows through the same
//! sanitizer regardless of which entity authored it.

use super::super::ApplyError;
use lorvex_domain::Patch;

pub(in crate::apply::aggregate) fn optional_object_array<'a>(
    val: &'a serde_json::Value,
    key: &str,
    entity: &str,
) -> Result<Option<&'a [serde_json::Value]>, ApplyError> {
    match val.get(key) {
        None | Some(serde_json::Value::Null) => Ok(None),
        Some(serde_json::Value::Array(items)) => Ok(Some(items.as_slice())),
        Some(_) => Err(ApplyError::InvalidPayload(format!(
            "{entity} payload: {key} must be an array when present"
        ))),
    }
}

/// Tri-state optional string for nullable columns where "explicit clear"
/// must be distinguishable from "field absent".
///
/// Returns:
/// * `Patch::Unset` — key is absent from the JSON object (no change intent).
/// * `Patch::Clear` — key is present as JSON `null` *or* an empty string
///   `""`. Older peers serialize "clear" as `""`, newer peers as `null`;
///   both collapse to the same SQL NULL here so the clear fans out.
/// * `Patch::Set(s)` — key is present with a non-empty string value.
///
/// Callers that bind the result into a nullable SQLite column should flatten
/// `Unset`/`Clear` to `None::<&str>` (SQL NULL) and `Set(s)` to `Some(s)` —
/// see [`nullable_str_or_clear`]. The helper exists so the *intent* of
/// "explicit empty = clear" is named in the types and preserved under future
/// partial-update strategies, rather than silently conflated with "absent"
/// by the legacy [`super::optional_str`] coercion (issue #2308).
pub(in crate::apply::aggregate) fn optional_str_preserving_empty<'a>(
    val: &'a serde_json::Value,
    key: &str,
    entity: &str,
) -> Result<Patch<&'a str>, ApplyError> {
    match val.get(key) {
        None => Ok(Patch::Unset),
        Some(serde_json::Value::Null) => Ok(Patch::Clear),
        Some(value) => match value.as_str() {
            Some("") => Ok(Patch::Clear),
            Some(s) => Ok(Patch::Set(s)),
            None => Err(ApplyError::InvalidPayload(format!(
                "{entity} payload: {key} must be a string when present"
            ))),
        },
    }
}

/// Flatten [`optional_str_preserving_empty`] to a simple `Option<&str>` for
/// binding into a nullable SQL column. Both "absent" and "explicit clear"
/// collapse to SQL NULL; "explicit non-empty value" passes through.
#[inline]
pub(in crate::apply::aggregate) const fn nullable_str_or_clear<'a>(
    val: &Patch<&'a str>,
) -> Option<&'a str> {
    val.as_bind_value().copied()
}

/// Split a [`Patch<&str>`] from [`optional_str_preserving_empty`] into the
/// `(value, present)` pair an `INSERT … ON CONFLICT` upsert needs to
/// distinguish "field absent from envelope" (preserve the existing column
/// value) from "field present, possibly with an explicit clear" (write the
/// new value, including SQL NULL).
///
/// straight into `excluded.col`, which meant a peer running an older build
/// that simply didn't know about a recently-added column would silently NULL
/// it out on every receiving device — durably losing whatever value the
/// more-recent peer had set. The fix is to keep the same `:col` bind but
/// pair it with a `:col_present` integer flag so the conflict-resolution SQL
/// can emit `CASE WHEN :col_present THEN excluded.col ELSE tasks.col END`
/// and preserve the local value on absence.
///
/// On a fresh INSERT the `present` flag is unused — the row's value comes
/// straight from `:col`, which is `None` for both absent and explicit-clear,
/// both of which produce a SQL NULL (there is no existing value to preserve
/// on a first-time insert).
#[inline]
pub(in crate::apply::aggregate) const fn split_partial_str_value(
    val: Patch<&str>,
) -> (Option<&str>, i64) {
    match val {
        Patch::Unset => (None, 0),
        Patch::Clear => (None, 1),
        Patch::Set(s) => (Some(s), 1),
    }
}

/// integer-column variant of [`split_partial_str_value`].
/// Returns `(value, present)` so the upsert SET clause can preserve
/// the existing column on field absence rather than collapsing it to
/// NULL.
#[inline]
pub(in crate::apply::aggregate) const fn split_partial_i64_value(
    val: Patch<i64>,
) -> (Option<i64>, i64) {
    match val {
        Patch::Unset => (None, 0),
        Patch::Clear => (None, 1),
        Patch::Set(n) => (Some(n), 1),
    }
}

/// Tri-state version of `optional_i64` mirroring
/// [`optional_str_preserving_empty`]. Distinguishes:
///
/// * `Patch::Unset` — key is absent from the JSON object.
/// * `Patch::Clear` — key is present with JSON `null`.
/// * `Patch::Set(n)` — key is present with an integer value.
///
/// Used together with [`split_partial_i64_value`] to keep "absent"
/// from clobbering a non-NULL local column on partial-update
/// envelopes from older / forward-compat peers.
pub(in crate::apply::aggregate) fn optional_i64_preserving_null(
    val: &serde_json::Value,
    key: &str,
    entity: &str,
) -> Result<Patch<i64>, ApplyError> {
    match val.get(key) {
        None => Ok(Patch::Unset),
        Some(serde_json::Value::Null) => Ok(Patch::Clear),
        Some(value) => value
            .as_i64()
            .ok_or_else(|| {
                ApplyError::InvalidPayload(format!(
                    "{entity} payload: {key} must be an integer when present"
                ))
            })
            .map(Patch::Set),
    }
}

/// Apply the Unicode hygiene scrubber to a value so inbound sync payloads
/// cannot smuggle bidi overrides, zero-width chars, or line separators into
/// local text columns. Called at every free-text field on inbound apply so
/// the invariant holds even when the envelope came from a peer running an
/// older build without the write-boundary scrub.
#[inline]
pub(in crate::apply::aggregate) fn scrub(s: &str) -> String {
    lorvex_domain::sanitize_user_text(s)
}

#[inline]
pub(in crate::apply::aggregate) fn scrub_opt(s: Option<&str>) -> Option<String> {
    s.map(scrub)
}
