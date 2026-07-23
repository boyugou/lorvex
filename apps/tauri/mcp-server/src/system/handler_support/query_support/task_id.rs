//! Small parsing / validation helpers for task identifiers.
//!
//! Split out of `query_support/mod.rs` so the generic id-shape predicates
//! (UUID-form check, LIKE-pattern escaper) and the strict
//! `required_task_id` extractor live next to one another, not interleaved
//! with the multi-row enrichment and suggestion-rendering machinery.

use crate::error::McpError;
use serde_json::Value;

/// Extract a non-empty `id` string from a task JSON value, returning an
/// `McpError::Internal` when the field is missing or empty.
///
/// Pulled into a shared helper so `enrich_tasks_with_reminders`,
/// `fetch_tasks_json_batch`, and `reorder_tasks_to_request_order` all
/// produce the same diagnostic shape on a malformed row instead of
/// each open-coding the same `get("id").and_then(as_str)` ladder.
pub(super) fn required_task_id<'a>(task: &'a Value, context: &str) -> Result<&'a str, McpError> {
    task.get("id")
        .and_then(|v| v.as_str())
        .filter(|id| !id.is_empty())
        .ok_or_else(|| {
            McpError::Internal(format!(
                "malformed task JSON for {context}: missing required non-empty `id` field"
            ))
        })
}

/// Escape `%`, `_`, and `\` for a SQLite LIKE pattern using `\` as the
/// escape character. The caller must pair the parameter with
/// `ESCAPE '\\'` in the SQL text.
pub(super) fn escape_like(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for ch in value.chars() {
        match ch {
            '\\' | '%' | '_' => {
                out.push('\\');
                out.push(ch);
            }
            _ => out.push(ch),
        }
    }
    out
}

/// Match the canonical 8-4-4-4-12 UUID shape so the title-substring
/// fallback is suppressed when the assistant clearly meant an id.
///
/// which classified inputs like `"deadbeef"`, `"12345678"`, or
/// `"--------"` as UUID-shaped — and therefore suppressed title-hit
/// suggestions on plenty of plausible non-UUID needles. Gating on the
/// canonical hyphenated form (36 chars, hex digits, dashes at the
/// 8-4-4-4-12 boundaries) keeps the false-positive surface narrow
/// while still firing on the form `parse_id_with_sentinel` accepts.
pub(super) fn looks_like_uuid(value: &str) -> bool {
    let trimmed = value.trim();
    let bytes = trimmed.as_bytes();
    if bytes.len() != 36 {
        return false;
    }
    for (i, b) in bytes.iter().enumerate() {
        match i {
            8 | 13 | 18 | 23 => {
                if *b != b'-' {
                    return false;
                }
            }
            _ => {
                if !b.is_ascii_hexdigit() {
                    return false;
                }
            }
        }
    }
    true
}
