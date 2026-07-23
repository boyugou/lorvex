use crate::error::{AppError, AppResult};

/// typed `DeleteEnvelope<T>` newtype the `enqueue_*_delete`
/// helpers consume in place of a free-form `serde_json::Value` payload.
/// Carrying the pre-delete snapshot at the type level prevents the
/// degenerate `{id}`-only tombstones the audit found in
/// `enqueue_habit_reminder_policy_delete`, `enqueue_task_reminder_delete`,
/// `enqueue_task_checklist_item_delete`, and `enqueue_preference_delete`
/// (issue #2918-H9).
///
/// The type-level requirement matters because a peer that GC'd its own
/// copy of the entity before the tombstone arrives needs the snapshot
/// to reconstruct the deleted state for its own `before_json` audit
/// row. The MCP server-side has consistent snapshot discipline via
/// `enqueue_payload_delete` + the `tombstones` map; the Tauri app side
/// closes the same gap here.
///
/// Usage: every delete-payload call site loads the row first and
/// wraps it via `DeleteEnvelope::new(id, snapshot)` — there is no
/// `DeleteEnvelope::id_only(...)` constructor on purpose, so the
/// compiler enforces the snapshot discipline against a bare
/// `serde_json::json!({ "id": id })` shortcut.
#[derive(Debug)]
pub(crate) struct DeleteEnvelope<T: serde::Serialize> {
    /// The entity ID — round-trips into the outbox row's `entity_id`
    /// column so peer apply pipelines can address the tombstone.
    pub(crate) id: String,
    /// The pre-delete snapshot. Serialized verbatim into the outbox
    /// row's `payload` column and into the `before_json` audit row;
    /// the audit and the wire envelope are sourced from the same
    /// struct so they cannot drift.
    pub(crate) snapshot: T,
}

impl<T: serde::Serialize> DeleteEnvelope<T> {
    pub(crate) fn new(id: impl Into<String>, snapshot: T) -> Self {
        Self {
            id: id.into(),
            snapshot,
        }
    }

    /// Serialize the envelope to the JSON payload the outbox writer
    /// consumes. Surfaces a typed `AppError::Serialization` on
    /// failure (in practice unreachable for our snapshot types — they
    /// all derive `Serialize` and don't carry types that fail to
    /// serialize).
    pub(super) fn to_payload(&self) -> AppResult<serde_json::Value> {
        serde_json::to_value(&self.snapshot).map_err(AppError::from)
    }
}
