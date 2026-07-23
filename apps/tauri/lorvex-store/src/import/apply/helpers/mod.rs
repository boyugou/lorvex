//! Shared helpers for the apply pipeline: JSONL line parsing and the
//! payload-shape validators reused by every per-entity upsert.

use serde::Deserialize;

use lorvex_domain::naming::EntityKind;
use lorvex_domain::{hlc::Hlc, normalize_sync_timestamp};

use crate::import::ImportError;

/// Raw deserialization shape for a versioned JSONL line. Internal —
/// callers receive [`VersionedJsonlLine`] which carries the typed
/// [`EntityKind`] in place of `entity_type: String`.
#[derive(Deserialize)]
struct RawVersionedJsonlLine {
    entity_type: String,
    #[serde(default)]
    entity_id: Option<String>,
    version: String,
    payload: serde_json::Value,
}

/// A parsed versioned JSONL line from entities/edges/children.
///
/// The trust boundary parses `entity_type` into the typed
/// [`EntityKind`] enum exactly once, at line construction. Downstream
/// dispatch (`dispatch_entity` / `dispatch_edge` / `dispatch_child`
/// and the per-domain upsert helpers) match on the enum so adding a
/// new entity kind cascades through the type system. Unknown entity
/// types are rejected here: snapshot restore must never report success
/// while silently dropping archive rows.
#[derive(Debug)]
pub(in crate::import) struct VersionedJsonlLine {
    /// Parsed [`EntityKind`].
    pub(in crate::import) entity_type: EntityKind,
    pub(in crate::import) version: String,
    pub(in crate::import) payload: serde_json::Value,
}

/// A parsed JSONL line from non-versioned streams such as audit entries.
#[derive(Deserialize)]
pub(in crate::import::apply) struct JsonlLine {
    pub(in crate::import::apply) entity_type: String,
    pub(in crate::import::apply) payload: serde_json::Value,
}

pub(in crate::import) fn parse_versioned_jsonl_line(
    line: &str,
    stream_name: &str,
) -> Result<VersionedJsonlLine, ImportError> {
    let raw: RawVersionedJsonlLine = serde_json::from_str(line)?;
    if raw.version.trim().is_empty() {
        return Err(invalid_payload(format!(
            "{stream_name} entry for `{}` must include a non-empty version",
            raw.entity_type
        )));
    }
    Hlc::parse(&raw.version).map_err(|error| {
        invalid_payload(format!(
            "{stream_name} entry for `{}` must include a valid HLC version: {error}",
            raw.entity_type
        ))
    })?;
    let entity_type = EntityKind::parse(&raw.entity_type).ok_or_else(|| {
        invalid_payload(format!(
            "{stream_name} entry uses unknown entity_type `{}`; upgrade Lorvex before importing this archive",
            raw.entity_type
        ))
    })?;
    crate::jsonl_identity::validate_versioned_jsonl_identity(
        stream_name,
        entity_type,
        raw.entity_id.as_deref(),
        &raw.payload,
    )
    .map_err(invalid_payload)?;
    Ok(VersionedJsonlLine {
        entity_type,
        version: raw.version,
        payload: raw.payload,
    })
}

pub(in crate::import) fn invalid_payload(message: impl Into<String>) -> ImportError {
    ImportError::InvalidPayload(message.into())
}

pub(in crate::import::apply) fn incoming_hlc_replaces_existing(
    existing: &str,
    incoming: &str,
    locator: &str,
) -> Result<bool, ImportError> {
    let incoming_hlc = Hlc::parse(incoming).map_err(|error| {
        invalid_payload(format!(
            "incoming {locator} must use a valid HLC version: {error}"
        ))
    })?;
    let Ok(existing_hlc) = Hlc::parse(existing) else {
        return Ok(true);
    };
    Ok(incoming_hlc > existing_hlc)
}

pub(in crate::import) fn required_string_field(
    payload: &serde_json::Value,
    key: &str,
    context: &str,
) -> Result<String, ImportError> {
    payload
        .get(key)
        .and_then(|value| value.as_str())
        .map(ToString::to_string)
        .ok_or_else(|| invalid_payload(format!("{context}.{key} must be a string")))
}

pub(in crate::import) fn normalize_import_sync_timestamp(
    value: String,
    key: &str,
    context: &str,
) -> Result<String, ImportError> {
    normalize_sync_timestamp(&value).ok_or_else(|| {
        invalid_payload(format!(
            "{context}.{key} must be a valid UTC sync timestamp"
        ))
    })
}

