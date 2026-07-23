//! Shared outbox enqueue core — the canonical write path for sync outbox enqueue.
//!
//! Both the MCP server and the Tauri app should call these functions after any
//! entity mutation, instead of duplicating version stamping, payload shadow
//! merge/remove, canonicalization, and outbox envelope construction. This ensures:
//!
//! - Consistent snapshot reading
//! - Canonical JSON serialization
//! - Correct version stamping
//! - Coalesced outbox enqueue (dedup of rapid writes)
//!
//! Per-concern siblings:
//! - [`context`]          — `OutboxWriteContext` caller bundle
//! - [`payload`]          — version-stamp + shadow + coalesce + tombstone pipeline
//! - [`snapshot`]         — DB → JSON snapshot reader (+ public read wrapper)
//! - [`entity`]           — read-snapshot-then-upsert convenience entry point
//! - [`dependency_edge`]  — `task_dependencies` wire-shape helpers
//! - [`child_tombstones`] — bulk child-row tombstones for delete cascades
//! - [`error`]            — `EnqueueError` typed error surface

mod child_tombstones;
mod context;
mod dependency_edge;
mod entity;
mod error;
mod payload;
mod snapshot;

pub use child_tombstones::{
    enqueue_edge_tombstones_for_calendar_event_delete, tombstone_completions_for_habit_delete,
    tombstone_edges_for_calendar_event_delete, tombstone_reminder_policies_for_habit_delete,
    DeletedHabitCompletionSnapshot, DeletedHabitReminderPolicySnapshot,
    DeletedTaskCalendarEventLinkSnapshot,
};
pub use context::OutboxWriteContext;
pub use dependency_edge::{build_dependency_edge_delete_payload, encode_dependency_edge_entity_id};
pub use entity::enqueue_entity_upsert;
pub use error::EnqueueError;
pub use payload::{enqueue_payload_delete, enqueue_payload_upsert, pending_drain_failure_count};
pub use snapshot::read_entity_payload_snapshot;

#[cfg(test)]
mod tests;
