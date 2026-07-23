//! Per-shape executor delegates kept on top of [`super::core::execute_with`]
//! so the 50+ MCP call sites read at the call-site as a single named
//! operation rather than an open-coded `params_builder + ExecuteOptions`
//! tuple. Each is a one-call wrapper — the audit-emission and
//! finalize-ordering rules live in [`super::core::execute_with`] alone,
//! not duplicated per shape.

use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationExecution, MutationOutput};
use rusqlite::Connection;
use serde_json::Value;
use std::collections::HashMap;

use super::audit_entry::MutationAuditEntry;
use super::core::{execute_with, execute_with_audit_entries};
use super::options::ExecuteOptions;
use super::params::{audit_params, batch_audit_params, tombstone_audit_params};
use crate::error::McpError;

/// Standard single-entity audit emit with no extra finalizer work.
pub(crate) fn execute_mcp_mutation<M>(
    conn: &Connection,
    mutation: &M,
    mcp_tool: &'static str,
    entity_id: impl Into<String>,
) -> Result<MutationOutput, McpError>
where
    M: Mutation,
{
    execute_mcp_mutation_map_store_error(conn, mutation, mcp_tool, entity_id, McpError::from)
}

/// Like [`execute_mcp_mutation`] but with a caller-supplied store-error
/// mapper. Used by sites that want to project specific [`StoreError`]
/// variants into domain-specific [`McpError`] tags before they reach
/// the contract surface.
pub(crate) fn execute_mcp_mutation_map_store_error<M, MapStoreError>(
    conn: &Connection,
    mutation: &M,
    mcp_tool: &'static str,
    entity_id: impl Into<String>,
    map_store_error: MapStoreError,
) -> Result<MutationOutput, McpError>
where
    M: Mutation,
    MapStoreError: Fn(StoreError) -> McpError,
{
    let entity_id = entity_id.into();
    execute_with(
        conn,
        mutation,
        map_store_error,
        ExecuteOptions::default(),
        |execution| audit_params(execution, mcp_tool, entity_id),
        |_, _| Ok(()),
    )
}

/// Single-entity audit emit + post-mutation finalizer.
pub(crate) fn execute_mcp_mutation_with_audit_finalizer<M, MapStoreError, Finalize>(
    conn: &Connection,
    mutation: &M,
    mcp_tool: &'static str,
    entity_id: impl Into<String>,
    map_store_error: MapStoreError,
    finalize: Finalize,
) -> Result<MutationOutput, McpError>
where
    M: Mutation,
    MapStoreError: Fn(StoreError) -> McpError,
    Finalize: FnOnce(&Connection, &MutationExecution) -> Result<(), McpError>,
{
    let entity_id = entity_id.into();
    execute_with(
        conn,
        mutation,
        map_store_error,
        ExecuteOptions::default(),
        |execution| audit_params(execution, mcp_tool, entity_id),
        finalize,
    )
}

/// Same as [`execute_mcp_mutation_with_audit_finalizer`] but the entity
/// id is computed from the captured [`MutationExecution`] rather than
/// known up front. Used by upsert tools whose generated row id only
/// exists after `apply`.
pub(crate) fn execute_mcp_mutation_with_dynamic_audit_finalizer<
    M,
    MapStoreError,
    EntityId,
    Finalize,
>(
    conn: &Connection,
    mutation: &M,
    mcp_tool: &'static str,
    map_store_error: MapStoreError,
    entity_id: EntityId,
    finalize: Finalize,
) -> Result<MutationOutput, McpError>
where
    M: Mutation,
    MapStoreError: Fn(StoreError) -> McpError,
    EntityId: FnOnce(&MutationExecution) -> String,
    Finalize: FnOnce(&Connection, &MutationExecution) -> Result<(), McpError>,
{
    execute_with(
        conn,
        mutation,
        map_store_error,
        ExecuteOptions::default(),
        |execution| audit_params(execution, mcp_tool, entity_id(execution)),
        finalize,
    )
}

/// Variant for compute-and-log tools whose audit row records intent
/// without an actual row mutation — emits the audit row but skips the
/// per-entity sync enqueue.
pub(crate) fn execute_mcp_mutation_with_skip_sync_audit_finalizer<M, MapStoreError, Finalize>(
    conn: &Connection,
    mutation: &M,
    mcp_tool: &'static str,
    entity_id: impl Into<String>,
    map_store_error: MapStoreError,
    finalize: Finalize,
) -> Result<MutationOutput, McpError>
where
    M: Mutation,
    MapStoreError: Fn(StoreError) -> McpError,
    Finalize: FnOnce(&Connection, &MutationExecution) -> Result<(), McpError>,
{
    let entity_id = entity_id.into();
    execute_with(
        conn,
        mutation,
        map_store_error,
        ExecuteOptions::default(),
        |execution| audit_params(execution, mcp_tool, entity_id).skip_sync(),
        finalize,
    )
}

/// Variant for idempotent link mutations whose apply path may report a
/// no-op via an extra flag — emits the audit row only when
/// `should_log(&execution)` returns true; finalizer still runs.
pub(crate) fn execute_mcp_mutation_with_skippable_audit_finalizer<
    M,
    MapStoreError,
    ShouldLog,
    Finalize,
