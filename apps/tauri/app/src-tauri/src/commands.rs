pub(crate) mod app_services;
pub(crate) mod bootstrap;
pub(crate) mod calendar;
pub(crate) mod data;
pub(crate) mod day_context;
pub(crate) mod device_state;
pub(crate) mod diagnostics;
pub(crate) mod habits;
pub(crate) mod lists;
pub(crate) mod memory;
pub(crate) mod overview;
pub(crate) mod planning;
pub(crate) mod reviews;
pub(crate) mod saved_queries;
pub(crate) mod settings;
pub(crate) mod shared;
pub(crate) mod sync;
pub(crate) mod tasks;
pub(crate) mod ui;

#[cfg(test)]
use calendar::events::{delete_calendar_event_internal, update_calendar_event_internal};
#[allow(unused_imports)]
pub(crate) use calendar::events::{normalize_calendar_recurrence, CalendarEvent};
pub(crate) use day_context::{normalize_date_input_for_conn, trailing_day_window_bounds_for_conn};
#[cfg(test)]
pub(crate) use day_context::{
    normalize_date_input_for_timezone, trailing_day_window_bounds_for_conn_at,
};
#[cfg(test)]
use diagnostics::{
    read_ai_changelog_entries, read_ai_changelog_entries_for_entity, read_error_logs,
};
#[cfg(test)]
use lists::{delete_list_internal, query_list_tasks_with_recent_completed};
#[cfg(test)]
pub(crate) use settings::preferences::default_sync_backend_kind;
pub(crate) use shared::{
    clamp_limit, fetch_list_by_id, fetch_ordered_active_tasks_by_ids, fetch_ordered_tasks_by_ids,
    fetch_task_by_id, fetch_task_row_unenriched, fetch_tasks_by_ids, is_syncable_entity_type,
    link_tag_to_task, list_from_row, parse_canonical_json_value, parse_rfc3339_utc,
    rows_from_query, sanitize_db_error, sync_timestamp_now, task_from_row, task_list_from_list_row,
    tasks_from_query, tasks_from_task_rows, validate_task_ids_active, with_immediate_transaction,
    OptionalExt, FILESYSTEM_BRIDGE_CURSOR_LOOKBACK_CAP_MULTIPLIER,
    FILESYSTEM_BRIDGE_CURSOR_LOOKBACK_SECONDS, LIST_COLS, MAX_REMINDER_QUERY_WINDOW_SECONDS,
    MAX_SYNC_EVENTS_LIMIT, MAX_UPCOMING_DAYS,
    SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LAST_PULL_CURSOR_KEY,
    SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LOOKBACK_KNOWN_ID_SKIPPED_LAST_RUN_AT_KEY,
    SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LOOKBACK_KNOWN_ID_SKIPPED_LAST_RUN_KEY,
    SYNC_GC_RETENTION_DAYS, TASK_COLS,
};
#[cfg(test)]
pub(crate) use shared::{date_plus_days_ymd_local_for_test, today_ymd_local_for_test};
pub use shared::{
    CurrentFocusSummary, CurrentFocusWithTasks, DeleteListResult, FocusScheduleWithTasks,
    ListWithCount, Overview, ScheduleBlock, Stats, Task, TaskChecklistItem, TaskList, TaskReminder,
};
#[cfg(test)]
pub(crate) use ui::runtime_status::get_runtime_paths;

#[cfg(test)]
use sync::filesystem_bridge::{
    collect_remote_filesystem_bridge_envelopes, load_filesystem_bridge_pull_cursor,
    newest_filesystem_bridge_pull_cursor,
};
#[cfg(test)]
use sync::filesystem_bridge::{store_filesystem_bridge_pull_cursor, FilesystemBridgePullCursor};

pub(crate) use sync::runtime::get_or_create_sync_device_id_typed;
#[cfg(test)]
use sync::runtime::{
    apply_remote_sync_envelopes_internal,
    apply_remote_sync_envelopes_with_filesystem_bridge_cursor,
    apply_remote_sync_records_with_checkpoint_writer, compare_sync_versions,
    incoming_records_match_for_file_idempotency, latest_entity_sync_version,
    load_sync_status_from_conn, mark_outbox_entries_synced_internal,
    mark_outbox_entry_retry_internal, resolve_filesystem_bridge_root_path,
    sync_entity_apply_priority, upsert_sync_checkpoint_timestamp_if_newer, RemoteApplyMode,
};
// Outbox enqueue helpers — single consolidated re-export wall.
// The canonical home for these functions is
// `commands::sync::runtime::queue::enqueue::*`; the wall keeps the
// `crate::commands::enqueue_*` short path that every command-tree
// caller has depended on since the layer was introduced. The premise
// in #3339 of forwarding to `lorvex_sync::outbox::*` is incorrect —
// these helpers wrap rusqlite + the Tauri-side outbox payload codec
// and have no equivalent in `lorvex-sync`.
pub(crate) use sync::runtime::{
    enqueue_affected_dependents, enqueue_calendar_to_outbox, enqueue_current_focus_upsert_for_date,
    enqueue_dependency_edge_upsert, enqueue_focus_schedule_upsert_for_date,
    enqueue_lifecycle_sync_plan, enqueue_list_delete_with_version, enqueue_list_upsert,
    enqueue_preference_delete, enqueue_preference_upsert, enqueue_tag_upsert,
    enqueue_task_checklist_item_delete, enqueue_task_checklist_item_upsert,
    enqueue_task_delete_with_version, enqueue_task_reminder_delete, enqueue_task_reminder_upsert,
    enqueue_task_upsert, enqueue_to_outbox_typed,
};
// surfaced for the startup pending-inbox drain in
// `db::connection::schedule_startup_maintenance`, which fans out
// `data-changed` events for entity types the drain just unblocked.
pub(crate) use sync::runtime::emit_data_changed_for_entity_types;
// typed delete envelopes + pre-delete snapshot loaders.
#[cfg(test)]
use sync::runtime::IncomingSyncRecord;
pub(crate) use sync::runtime::{
    enqueue_task_calendar_event_link_delete, enqueue_task_tag_delete,
    load_preference_pre_delete_snapshot, load_task_calendar_event_link_pre_delete_snapshot,
    load_task_calendar_event_link_pre_delete_snapshots,
    load_task_checklist_item_pre_delete_snapshot, load_task_checklist_item_pre_delete_snapshots,
    load_task_reminder_pre_delete_snapshot, load_task_reminder_pre_delete_snapshots,
    load_task_tag_pre_delete_snapshots, DeleteEnvelope,
};
// Lifecycle hammer used from the `RunEvent::Exit` handler to abort any
// in-flight sync loop at the next probe instead of dragging shutdown
// out behind a network round trip.
pub(crate) use sync::runtime::request_cancel_all;

#[cfg(test)]
use lists::{update_list_with_conn, UpdateListArgs};
pub(crate) use tasks::dependencies::cleanup_task_dependency_refs_after_removal;
#[cfg(test)]
use tasks::queries::build_get_all_tasks_sql;
pub(crate) use tasks::reminders::snooze_reminder_for_task_internal;
pub(crate) use tasks::{complete_task_internal, run_startup_trash_purge, undo_task_lifecycle};
#[cfg(desktop)]
pub(crate) use ui::window_commands::hide_popover_window;

// Brings the build.rs-generated handler registration function into this
// module, where it can reference the private command tree directly.
include!(concat!(env!("OUT_DIR"), "/handler_inventory.rs"));

#[cfg(test)]
mod tests;
