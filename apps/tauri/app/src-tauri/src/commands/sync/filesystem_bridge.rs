#![allow(unused_imports)] // facade re-exports bridge runtime entry points

pub(super) use rusqlite::params;
pub(super) use serde::{Deserialize, Serialize};
pub(super) use std::{
    collections::HashSet,
    fs,
    io::Write,
    path::{Path, PathBuf},
};

pub(super) use crate::db::get_conn;

pub(super) use super::runtime::{
    apply_remote_sync_records_with_checkpoint_writer, compare_sync_versions_with_outbox_id,
    emit_data_changed_for_entity_types, flag_reseed_required_due_to_pending_horizon_in_transaction,
    gc_expired_pending_queues_best_effort, gc_synced_events, get_or_create_sync_device_id_typed,
    is_supported_incoming_record, resolve_filesystem_bridge_root_path,
    upsert_sync_checkpoint_timestamp_if_newer, ApplyRemoteSyncResult, IncomingSyncRecord,
    RemoteApplyMode,
};
pub(super) use crate::commands::{
    sync_timestamp_now, FILESYSTEM_BRIDGE_CURSOR_LOOKBACK_CAP_MULTIPLIER,
    FILESYSTEM_BRIDGE_CURSOR_LOOKBACK_SECONDS, MAX_SYNC_EVENTS_LIMIT,
    SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LAST_PULL_CURSOR_KEY,
    SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LOOKBACK_KNOWN_ID_SKIPPED_LAST_RUN_AT_KEY,
    SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LOOKBACK_KNOWN_ID_SKIPPED_LAST_RUN_KEY,
};

mod collection;
mod cursor;
mod diagnostics;
mod lease_heartbeat;
pub(crate) mod runtime;

#[cfg(test)]
pub(crate) use collection::collect_remote_filesystem_bridge_envelopes;
pub(crate) use cursor::store_filesystem_bridge_pull_cursor;
#[cfg(test)]
pub(crate) use cursor::{
    load_filesystem_bridge_pull_cursor, newest_filesystem_bridge_pull_cursor,
    FilesystemBridgePullCursor,
};
pub use runtime::{run_filesystem_bridge_sync, FilesystemBridgeSyncResult};