>(
    conn: &Connection,
    mutation: &M,
    mcp_tool: &'static str,
    entity_id: impl Into<String>,
    map_store_error: MapStoreError,
    should_log: ShouldLog,
    finalize: Finalize,
) -> Result<MutationOutput, McpError>
where
    M: Mutation,
    MapStoreError: Fn(StoreError) -> McpError,
    ShouldLog: FnOnce(&MutationExecution) -> bool + 'static,
    Finalize: FnOnce(&Connection, &MutationExecution) -> Result<(), McpError>,
{
    let entity_id = entity_id.into();
    execute_with(
        conn,
        mutation,
        map_store_error,
        ExecuteOptions::default().with_emit_if(should_log),
        |execution| audit_params(execution, mcp_tool, entity_id),
        finalize,
    )
}

/// Multi-emit variant. See [`super::core::execute_with_audit_entries`].
pub(crate) fn execute_mcp_mutation_with_audit_entries_finalizer<
    M,
    MapStoreError,
    Entries,
    Finalize,
>(
    conn: &Connection,
    mutation: &M,
    mcp_tool: &'static str,
    map_store_error: MapStoreError,
    entries: Entries,
    finalize: Finalize,
) -> Result<MutationOutput, McpError>
where
    M: Mutation,
    MapStoreError: Fn(StoreError) -> McpError,
    Entries: FnOnce(&MutationExecution) -> Result<Vec<MutationAuditEntry>, McpError>,
    Finalize: FnOnce(&Connection, &MutationExecution) -> Result<(), McpError>,
{
    execute_with_audit_entries(conn, mutation, mcp_tool, map_store_error, entries, finalize)
}

/// Batch variant: audit row carries `entity_ids: Vec<String>` instead
/// of a single `entity_id`.
pub(crate) fn execute_mcp_batch_mutation_with_audit_finalizer<M, MapStoreError, Finalize>(
    conn: &Connection,
    mutation: &M,
    mcp_tool: &'static str,
    entity_ids: Vec<String>,
    map_store_error: MapStoreError,
    finalize: Finalize,
) -> Result<MutationOutput, McpError>
where
    M: Mutation,
    MapStoreError: Fn(StoreError) -> McpError,
    Finalize: FnOnce(&Connection, &MutationExecution) -> Result<(), McpError>,
{
    execute_with(
        conn,
        mutation,
        map_store_error,
        ExecuteOptions::default(),
        |execution| batch_audit_params(execution, mcp_tool, entity_ids),
        finalize,
    )
}

/// Batch variant carrying a serialized undo token on the audit row.
pub(crate) fn execute_mcp_batch_mutation_with_undo_audit_finalizer<M, MapStoreError, Finalize>(
    conn: &Connection,
    mutation: &M,
    mcp_tool: &'static str,
    entity_ids: Vec<String>,
    undo_token_json: String,
    map_store_error: MapStoreError,
    finalize: Finalize,
) -> Result<MutationOutput, McpError>
where
    M: Mutation,
    MapStoreError: Fn(StoreError) -> McpError,
    Finalize: FnOnce(&Connection, &MutationExecution) -> Result<(), McpError>,
{
    execute_with(
        conn,
        mutation,
        map_store_error,
        ExecuteOptions::default(),
        |execution| {
            batch_audit_params(execution, mcp_tool, entity_ids).with_undo_token(undo_token_json)
        },
        finalize,
    )
}

/// Delete-shaped variant: runs the finalizer BEFORE the audit row,
/// short-circuits when the apply pass reports `deleted == false`
/// (idempotent delete-of-missing), and threads `tombstone_payloads`
/// into the per-entity sync envelopes.
pub(crate) fn execute_mcp_mutation_with_tombstone_audit_finalizer<M, MapStoreError, Finalize>(
    conn: &Connection,
    mutation: &M,
    mcp_tool: &'static str,
    entity_id: impl Into<String>,
    tombstone_payloads: HashMap<String, Value>,
    map_store_error: MapStoreError,
    finalize: Finalize,
) -> Result<MutationOutput, McpError>
where
    M: Mutation,
    MapStoreError: Fn(StoreError) -> McpError,
    Finalize: FnOnce(&Connection, &MutationExecution) -> Result<(), McpError>,
{
    let entity_id = entity_id.into();
    execute_with(
        conn,
        mutation,
        map_store_error,
        ExecuteOptions::default().with_tombstone(tombstone_payloads),
        |execution| tombstone_audit_params(execution, mcp_tool, entity_id),
        finalize,
    )
}

/// Like [`execute_mcp_mutation_with_tombstone_audit_finalizer`] plus a
/// serialized undo token on the audit row.
#[allow(clippy::too_many_arguments)]
pub(crate) fn execute_mcp_mutation_with_undo_tombstone_audit_finalizer<M, MapStoreError, Finalize>(
    conn: &Connection,
    mutation: &M,
    mcp_tool: &'static str,
    entity_id: impl Into<String>,
    undo_token_json: String,
    tombstone_payloads: HashMap<String, Value>,
    map_store_error: MapStoreError,
    finalize: Finalize,
) -> Result<MutationOutput, McpError>
where
    M: Mutation,
    MapStoreError: Fn(StoreError) -> McpError,
    Finalize: FnOnce(&Connection, &MutationExecution) -> Result<(), McpError>,
{
    let entity_id = entity_id.into();
    execute_with(
        conn,
        mutation,
        map_store_error,
        ExecuteOptions::default().with_tombstone(tombstone_payloads),
        |execution| {
            tombstone_audit_params(execution, mcp_tool, entity_id).with_undo_token(undo_token_json)
        },
        finalize,
    )
}
