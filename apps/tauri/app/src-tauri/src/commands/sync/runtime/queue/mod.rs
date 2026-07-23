#![allow(unused_imports)] // queue facade re-exports sync entry points

pub(super) use super::*;

// `enqueue.rs` is the public facade; #3441 phase-2 collapsed the
// former `enqueue/` directory into flat `enqueue_*` siblings to keep
// depth ≤3.
mod enqueue;
mod enqueue_aggregates;
mod enqueue_child_items;
mod enqueue_core;
mod enqueue_edge_snapshots;
mod enqueue_envelope;
mod enqueue_imports;
mod enqueue_lifecycle;
mod enqueue_task_entities;
pub(crate) mod events;
mod filesystem_bridge_root_path;
pub(crate) mod retry;
// `seed.rs` is the public facade; #3441 phase-2 collapsed the former
// `seed/` directory into flat `seed_*` siblings to keep depth ≤3.
mod seed;
mod seed_entities;
mod seed_helpers;
pub(crate) mod seed_orchestrator;
#[cfg(test)]
mod seed_tests;
mod types;

pub use events::{get_pending_outbox_entries, get_recent_outbox_entries};
pub use types::SyncOutboxEntry;

pub(crate) use enqueue::{
    enqueue_affected_dependents,
    enqueue_calendar_to_outbox,
    enqueue_current_focus_upsert_for_date,
    enqueue_dependency_edge_upsert,
    enqueue_focus_schedule_upsert_for_date,
    enqueue_lifecycle_sync_plan,
    enqueue_lifecycle_transition,
    enqueue_list_delete_with_version,
    enqueue_list_upsert,
    enqueue_preference_delete,
    enqueue_preference_upsert,
    enqueue_tag_upsert,
    enqueue_task_calendar_event_link_delete,
    enqueue_task_checklist_item_delete,
    enqueue_task_checklist_item_upsert,
    enqueue_task_delete_with_version,
    enqueue_task_reminder_delete,
    enqueue_task_reminder_upsert,
    enqueue_task_tag_delete,
    enqueue_task_upsert,
    enqueue_to_outbox_typed,
    get_or_create_sync_device_id_typed,
    // typed delete
    // envelopes + their pre-delete snapshot loaders.
    load_preference_pre_delete_snapshot,
    load_task_calendar_event_link_pre_delete_snapshot,
    load_task_calendar_event_link_pre_delete_snapshots,
    load_task_checklist_item_pre_delete_snapshot,
    load_task_checklist_item_pre_delete_snapshots,
    load_task_reminder_pre_delete_snapshot,
    load_task_reminder_pre_delete_snapshots,
    load_task_tag_pre_delete_snapshot,
    load_task_tag_pre_delete_snapshots,
    DeleteEnvelope,
};
pub(crate) use filesystem_bridge_root_path::resolve_filesystem_bridge_root_path;
pub(crate) use retry::gc_synced_events;
#[cfg(test)]
pub(crate) use retry::mark_outbox_entries_synced_internal;
#[cfg(test)]
pub(crate) use retry::mark_outbox_entry_retry_internal;
pub(crate) use seed::seed_full_sync_internal;
