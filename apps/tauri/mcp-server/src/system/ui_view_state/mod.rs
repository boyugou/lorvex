//! MCP tool: `get_ui_view_state` — exposes the Tauri UI's presentation state
//! (active view, selected task, filters, focus mode) to the assistant so it
//! can act on what the user is actually looking at instead of always
//! reasoning about the global DB.
//!
//! The frontend writes a JSON snapshot into `device_state`
//! under the key [`UI_VIEW_STATE_KEY`] on every navigation / filter change
//! (debounced at the frontend). This module is the READ-ONLY counterpart
//! exposed to the MCP client — the assistant cannot mutate UI state here.
//!
//! ### Staleness
//!
//! The frontend stamps every snapshot with `last_updated_at` (RFC3339). If
//! the snapshot is older than [`STALE_THRESHOLD_SECS`] seconds, we return a
//! bare envelope with `stale: true` and no fields. The assistant shouldn't
//! act on a day-old filter. Missing-key (never written) is reported as
//! `available: false`.
//!
//! ### Privacy
//!
//! View state is intentionally local-only. Nothing in this module writes
//! to the outbox; `device_state` is excluded from sync by design.

use crate::error::McpError;
use chrono::{DateTime, Utc};
use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{json, Value};

/// `device_state` key where the frontend persists the UI view-state snapshot.
pub(crate) const UI_VIEW_STATE_KEY: &str = "ui_view_state";

/// Snapshots older than this are treated as "unknown" — the user likely
/// closed the app or switched context long ago, and the assistant should
/// not make decisions based on stale view state.
pub(crate) const STALE_THRESHOLD_SECS: i64 = 10 * 60;

/// Top-level keys the tool surfaces. Kept in sync with the frontend writer
/// (`app/src/app-shell/main-window/useUiViewStatePersistence.ts`) so the
/// snapshot round-trips cleanly.
const KNOWN_FIELDS: &[&str] = &[
    "active_view",
    "selected_task_id",
    "search_query",
    "list_filter_id",
    "tag_filters",
    "priority_filter",
    "focus_mode_active",
    "focus_mode_task_id",
];

/// Read the UI view-state snapshot and return a structured JSON envelope.
///
/// The response shape is always one of:
///
/// - `{ "available": false, "reason": "never_written" }` — no row yet.
/// - `{ "available": false, "reason": "stale", "age_seconds": N, "last_updated_at": "..." }`
///   — snapshot exists but is older than [`STALE_THRESHOLD_SECS`].
/// - `{ "available": true, "last_updated_at": "...", "age_seconds": N,
///      "active_view": ..., "selected_task_id": ..., ... }` — fresh.
///
/// Unknown fields in the stored blob are silently dropped so the contract
/// remains stable even if the frontend writes extra metadata for its own
/// use.
pub(crate) fn get_ui_view_state(conn: &Connection) -> Result<String, McpError> {
    let now = Utc::now();
    get_ui_view_state_at(conn, now)
}

/// Testable variant that takes an injected "now" instant so staleness can
/// be exercised deterministically.
pub(crate) fn get_ui_view_state_at(
    conn: &Connection,
    now: DateTime<Utc>,
) -> Result<String, McpError> {
    let row: Option<String> = conn
        .query_row(
            "SELECT value FROM device_state WHERE key = ?1",
            params![UI_VIEW_STATE_KEY],
            |r| r.get(0),
        )
        .optional()?;

    let Some(raw) = row else {
        return Ok(serde_json::to_string(&json!({
            "available": false,
            "reason": "never_written",
        }))?);
    };

    // Stored blob is canonical JSON (see `set_device_state`), so any parse
    // error here indicates a corrupt row — surface it rather than hide.
    let blob: Value = serde_json::from_str(&raw)
        .map_err(|e| McpError::Internal(format!("ui_view_state row is not valid JSON: {e}")))?;

    let Some(obj) = blob.as_object() else {
        return Err(McpError::Internal(
            "ui_view_state row is not a JSON object".to_string(),
        ));
    };

    // Read last_updated_at; if absent or unparseable, treat as stale so
    // the assistant doesn't act on a snapshot it cannot date.
    let last_updated_str = obj
        .get("last_updated_at")
        .and_then(Value::as_str)
        .unwrap_or("");
    let last_updated = DateTime::parse_from_rfc3339(last_updated_str)
        .ok()
        .map(|dt| dt.with_timezone(&Utc));

    let Some(last_updated) = last_updated else {
        return Ok(serde_json::to_string(&json!({
            "available": false,
            "reason": "stale",
            "detail": "missing or unparseable last_updated_at",
        }))?);
    };

    let age_seconds = (now - last_updated).num_seconds();

    if age_seconds > STALE_THRESHOLD_SECS {
        return Ok(serde_json::to_string(&json!({
            "available": false,
            "reason": "stale",
            "age_seconds": age_seconds,
            "last_updated_at": lorvex_domain::format_sync_timestamp(last_updated),
        }))?);
    }

    // Project only the known fields into the response so forward-compat
    // additions by the frontend don't leak into the MCP contract until we
    // explicitly decide to surface them.
    let mut out = serde_json::Map::new();
    out.insert("available".to_string(), Value::Bool(true));
    out.insert(
        "last_updated_at".to_string(),
        Value::String(lorvex_domain::format_sync_timestamp(last_updated)),
    );
    out.insert(
        "age_seconds".to_string(),
        Value::Number(serde_json::Number::from(age_seconds)),
    );
    for field in KNOWN_FIELDS {
        let value = obj.get(*field).cloned().unwrap_or(Value::Null);
        out.insert((*field).to_string(), value);
    }

    Ok(serde_json::to_string(&Value::Object(out))?)
}

#[cfg(test)]
mod tests;
