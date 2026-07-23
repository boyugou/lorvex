//! Shared `Task` sync-payload preparation policy.
//!
//! Derived columns must be stripped from the synced task payload
//! because they are projected from independently-synced child tables
//! (`task_tags`, `task_dependencies`, `task_checklist_items`) and the
//! `lateness_state` column is a UI-derived flag that never round-
//! trips through sync. Including them in the task envelope would
//! make a peer's apply pipeline overwrite its own freshly-applied
//! child rows with a snapshot from the writer's view at enqueue
//! time.
//!
//! Centralizing the strip in this single helper keeps the derived-
//! column list ([`DERIVED_TASK_FIELDS`]) authoritative — every shell
//! (Tauri / MCP / CLI) routes through `strip_derived_task_fields`
//! before enqueueing, so adding a new derived column is one slice
//! edit, not a parallel update across every enqueue site.
//!
//! The function is a pure JSON manipulation — no IO, no error path —
//! so it lives at the lower layer alongside other payload-shape
//! policy. Surface-specific HLC sourcing and outbox bookkeeping stay
//! at the call sites because each shell has its own HLC source.

use serde_json::Value;

/// Names of `Task` JSON fields that must NOT ride on the sync
/// envelope because they are projected from independently-synced
/// child tables or are device-local UI projections.
pub const DERIVED_TASK_FIELDS: &[&str] =
    &["tags", "depends_on", "checklist_items", "lateness_state"];

/// Strip every entry in [`DERIVED_TASK_FIELDS`] from a serialized
/// task JSON object. No-op for non-object values (the caller is
/// trusted to pass a `serde_json::to_value(&task)` shape).
///
/// Returns the stripped payload by value so callers can pipe the
/// result straight into `enqueue_payload_upsert(...)`. The input is
/// consumed because every observed call site already produced a
/// fresh `Value` via `serde_json::to_value`.
pub fn strip_derived_task_fields(mut payload: Value) -> Value {
    if let Value::Object(ref mut obj) = payload {
        for field in DERIVED_TASK_FIELDS {
            obj.remove(*field);
        }
    }
    payload
}

#[cfg(test)]
mod tests;
