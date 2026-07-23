//! Dry-run flag stamping for the batch task-write previews.
//!
//! The three batch verbs (`task.batch_create`, `task.batch_update`,
//! `task.batch_cancel_in_list`) each support `--dry-run`. The workflow
//! crate returns the same `*Result` shape for preview vs commit; the
//! CLI marks the rendered payload with `"dry_run": true` so the JSON
//! envelope a caller receives is self-describing. The shape contract
//! is identical across the three verbs, so it lives in one helper.

use serde_json::{json, Value};

/// Insert a top-level `"dry_run": true` flag into `payload` if it is a
/// JSON object; if it is any other shape, wrap it under
/// `{"dry_run": true, "preview": <original>}`. The wrap branch is
/// defensive — every batch workflow currently emits an object — but
/// keeping it preserves caller compatibility if the workflow shape
/// drifts.
pub(crate) fn stamp_dry_run_flag(payload: &mut Value) {
    if let Value::Object(object) = payload {
        object.insert("dry_run".to_string(), Value::Bool(true));
        return;
    }
    let original = std::mem::replace(payload, Value::Null);
    *payload = json!({ "dry_run": true, "preview": original });
}