pub(in crate::import) fn required_sync_timestamp_field(
    payload: &serde_json::Value,
    key: &str,
    context: &str,
) -> Result<String, ImportError> {
    normalize_import_sync_timestamp(required_string_field(payload, key, context)?, key, context)
}

pub(in crate::import) fn optional_sync_timestamp_field(
    payload: &serde_json::Value,
    key: &str,
    context: &str,
) -> Result<Option<String>, ImportError> {
    optional_string_field(payload, key, context)?
        .map(|value| normalize_import_sync_timestamp(value, key, context))
        .transpose()
}

/// Enforce a maximum byte length on a JSONL string field at the import
/// boundary. Mirrors the cap helpers used throughout `lorvex-domain`
/// for outbound writes, but lives here because the import boundary
/// also accepts payloads from peer devices and from manual archive
/// edits — the cap defends both against an adversarial archive (a
/// pasted-in 16 MB `provider_event_key` to inflate the row size) and
/// against an older client that wrote a value the schema later
/// constrained.
///
/// Returns the original string unchanged when within the cap; returns
/// an `InvalidPayload` error when over. We refuse instead of
/// truncating because string-keyed columns (`task_id`, provider keys)
/// are part of natural identity — a silently-truncated key would
/// land in a different row than the source intended, breaking sync
/// idempotency.
pub(in crate::import) fn enforce_max_field_length(
    value: String,
    max_bytes: usize,
    key: &str,
    context: &str,
) -> Result<String, ImportError> {
    if value.len() > max_bytes {
        return Err(invalid_payload(format!(
            "{context}.{key} exceeds maximum length ({len} bytes > {max_bytes} bytes)",
            len = value.len()
        )));
    }
    Ok(value)
}

pub(in crate::import) fn required_string_array_field(
    payload: &serde_json::Value,
    key: &str,
    context: &str,
) -> Result<Vec<String>, ImportError> {
    let values = payload
        .get(key)
        .and_then(|value| value.as_array())
        .ok_or_else(|| invalid_payload(format!("{context}.{key} must be an array of strings")))?;
    values
        .iter()
        .enumerate()
        .map(|(index, value)| {
            value.as_str().map(ToString::to_string).ok_or_else(|| {
                invalid_payload(format!("{context}.{key}[{index}] must be a string"))
            })
        })
        .collect()
}

pub(in crate::import) fn required_object_array_field<'a>(
    payload: &'a serde_json::Value,
    key: &str,
    context: &str,
) -> Result<&'a [serde_json::Value], ImportError> {
    payload
        .get(key)
        .and_then(|value| value.as_array())
        .map(Vec::as_slice)
        .ok_or_else(|| invalid_payload(format!("{context}.{key} must be an array")))
}

pub(in crate::import::apply) fn required_i64_field(
    payload: &serde_json::Value,
    key: &str,
    context: &str,
) -> Result<i64, ImportError> {
    payload
        .get(key)
        .and_then(serde_json::Value::as_i64)
        .ok_or_else(|| invalid_payload(format!("{context}.{key} must be an integer")))
}

/// Accept JSON booleans in import payloads and store them in SQLite's
/// integer-bool columns.
pub(in crate::import) fn required_bool_as_i64_field(
    payload: &serde_json::Value,
    key: &str,
    context: &str,
) -> Result<i64, ImportError> {
    match payload.get(key) {
        Some(serde_json::Value::Bool(b)) => Ok(i64::from(*b)),
        _ => Err(invalid_payload(format!(
            "{context}.{key} must be a boolean"
        ))),
    }
}

pub(in crate::import) fn optional_string_field(
    payload: &serde_json::Value,
    key: &str,
    context: &str,
) -> Result<Option<String>, ImportError> {
    match payload.get(key) {
        None | Some(serde_json::Value::Null) => Ok(None),
        Some(value) => value.as_str().map(|s| Some(s.to_string())).ok_or_else(|| {
            invalid_payload(format!("{context}.{key} must be a string when present"))
        }),
    }
}

pub(in crate::import::apply) fn optional_i64_field(
    payload: &serde_json::Value,
    key: &str,
    context: &str,
) -> Result<Option<i64>, ImportError> {
    match payload.get(key) {
        None | Some(serde_json::Value::Null) => Ok(None),
        Some(value) => value.as_i64().map(Some).ok_or_else(|| {
            invalid_payload(format!("{context}.{key} must be an integer when present"))
        }),
    }
}

#[cfg(test)]
mod tests;
