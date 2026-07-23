//! Change-tracking funnel for the MCP server.
//!
//! Every mutating tool routes through [`log_change`] which writes the
//! `ai_changelog` row, enqueues the outbox envelopes for both the
//! changelog row and the per-entity payloads, refreshes the widget
//! snapshot, and bumps `local_change_seq`. This module is the thin
//! public-API barrel — the audit + enqueue chain is split across
//! sibling files so each concern has a single source of truth:
//!
//! - [`hlc`] — process-wide `HlcState`, lazy first-init, merge_version
//!   observer, and the [`HlcSession`] adapter.
//! - [`snapshot`] — pre/post-mutation entity reads (per-entity + batched
//!   IN-list variants) plus the `simple_pk_plan` registry.
//! - [`outbox`] — low-level `sync_outbox` writers shared by the
//!   relation, changelog, and per-entity enqueue paths.
//! - [`relations`] — task_tag / task_dependency / task_reminder
//!   relation enqueuers that ride alongside a parent `log_change`.
//! - [`retention`] — retention-preference validation + the
//!   `ai_changelog` row → outbox enqueue helper.
//! - [`log_change`] — the funnel itself plus the preview-only and
//!   local-only audit row writers.

mod hlc;
mod log_change;
mod mutation_executor;
mod outbox;
mod relations;
mod retention;
mod snapshot;

pub(crate) use hlc::{generate_hlc_version, with_hlc_session};
pub(crate) use log_change::{log_change, write_preview_audit_entry, LogChangeParams};
pub(crate) use mutation_executor::{
    execute_mcp_batch_mutation_with_audit_finalizer,
    execute_mcp_batch_mutation_with_undo_audit_finalizer, execute_mcp_mutation,
    execute_mcp_mutation_with_audit_entries_finalizer, execute_mcp_mutation_with_audit_finalizer,
    execute_mcp_mutation_with_dynamic_audit_finalizer, execute_mcp_mutation_with_finalizer,
    execute_mcp_mutation_with_skip_sync_audit_finalizer,
    execute_mcp_mutation_with_skippable_audit_finalizer,
    execute_mcp_mutation_with_tombstone_audit_finalizer,
    execute_mcp_mutation_with_undo_tombstone_audit_finalizer, MutationAuditEntry,
};
pub(crate) use relations::{
    enqueue_deleted_task_dependency_syncs, enqueue_relation_sync,
    enqueue_relation_sync_with_snapshot, enqueue_task_reminder_syncs, enqueue_task_tag_edge_syncs,
};
pub(crate) use snapshot::{
    read_current_entity_snapshot_for_bench, read_current_entity_snapshots_for_bench,
};

#[cfg(test)]
pub(crate) use hlc::{hlc_test_mutex, reset_thread_hlc_for_tests};

use crate::error::McpError;
use lorvex_domain::naming::OP_DELETE;
use lorvex_runtime::get_or_create_device_id;
use rusqlite::Connection;
use serde_json::Value;

// ─── Inlined trivial helpers (`actor.rs` / `sync_checkpoint.rs`) ───

pub(crate) fn resolve_ai_actor_name() -> String {
    std::env::var("LORVEX_AGENT_NAME")
        .ok()
        .map(|name| name.trim().to_string())
        .filter(|name| !name.is_empty())
        .unwrap_or_else(|| "ai".to_string())
}

pub(crate) fn get_or_create_sync_device_id(conn: &Connection) -> Result<String, McpError> {
    Ok(get_or_create_device_id(conn)?)
}

pub(crate) fn write_import_session_audit_entry(
    conn: &Connection,
    operation: &'static str,
    summary: String,
    after_json: Value,
    is_preview: bool,
) -> Result<(), McpError> {
    self::log_change::write_local_audit_entry(
        conn,
        self::log_change::LocalAuditEntryParams {
            operation,
            entity_type: lorvex_domain::naming::ENTITY_IMPORT_SESSION,
            summary,
            mcp_tool: "import_data",
            after_json: Some(after_json),
            is_preview,
        },
    )
}

// ─── Cross-module helpers ────────────────────────────────────────────────
//
// These tiny predicates and the entity-id deduper are used by both
// `log_change` and the relation enqueuers; keeping them at the barrel
// level avoids a circular module dependency between `log_change` and
// `relations` (both consume them, neither owns them).

pub(super) fn dedupe_entity_ids(
    entity_id: Option<String>,
    entity_ids: Option<Vec<String>>,
) -> Vec<String> {
    let mut ids: Vec<String> = Vec::new();
    if let Some(entity_id) = entity_id {
        ids.push(entity_id);
    }
    if let Some(entity_ids) = entity_ids {
        ids.extend(entity_ids);
    }
    let mut unique: Vec<String> = Vec::new();
    for id in ids {
        if id.trim().is_empty() {
            continue;
        }
        if !unique.iter().any(|existing| existing == &id) {
            unique.push(id);
        }
    }
    unique
}

pub(super) fn is_delete_sync_operation(operation: &str) -> bool {
    matches!(operation, OP_DELETE | "permanent_delete")
}

#[cfg(test)]
mod tests;
