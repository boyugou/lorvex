//! Router-side helpers for extracting affected entity ids from
//! handler responses.
//!
//! Each MCP write tool's router pairs a handler with an "affected
//! ids" extractor that pulls the entity ids the call mutated out of
//! the JSON response so the post-handler change-tracking pipeline
//! can broadcast them. The extractor shapes are domain-agnostic —
//! some tools return `{"id": …}`, some return `{"tasks": [{"id":
//! …}]}`, some return composite-key edges as `{lhs_id, rhs_id}`.
//! Centralizing the extractors here lets every router (task,
//! calendar, list, workflow) reach for them without depending on
//! a sibling router's module.

/// Extract a list of `id` strings from a JSON value of shape
/// `[{ "id": "..." }, ...]`. Returns an empty vec when the value
/// is missing, non-array, or carries no `id` strings.
///
/// Used for tool responses that wrap an array of entities in a
/// known-key envelope (`tasks`, `cancelled`, `calendar_events`,
/// etc.); callers extract the array via `value.get("tasks")` and
/// pipe through this helper.
pub(crate) fn collect_id_strings(value: Option<&serde_json::Value>) -> Vec<String> {
    let Some(arr) = value.and_then(serde_json::Value::as_array) else {
        return Vec::new();
    };
    arr.iter()
        .filter_map(|item| {
            item.get("id")
                .and_then(serde_json::Value::as_str)
                .map(str::to_string)
        })
        .collect()
}

/// Extract a single top-level `id` string field from a JSON object.
/// Returns an empty vec when the field is missing or non-string.
/// Canonical single-id extractor that the 6+ router sites needing
/// this shape share instead of each carrying their own closure.
pub(crate) fn extract_top_level_id(value: &serde_json::Value) -> Vec<String> {
    value
        .get("id")
        .and_then(serde_json::Value::as_str)
        .map(|s| vec![s.to_string()])
        .unwrap_or_default()
}

/// Extract a composite `lhs:rhs` id from a JSON object that carries the
/// two component fields at top level — e.g. `{task_id, calendar_event_id}`.
pub(crate) fn extract_composite_pair_id(
    value: &serde_json::Value,
    lhs: &str,
    rhs: &str,
) -> Vec<String> {
    let lhs_val = value.get(lhs).and_then(serde_json::Value::as_str);
    let rhs_val = value.get(rhs).and_then(serde_json::Value::as_str);
    match (lhs_val, rhs_val) {
        (Some(a), Some(b)) => vec![format!("{a}:{b}")],
        _ => Vec::new(),
    }
}

/// Build an entity-ids extractor closure that ignores the response and
/// returns a single, caller-supplied id. Used by routers whose write
/// target is identified by an arg-side identifier (memory key,
/// preference key, habit reminder policy id)
/// rather than by anything in the JSON response. Replaces a `move |_|
/// vec![id]` pattern that was duplicated verbatim at 4 router sites.
pub(crate) fn singleton_id_extractor(id: String) -> impl FnOnce(&serde_json::Value) -> Vec<String> {
    move |_| vec![id]
}
