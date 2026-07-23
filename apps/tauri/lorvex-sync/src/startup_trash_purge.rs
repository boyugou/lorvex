//! Shared, sync-safe Trash purge for cold-start maintenance.
//!
//! Expired Trash rows are not mere local storage garbage: hard-deleting a
//! task must publish delete envelopes for the parent row, every synced child
//! or edge that SQLite cascades locally, and every soft-reference aggregate
//! rewired by the cleanup. This module keeps that startup maintenance out of
//! app/MCP/CLI-specific code while letting each surface supply its own HLC
//! generator.

use lorvex_domain::naming::{
    EDGE_TASK_CALENDAR_EVENT_LINK, EDGE_TASK_DEPENDENCY, EDGE_TASK_TAG, ENTITY_CURRENT_FOCUS,
    ENTITY_FOCUS_SCHEDULE, ENTITY_TASK, ENTITY_TASK_CHECKLIST_ITEM, ENTITY_TASK_REMINDER,
};
use rusqlite::{params, Connection};
use serde_json::Value;

use crate::error::SyncError;
use crate::outbox_enqueue::{
    build_dependency_edge_delete_payload, encode_dependency_edge_entity_id, enqueue_payload_delete,
    enqueue_payload_upsert, read_entity_payload_snapshot, OutboxWriteContext,
};

mod api;
mod enqueue;
mod model;
mod purge;
mod references;
mod snapshots;

#[cfg(test)]
mod tests;

pub use api::{
    purge_archived_tasks_older_than, purge_expired_archived_tasks, run_startup_trash_purge,
    trash_cutoff_iso,
};
pub use model::{StartupTrashPurgeReport, StartupTrashPurgeResult, TRASH_RETENTION_DAYS};
