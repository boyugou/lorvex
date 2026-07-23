//! Shared changelog audit shims for the clear / remove paths.
//!
//! `clear_current_focus` always emits a DELETE-op changelog with the
//! prior plan as the tombstone payload. `remove_from_current_focus`
//! switches between DELETE (when the last task left the plan, encoded
//! as `plan_cleared = true` in the mutation output) and UPDATE (the
//! plan still has tasks) — both shapes need the pre-mutation row in
//! the changelog `before_json`.
//!
//! The set / add paths emit their changelog through the standard
//! `execute_mcp_mutation` finalizer, so they don't surface here.

use std::collections::HashMap;

use lorvex_domain::naming::{ENTITY_CURRENT_FOCUS, OP_DELETE};
use lorvex_workflow::current_focus::load_current_focus_enriched;
use lorvex_workflow::mutation::MutationExecution;
use rusqlite::Connection;
use serde_json::Value;

use crate::error::McpError;
use crate::runtime::change_tracking::{log_change, LogChangeParams};

/// Adapt the workflow-layer `load_current_focus_enriched` return into
/// the surface's `McpError` for use in the pre/post-snapshot calls.
pub(super) fn load_enriched_focus(
    conn: &Connection,
    date: &str,
) -> Result<Option<Value>, McpError> {
    load_current_focus_enriched(conn, date).map_err(McpError::from)
}

pub(super) fn log_clear_current_focus_audit(
    conn: &Connection,
    execution: &MutationExecution,
) -> Result<(), McpError> {
    if execution
        .output
        .after
        .get("cleared")
        .and_then(Value::as_bool)
        != Some(true)
    {
        return Ok(());
    }
    let date = execution
        .output
        .after
        .get("date")
        .and_then(Value::as_str)
        .ok_or_else(|| {
            McpError::Internal(
                "Mutation contract: clear_current_focus output carries date".to_string(),
            )
        })?;
    let before = execution.before.clone().unwrap_or(Value::Null);
    let mut tombstones: HashMap<String, Value> = HashMap::with_capacity(1);
    tombstones.insert(date.to_string(), before.clone());
    log_change(
        conn,
        LogChangeParams::new(
            OP_DELETE,
            ENTITY_CURRENT_FOCUS,
            "clear_current_focus",
            execution.output.summary.clone(),
        )
        .with_entity_id(date.to_string())
        .with_before(before),
        Some(&tombstones),
    )
}

pub(super) fn log_remove_from_current_focus_audit(
    conn: &Connection,
    execution: &MutationExecution,
) -> Result<(), McpError> {
    let date = execution
        .output
        .after
        .get("date")
        .and_then(Value::as_str)
        .ok_or_else(|| {
            McpError::Internal(
                "Mutation contract: remove_from_current_focus output carries date".to_string(),
            )
        })?;
    if execution
        .output
        .after
        .get("plan_cleared")
        .and_then(Value::as_bool)
        == Some(true)
    {
        let before = execution.before.clone().unwrap_or(Value::Null);
        let mut tombstones: HashMap<String, Value> = HashMap::with_capacity(1);
        tombstones.insert(date.to_string(), before.clone());
        return log_change(
            conn,
            LogChangeParams::new(
                OP_DELETE,
                ENTITY_CURRENT_FOCUS,
                "remove_from_current_focus",
                execution.output.summary.clone(),
            )
            .with_entity_id(date.to_string())
            .with_before(before),
            Some(&tombstones),
        );
    }

    log_change(
        conn,
        LogChangeParams::new(
            "update",
            ENTITY_CURRENT_FOCUS,
            "remove_from_current_focus",
            execution.output.summary.clone(),
        )
        .with_entity_id(date.to_string())
        .with_before_opt(execution.before.clone())
        .with_after(execution.output.after.clone()),
        None,
    )
}
