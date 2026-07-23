//! CLI command handlers that mirror the remaining MCP
//! workflow / aggregation / structured-write tool surface. These thin
//! wrappers dispatch into [`lorvex_mcp_server::public_api`] so the CLI
//! and the MCP transport share one canonical implementation per tool —
//! same audit/sync/changelog semantics, no duplicated DB plumbing.
//!
//! The wrappers here own only the CLI concerns:
//!
//! * args → JSON value translation that the public_api expects;
//! * connection acquisition + DB-path resolution;
//! * canonical mutation envelope rendering for `--format json`.
//!
//! Read-path helpers do not pass through `render_mutation_envelope`
//! because they are queries, not mutations — they surface the same
//! envelope-less JSON shape an MCP client receives, with `db_path` and
//! `action` prepended for downstream `jq` consumers (parity with
//! `error_logs` / `changelog`).
//!
//! H6 decision (control_app_ui / get_ui_view_state): see the comment
//! at the head of `cli/args/mod.rs` — those tools IPC into a running
//! Tauri app and are intentionally NOT exposed here.
//!
//! Submodules group the wrappers by domain so each file stays focused:
//! - [`query`] — read-path tools (overview, session_context, guide,
//!   recent_logs, analyze_task_patterns, habit_completions).
//! - [`checklist`] — task checklist add/update/toggle/remove/reorder.
//! - [`tasks`] — per-verb structured task writes:
//!   - `create` (`task.create`)
//!   - `batch_create` (`task.batch_create`)
//!   - `batch_update` (`task.batch_update`)
//!   - `batch_cancel` (`task.batch_cancel_in_list`)
//!
//!   These verbs share `idempotency`, `dry_run`, and `shared_flush`
//!   sibling helpers consumed by every variant.
//! - [`recurrence`] — set_recurrence with its dedicated input struct.
//! - [`list_ops`] — list-level mutations (reorganize, permanent delete).
//!
//! The shared helpers (`render_query_response`,
//! `render_mutation_response`, `parse_payload`, the public_api error
//! decoder) live in this file because every submodule consumes them.

use serde::Deserialize;
use serde_json::{json, Value};
use std::path::Path;

use crate::cli::OutputFormat;
use crate::commands::shared::render_mutation_envelope;
use crate::error::CliError;

mod checklist;
mod list_ops;
mod query;
mod recurrence;
mod tasks;

pub(crate) use checklist::{
    run_checklist_add, run_checklist_remove, run_checklist_reorder, run_checklist_toggle,
    run_checklist_update,
};
pub(crate) use list_ops::{run_permanent_delete, run_reorganize_list};
pub(crate) use query::{
    run_analyze, run_guide, run_habit_completions, run_overview, run_recent_logs,
    run_session_context,
};
pub(crate) use recurrence::{run_set_recurrence, SetRecurrenceInputs};
pub(crate) use tasks::{
    run_batch_cancel_in_list, run_batch_create, run_batch_update, run_task_create, TaskCreateInputs,
};

/// Render a canonical query response — the public_api returns a JSON
/// string already; we pretty-print it for `--format json` and prepend
/// `db_path` + `action` so callers can route by tool. Text mode emits
/// the JSON unmodified (matches the MCP transport's verbatim shape).
fn render_query_response(
    action: &str,
    db_path: &Path,
    raw_json: String,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => Ok(raw_json),
        OutputFormat::Json => {
            // The handler emits valid JSON, so a parse failure is a
            // bug and should surface as an internal error.
            let value: Value = serde_json::from_str(&raw_json).map_err(|e| {
                CliError::Internal(format!("public_api returned malformed JSON: {e}"))
            })?;
            let mut wrapper = serde_json::Map::with_capacity(3);
            wrapper.insert("action".to_string(), json!(action));
            wrapper.insert("db_path".to_string(), json!(db_path.display().to_string()));
            wrapper.insert("payload".to_string(), value);
            Ok(serde_json::to_string_pretty(&Value::Object(wrapper))?)
        }
    }
}

#[derive(Debug, Deserialize)]
struct PublicApiErrorPayload {
    kind: String,
    message: String,
    #[serde(default)]
    retryable: bool,
    docs_hint: Option<String>,
    entity_id: Option<String>,
}

fn is_known_mcp_error_kind(kind: &str) -> bool {
    matches!(
        kind,
        "validation"
            | "not_found"
            | "db_busy"
            | "sync_conflict"
            | "serialization"
            | "rate_limited"
            | "internal"
    )
}

const fn has_mcp_payload_metadata(payload: &PublicApiErrorPayload) -> bool {
    payload.retryable || payload.docs_hint.is_some() || payload.entity_id.is_some()
}

fn structured_mcp_error(payload: PublicApiErrorPayload) -> CliError {
    if !is_known_mcp_error_kind(&payload.kind) {
        return CliError::Internal(payload.message);
    }
    if !has_mcp_payload_metadata(&payload) {
        match payload.kind.as_str() {
            "validation" => return CliError::Validation(payload.message),
            "not_found" => return CliError::NotFound(payload.message),
            "sync_conflict" => return CliError::Conflict(payload.message),
            "internal" => return CliError::Internal(payload.message),
            _ => {}
        }
    }
    CliError::McpTool {
        kind: payload.kind,
        message: payload.message,
        retryable: payload.retryable,
        docs_hint: payload.docs_hint,
        entity_id: payload.entity_id,
    }
}

/// Convert a public_api `Result<String, String>` into `CliError`. Modern
/// MCP handlers emit a structured JSON object inside the string error
/// boundary; parse that first so retryability, docs hints, and entity ids
/// survive the CLI mirror. The prose fallback is retained only for legacy
/// literals such as client cancellation.
fn map_public_api_error(message: String) -> CliError {
    if let Ok(payload) = serde_json::from_str::<PublicApiErrorPayload>(&message) {
        return structured_mcp_error(payload);
    }
    if message.starts_with("invalid args:") || message.contains("Validation") {
        CliError::Validation(message)
    } else if message.contains("not found") {
        CliError::NotFound(message)
    } else if message.contains("conflict") || message.contains("concurrent") {
        CliError::Conflict(message)
    } else {
        CliError::Internal(message)
    }
}

/// The mutating wrappers in this module open-coded
/// the same match: `Text` returns the raw `public_api` string verbatim,
/// and `Json` parses the string, hands the parsed `Value` to a tiny
/// closure that wraps it in the envelope payload (`{"task": ...}`,
/// `{"result": ..., "dry_run": ...}`, …), and emits the canonical
/// mutation envelope. Hoisting that match into one helper keeps the
/// payload-shape decision (the closure body) at every call site while
/// removing the `match` / `parse_payload` / `render_mutation_envelope`
/// boilerplate that drifted as new mutations were added (see #2976).
fn render_mutation_response<F>(
    action: &str,
    db_path: &Path,
    raw: String,
    format: OutputFormat,
    payload_wrap: F,
) -> Result<String, CliError>
where
    F: FnOnce(Value) -> Value,
{
    match format {
        OutputFormat::Text => Ok(raw),
        OutputFormat::Json => {
            let payload = parse_payload(&raw)?;
            render_mutation_envelope(action, db_path, payload_wrap(payload))
        }
    }
}

/// Helper: parse a JSON string returned by the public_api into a Value
/// for envelope rendering.
fn parse_payload(raw: &str) -> Result<Value, CliError> {
    serde_json::from_str(raw)
        .map_err(|e| CliError::Internal(format!("public_api returned malformed JSON: {e}")))
}

#[cfg(test)]
mod tests;
