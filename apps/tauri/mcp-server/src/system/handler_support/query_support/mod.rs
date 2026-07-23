//! Query-support helpers shared across MCP read/write tools.
//!
//! The module is split by concern:
//!
//! * [`task_id`] — small parsing / validation helpers
//!   (`required_task_id`, `escape_like`, `looks_like_uuid`).
//! * [`suggestions`] — did-you-mean machinery for task-not-found errors
//!   (#2371): prefix + title-substring scans, `Did you mean: …` rendering,
//!   and the `task_not_found_with_suggestions` constructor.
//! * [`enrich`] — task-row enrichment + multi-row fetch family
//!   (`enrich_tasks_for_response`, `fetch_task_json`, `reload_task_json`,
//!   `fetch_tasks_json_batch`, `fetch_existing_*_tasks_json`).
//!
//! This file owns only the small generic helpers (pagination bounds,
//! null-aware `Value` coercions, JSON field extractors, `plural_s`)
//! plus the curated re-export surface — keeping cross-module imports
//! pinned to a single namespace.

mod enrich;
mod suggestions;
mod task_id;

#[cfg(test)]
mod tests;

pub(crate) use enrich::{
    enrich_and_fence_tasks_for_response, fetch_existing_active_tasks_json,
    fetch_existing_tasks_json, fetch_task_json, fetch_tasks_json_batch, reload_task_json,
};

use serde_json::Value;

pub(crate) fn bounded_limit(value: u32, default: u32, cap: u32) -> u32 {
    let normalized = if value == 0 { default } else { value };
    normalized.min(cap)
}

pub(crate) fn bounded_limit_or_default(value: Option<u32>, default: u32, cap: u32) -> u32 {
    bounded_limit(value.unwrap_or(default), default, cap)
}

/// Compute the canonical `next_offset` value for a paginated MCP
/// response. Returns `Some(offset + returned)` only when the page is
/// non-empty AND more rows remain past the consumed window; `None`
/// otherwise. Pre-extraction this expression was inlined verbatim at
/// 14 different sites across the lists / calendar / logs / sync /
/// review / task-query handlers — every copy used the same
/// `if has_more && returned > 0 { Some(consumed as u64) } else { None }`
/// shape, just with slightly different precomputed `truncated` /
/// `total_matching > consumed` predicates feeding the boolean.
///
/// Callers pass the already-computed `has_more` predicate (so the
/// helper does not need to know whether the count came from a
/// `COUNT(*)` query, a `LIMIT+1` overshoot probe, or an in-memory
/// `truncated` flag) and the `consumed = offset + returned` total.
pub(crate) fn next_offset_for_page(has_more: bool, consumed: i64, returned: i64) -> Option<u64> {
    (has_more && returned > 0).then_some(consumed as u64)
}

pub(crate) fn required_json_string_field<'a>(
    value: &'a Value,
    field: &str,
    context: &str,
) -> Result<&'a str, String> {
    value.get(field).and_then(Value::as_str).ok_or_else(|| {
        format!("Error: malformed JSON payload for {context}: expected string field '{field}'")
    })
}

pub(crate) fn required_json_i64_field(
    value: &Value,
    field: &str,
    context: &str,
) -> Result<i64, String> {
    value.get(field).and_then(Value::as_i64).ok_or_else(|| {
        format!("Error: malformed JSON payload for {context}: expected integer field '{field}'")
    })
}

pub(crate) const fn plural_s(count: usize) -> &'static str {
    if count == 1 {
        ""
    } else {
        "s"
    }
}
