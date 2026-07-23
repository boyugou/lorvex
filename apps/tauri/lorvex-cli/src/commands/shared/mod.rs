//! Shared envelope helpers for CLI command output.
//!
//! every mutating CLI command must emit a
//! canonical JSON envelope of the shape
//!
//! ```json
//! { "action": "<verb>", "db_path": "<path>", ...domain fields }
//! ```
//!
//! so a downstream `jq` consumer can discriminate by `.action` and
//! correlate output to the DB it came from without traversing
//! per-domain shapes. Action verbs use dotted namespacing
//! (`task.update`, `list.create`, `focus.set`, ...) so siblings of the
//! same domain stay grouped.
//!
//! `mutation_envelope` takes a JSON object payload (the existing
//! per-command body) and prepends `action` + `db_path` to it.
//!
//! the helper now accepts the payload as a
//! `serde_json::Map<String, Value>` rather than a `serde_json::Value`.
//! the implementation panicked on any other variant. The panic was a
//! load-bearing programmer-error gate but was not type-enforced —
//! callers had to remember to wrap their `json!({...})` literals in
//! object form, and a regression that produced a non-object would
//! crash the CLI in production. The typed signature pushes the
//! object-vs-not check to the compiler and removes the panic arm
//! entirely.

use std::path::Path;

use lorvex_store::repositories::task::read;
use rusqlite::Connection;
use serde_json::{json, Map, Value};

pub(crate) mod effects;
pub(crate) mod idempotency;
#[cfg(test)]
pub(crate) mod test_support;

pub(crate) use effects::{
    anchored_timezone_name_for_conn, bare_outbox_ctx, ensure_task_exists,
    execute_cli_entity_mutation_map_store_error, execute_cli_mutation_with_finalizer,
    log_cli_changelog_many_with_state, log_cli_changelog_with_state, today_naivedate_for_conn,
    today_ymd_for_conn, validate_calendar_date, CliChangelogParams, CliMultiChangelogParams,
};

/// Validate that an optional `&[String]` patch slice does not exceed
/// `max_count` entries, surfacing the cap and the offending field
/// name in the diagnostic. Shared across tag and dependency patch
/// validators so the message shape stays byte-identical.
pub(crate) fn validate_slice_max_len(
    items: Option<&[String]>,
    field: &str,
    max_count: usize,
) -> Result<(), crate::error::CliError> {
    if let Some(items) = items {
        if items.len() > max_count {
            return Err(crate::error::CliError::Validation(format!(
                "{field} exceeds maximum count ({} items, limit {max_count})",
                items.len()
            )));
        }
    }
    Ok(())
}

pub(crate) fn load_task_row(
    conn: &Connection,
    task_id: &lorvex_domain::TaskId,
) -> Result<read::TaskRow, crate::error::CliError> {
    read::get_task(conn, task_id)?.ok_or_else(|| {
        crate::error::CliError::NotFound(format!("task '{}' not found", task_id.as_str()))
            as crate::error::CliError
    })
}

/// Build the canonical CLI mutation envelope.
///
/// `payload` is taken by-value as a `serde_json::Map`. The returned
/// value is a fresh `Object` containing every key from `payload` plus
/// `action` and `db_path` set to the provided values. Any existing
/// `action` / `db_path` keys in the payload are overwritten — callers
/// should not pre-populate them. The serialized key order is
/// alphabetic (BTreeMap-backed `serde_json::Map`) and not part of the
/// public contract.
fn mutation_envelope(action: &str, db_path: &Path, payload: Map<String, Value>) -> Value {
    let mut obj = payload;
    let mut envelope = serde_json::Map::with_capacity(obj.len() + 2);
    envelope.insert("action".to_string(), json!(action));
    envelope.insert("db_path".to_string(), json!(db_path.display().to_string()));
    // Drop any caller-supplied `action` / `db_path` so the envelope
    // stays canonical even if a payload accidentally carried them.
    obj.remove("action");
    obj.remove("db_path");
    for (key, value) in obj {
        envelope.insert(key, value);
    }
    Value::Object(envelope)
}

/// Convenience: render `mutation_envelope` to the pretty-printed JSON
/// string the CLI's `--format json` arm returns.
///
/// Accepts a `serde_json::Value` for caller ergonomics (most call
/// sites build their payload via `json!({...})`) and validates at the
/// boundary that the value is an object — non-object inputs return a
/// typed `CliError` instead of panicking.
pub(crate) fn render_mutation_envelope(
    action: &str,
    db_path: &Path,
    payload: Value,
) -> Result<String, crate::error::CliError> {
    render_envelope("render_mutation_envelope", action, db_path, payload)
}

/// #3033-M6: query-side companion to `render_mutation_envelope`.
///
/// Read renders (sync status, pending outbox listing, ai_changelog
/// readout) hand-rolled `serde_json::to_string_pretty(&json!({
/// "db_path": ..., ... }))` with bespoke key sets per surface. A future
/// envelope-format bump (e.g. adding a `cli_version` discriminator)
/// would silently skip them. Route every read render through the same
/// `mutation_envelope` builder so the wire shape `{action, db_path,
/// ...payload}` stays universal across query and mutation surfaces;
/// query verbs use a `query.<domain>` namespace so a downstream
/// consumer can still distinguish read vs. write by the leading
/// segment of `.action`.
pub(crate) fn render_query_envelope(
    action: &str,
    db_path: &Path,
    payload: Value,
) -> Result<String, crate::error::CliError> {
    render_envelope("render_query_envelope", action, db_path, payload)
}

fn render_envelope(
    fn_name: &'static str,
    action: &str,
    db_path: &Path,
    payload: Value,
) -> Result<String, crate::error::CliError> {
    let map = match payload {
        Value::Object(map) => map,
        other => {
            return Err(crate::error::CliError::Internal(format!(
                "{fn_name} requires a JSON object payload, got {}",
                json_value_kind(&other)
            )));
        }
    };
    Ok(serde_json::to_string_pretty(&mutation_envelope(
        action, db_path, map,
    ))?)
}

const fn json_value_kind(value: &Value) -> &'static str {
    match value {
        Value::Null => "null",
        Value::Bool(_) => "bool",
        Value::Number(_) => "number",
        Value::String(_) => "string",
        Value::Array(_) => "array",
        Value::Object(_) => "object",
    }
}

#[cfg(test)]
mod tests;
