//! Core executor entry points: drive a [`Mutation`] inside an HLC
//! session and route the captured [`MutationExecution`] to the caller's
//! audit / finalize callbacks.

use lorvex_store::StoreError;
use lorvex_workflow::mutation::{
    execute_with_context, Mutation, MutationContext, MutationExecution, MutationOutput,
};
use rusqlite::Connection;
use serde_json::Value;

use super::audit_entry::MutationAuditEntry;
use super::options::{ExecuteOptions, TOMBSTONE_DELETED_KEY};
use crate::error::McpError;
use crate::runtime::change_tracking::{log_change, with_hlc_session, LogChangeParams};

/// Drive one [`Mutation`] and emit at most one audit row.
///
/// `params_builder` receives the captured [`MutationExecution`] and
/// returns the fully-composed [`LogChangeParams`] for the audit row.
/// Putting the builder in the caller's hands instead of synthesizing
/// it inside per-shape wrappers lets one entry point cover every
/// variant the codebase express via 8 near-identical wrapper
/// fns — static vs dynamic entity-id, batch `entity_ids`, `skip_sync`,
/// `undo_token`, and the conditional-emit / tombstone shapes (the
/// latter two through [`ExecuteOptions`]).
///
/// `finalize` runs in the same transaction as the audit row, either
/// before or after it depending on [`ExecuteOptions::finalize_before_audit`].
pub(crate) fn execute_with<M, MapStoreError, ParamsBuilder, Finalize>(
    conn: &Connection,
    mutation: &M,
    map_store_error: MapStoreError,
    options: ExecuteOptions,
    params_builder: ParamsBuilder,
    finalize: Finalize,
) -> Result<MutationOutput, McpError>
where
    M: Mutation,
    MapStoreError: Fn(StoreError) -> McpError,
    ParamsBuilder: FnOnce(&MutationExecution) -> LogChangeParams,
    Finalize: FnOnce(&Connection, &MutationExecution) -> Result<(), McpError>,
{
    let ExecuteOptions {
        tombstone_payloads,
        finalize_before_audit,
        should_emit,
    } = options;

    execute_mcp_mutation_with_finalizer(conn, mutation, map_store_error, move |execution| {
        let emit_audit = |execution: &MutationExecution| -> Result<(), McpError> {
            let suppress_for_no_op_delete = tombstone_payloads.is_some()
                && execution
                    .output
                    .after
                    .get(TOMBSTONE_DELETED_KEY)
                    .and_then(Value::as_bool)
                    == Some(false);
            let suppress_for_predicate = should_emit
                .map(|predicate| !predicate(execution))
                .unwrap_or(false);

            if !suppress_for_no_op_delete && !suppress_for_predicate {
                let params = params_builder(execution);
                log_change(conn, params, tombstone_payloads.as_ref())?;
            }
            Ok(())
        };

        if finalize_before_audit {
            finalize(conn, &execution)?;
            emit_audit(&execution)?;
        } else {
            emit_audit(&execution)?;
            finalize(conn, &execution)?;
        }
        Ok(())
    })
}

/// Drive one [`Mutation`] and emit N audit rows, one per
/// [`MutationAuditEntry`] yielded by `entries`.
///
/// The multi-emit shape is rare (currently `batch_link_tasks_to_event`
/// / `batch_unlink_tasks_from_event`) and intentionally separate from
/// [`execute_with`]: single-row callers stay on the more ergonomic
/// `params_builder -> LogChangeParams` signature, while multi-emit
/// callers get a `Result<Vec<_>, _>` builder that can fail before any
/// row is written.
pub(crate) fn execute_with_audit_entries<M, MapStoreError, Entries, Finalize>(
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
    execute_mcp_mutation_with_finalizer(conn, mutation, map_store_error, |execution| {
        for entry in entries(&execution)? {
            log_change(
                conn,
                LogChangeParams::new(
                    execution.operation,
                    execution.entity_kind,
                    mcp_tool,
                    entry.summary,
                )
                .with_entity_id(entry.entity_id)
                .with_before_opt(entry.before)
                .with_after(entry.after),
                None,
            )?;
        }
        finalize(conn, &execution)
    })
}

/// Lower-level executor: drives the [`Mutation`] inside an
/// [`with_hlc_session`] block, captures the [`MutationExecution`], and
/// hands it to `finalize`. The audit-row write itself is the
/// finalizer's responsibility — most call sites should instead reach
/// for [`execute_with`] / [`execute_with_audit_entries`] which handle
/// that funnel inline.
///
/// Used directly by mutations whose post-write work doesn't fit the
/// audit-row shape at all (e.g. `batch_cancel` defers its audit writes
/// to a follow-up pass).
pub(crate) fn execute_mcp_mutation_with_finalizer<M, MapStoreError, Finalize>(
    conn: &Connection,
    mutation: &M,
    map_store_error: MapStoreError,
    finalize: Finalize,
) -> Result<MutationOutput, McpError>
where
    M: Mutation,
    MapStoreError: Fn(StoreError) -> McpError,
    Finalize: FnOnce(MutationExecution) -> Result<(), McpError>,
{
    let mut staged_execution: Option<MutationExecution> = None;
    let output = with_hlc_session(conn, |session| {
        let cx = MutationContext::new(session);
        execute_with_context(mutation, conn, &cx, map_store_error, |execution| {
            staged_execution = Some(execution);
            Ok(())
        })
    })?;
    let execution =
        staged_execution.expect("Mutation contract: execute_with_context staged finalizer payload");
    finalize(execution)?;
    Ok(output)
}
