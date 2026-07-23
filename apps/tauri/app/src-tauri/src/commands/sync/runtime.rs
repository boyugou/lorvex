#![allow(unused_imports)] // sync facade re-exports command/runtime entry points

pub(super) use crate::db::{get_conn, get_read_conn};
pub(super) use rusqlite::params;
pub(super) use serde::{Deserialize, Serialize};
pub(super) use std::path::PathBuf;

pub(super) use crate::commands::{
    clamp_limit, parse_rfc3339_utc, rows_from_query, sync_timestamp_now, Task, TaskList,
    MAX_SYNC_EVENTS_LIMIT, SYNC_GC_RETENTION_DAYS,
};

pub(crate) mod apply;
pub(crate) mod cancel;
mod cancel_signal;
mod maintenance;
pub(crate) mod queue;
pub(crate) mod status;

pub(crate) use cancel_signal::{
    is_cancelled_for as is_sync_cancelled_for, request_cancel_all, CancelGuard, SyncKind,
};

pub use apply::{ApplyRemoteSyncResult, IncomingSyncRecord};
pub use queue::{get_pending_outbox_entries, get_recent_outbox_entries, SyncOutboxEntry};
#[cfg(test)]
pub(crate) use status::load_sync_status_from_conn;
pub use status::{get_sync_status, SyncStatus};

#[cfg(test)]
pub(crate) use apply::incoming_records_match_for_file_idempotency;
#[cfg(test)]
pub(crate) use apply::{
    apply_remote_sync_envelopes_internal,
    apply_remote_sync_envelopes_with_filesystem_bridge_cursor, latest_entity_sync_version,
    sync_entity_apply_priority,
};
pub(crate) use apply::{
    apply_remote_sync_records_with_checkpoint_writer, compare_sync_versions,
    compare_sync_versions_with_outbox_id, emit_data_changed_for_entity_types,
    is_supported_incoming_record, upsert_sync_checkpoint_timestamp_if_newer, RemoteApplyMode,
};
pub(crate) use maintenance::{
    flag_reseed_required_due_to_pending_horizon_in_transaction,
    gc_expired_pending_queues_best_effort,
};
#[cfg(test)]
pub(crate) use queue::mark_outbox_entries_synced_internal;
#[cfg(test)]
pub(crate) use queue::mark_outbox_entry_retry_internal;
pub(crate) use queue::seed_full_sync_internal;
pub(crate) use queue::{
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
    gc_synced_events,
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
    resolve_filesystem_bridge_root_path,
    DeleteEnvelope,
};
