use crate::db::{get_conn, get_read_conn};
use crate::error::{AppError, AppResult};
use crate::event_bus;
use serde::{Deserialize, Serialize};

use super::super::shared::{
    ai_changelog_where_clause, ai_changelog_where_clause_for_alias, clamp_limit, rows_from_query,
    MAX_CHANGELOG_LIMIT,
};
use super::undo_token_cache;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ClearChangelogResult {
    pub deleted: usize,
}

/// Counts of rows reaped by [`run_data_retention_cleanup`]. Mirrors
/// [`lorvex_sync::retention_sweep::RetentionSweepOutcome`] at the IPC
/// boundary so the renderer's TypeScript shape doesn't pick up the
/// crate-internal type.
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct DataRetentionCleanupResult {
    pub changelog_deleted: u64,
    pub error_logs_deleted: u64,
    #[serde(default)]
    pub memory_revisions_deleted: u64,
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn get_changelog(
    limit: Option<i64>,
    since_iso: Option<String>,
    source_device_id: Option<String>,
) -> Result<Vec<serde_json::Value>, String> {
    let conn = get_read_conn()?;
    let lim = clamp_limit(limit, 30, 1, MAX_CHANGELOG_LIMIT);
    read_ai_changelog_entries_filtered(
        &conn,
        lim,
        since_iso.as_deref(),
        source_device_id.as_deref(),
        None,
    )
    .map_err(String::from)
}

/// Per-task history view (#2513). Powers the collapsible History
/// section inside the task-detail panel so a power user can see
/// "every change to task X over its lifetime" without hunting through
/// the global Activity Log. Delegates row rendering to the same
/// `read_ai_changelog_entries_filtered` path so all provenance/undo
/// fields the global view surfaces also appear inline — the UI reuses
/// the ChangelogEntry row shape.
#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn get_task_history(
    task_id: String,
    limit: Option<i64>,
) -> Result<Vec<serde_json::Value>, String> {
    let trimmed = task_id.trim();
    if trimmed.is_empty() {
        return Err("task_id is required".to_string());
    }
    let conn = get_read_conn()?;
    let lim = clamp_limit(limit, 20, 1, MAX_CHANGELOG_LIMIT);
    read_ai_changelog_entries_filtered(&conn, lim, None, None, Some(trimmed)).map_err(String::from)
}

#[tauri::command]
pub fn clear_changelog() -> Result<ClearChangelogResult, String> {
    let conn = get_conn()?;
    let actor_filter = ai_changelog_where_clause();
    let deleted = conn
        .execute(
            &format!("DELETE FROM ai_changelog WHERE {actor_filter}"),
            [],
        )
        .map_err(AppError::from)?;
    if deleted > 0 {
        event_bus::emit_data_changed(event_bus::Entity::Changelog);
    }
    Ok(ClearChangelogResult { deleted })
}

#[tauri::command]
pub fn run_data_retention_cleanup() -> Result<DataRetentionCleanupResult, String> {
    let conn = get_conn()?;
    // The explicit `.map_err(String::from)` is redundant — `?` already
    // converts `AppError` to `String` via `From<AppError> for String`
    // (see `error/boundary.rs:4`). Sibling `clear_changelog` above
    // uses the same implicit `?`-driven conversion path.
    let result = run_data_retention_cleanup_with_conn(&conn)?;
    if result.changelog_deleted > 0 {
        event_bus::emit_data_changed(event_bus::Entity::Changelog);
    }
    Ok(result)
}

/// Core retention cleanup used by the `run_data_retention_cleanup` IPC
/// command and from test harnesses that need a seam without a global
/// connection pool. Delegates the entire sweep to
/// [`lorvex_sync::retention_sweep::run_periodic_retention_sweep`] so the
/// MCP server, the CLI's long-running surfaces, and the desktop app all
/// reap the same tables on the same schedule. Returns the row counts
/// deleted but does NOT emit `data-changed` events (the command wrapper
/// handles that).
pub(crate) fn run_data_retention_cleanup_with_conn(
    conn: &rusqlite::Connection,
) -> AppResult<DataRetentionCleanupResult> {
    let outcome =
        lorvex_sync::retention_sweep::run_periodic_retention_sweep(conn).map_err(AppError::from)?;
    // Stamp the watermark so headless processes (MCP / tui-watch) sharing
    // this DB don't double up the next time they boot inside the
    // `MIN_RETENTION_SWEEP_INTERVAL_HOURS` window.
    if let Err(err) = lorvex_sync::retention_sweep::record_retention_sweep_completed(conn) {
        record_retention_warning(
            conn,
            "diagnostics.retention.watermark_set_failed",
            format!("could not stamp retention sweep watermark: {err}"),
        );
    }
    Ok(DataRetentionCleanupResult {
        changelog_deleted: outcome.changelog_deleted,
        error_logs_deleted: outcome.error_logs_deleted,
        memory_revisions_deleted: outcome.memory_revisions_deleted,
    })
}

fn record_retention_warning(conn: &rusqlite::Connection, source: &str, message: impl AsRef<str>) {
    let _ = super::error_logs::append_error_log_internal(
        conn,
        source,
        message.as_ref(),
        None,
        Some("warn".to_string()),
    );
}

/// JSON-encoded `preferences` row reader for retention day counts.
/// Re-export of [`lorvex_sync::retention_sweep::read_retention_days`]
/// mapped into the Tauri-side `AppResult` shape. Single source of
/// truth lives in `lorvex-sync`.
pub(crate) fn read_retention_days(
    conn: &rusqlite::Connection,
    key: &str,
) -> AppResult<Option<i64>> {
    lorvex_sync::retention_sweep::read_retention_days(conn, key).map_err(AppError::from)
}

/// Read the user's ai_changelog retention window (in days) from
/// preferences.
///
/// Returns:
/// - `Ok(None)` when the preference is unset — the Settings UI "Forever"
///   option, meaning keep all entries and never clean up.
/// - `Ok(Some(days))` for any positive-integer day count (the Settings
///   UI offers 7/14/30/60/90/180/365, but any positive integer is
///   accepted for forward compatibility).
/// - `Err(Validation)` if the stored value is malformed.
///
/// Shared reader for the entire Tauri side — sync GC runtimes, the
/// `run_data_retention_cleanup` command, and any other caller that
/// needs the policy. Routing every consumer through this reader
/// (instead of a per-caller bucket-enum that only accepts a fixed
/// `7/14/30/90` set) lets every UI-selectable value round-trip
/// cleanly so picking `60/180/365` doesn't crash MCP mutations.
pub(crate) fn read_changelog_retention_days(conn: &rusqlite::Connection) -> AppResult<Option<i64>> {
    read_retention_days(
        conn,
        lorvex_domain::preference_keys::PREF_AI_CHANGELOG_RETENTION_POLICY,
    )
}

#[cfg(test)]
pub(crate) fn read_ai_changelog_entries(
    conn: &rusqlite::Connection,
    limit: i64,
) -> AppResult<Vec<serde_json::Value>> {
    read_ai_changelog_entries_filtered(conn, limit, None, None, None)
}

/// Test-only seam for #2513: exercises the `entity_id` filter path of
/// `read_ai_changelog_entries_filtered` without needing the full IPC
/// layer / global DB pool.
#[cfg(test)]
pub(crate) fn read_ai_changelog_entries_for_entity(
    conn: &rusqlite::Connection,
    limit: i64,
    entity_id: &str,
) -> AppResult<Vec<serde_json::Value>> {
    read_ai_changelog_entries_filtered(conn, limit, None, None, Some(entity_id))
}

/// Filtered variant that powers the `get_changelog` IPC with the
/// Diagnostics panel's time-window + device-scope controls (#2138),
/// and also surfaces the short undo window (#2547) via the in-process
/// undo-token cache. `since_iso` filters by `timestamp >= since_iso`
/// (RFC3339, lexicographic). `source_device_id`, when present and
/// non-empty, restricts to rows tagged with that device. `entity_id`,
/// when present and non-empty, restricts to rows mutating that
/// specific entity (#2513: powers the per-task History section inside
/// TaskDetail). Any filter being `None`/empty is a no-op.
pub(crate) fn read_ai_changelog_entries_filtered(
    conn: &rusqlite::Connection,
    limit: i64,
    since_iso: Option<&str>,
    source_device_id: Option<&str>,
    entity_id: Option<&str>,
) -> AppResult<Vec<serde_json::Value>> {
    let actor_filter = ai_changelog_where_clause_for_alias("c");
    let mut sql = format!(
        "SELECT c.id, c.timestamp, c.operation, c.entity_type, c.entity_id, \
                c.summary, c.mcp_tool, c.source_device_id, \
                c.before_json, c.after_json, \
                c.undo_token AS persisted_undo_token \
         FROM ai_changelog c \
         WHERE {actor_filter}"
    );
    let mut bindings: Vec<rusqlite::types::Value> = Vec::new();
    let since_trimmed = since_iso.map(str::trim).filter(|s| !s.is_empty());
    if let Some(since) = since_trimmed {
        sql.push_str(" AND c.timestamp >= ?");
        sql.push_str(&(bindings.len() + 1).to_string());
        bindings.push(rusqlite::types::Value::Text(since.to_string()));
    }
    let device_trimmed = source_device_id.map(str::trim).filter(|s| !s.is_empty());
    if let Some(device_id) = device_trimmed {
        sql.push_str(" AND c.source_device_id = ?");
        sql.push_str(&(bindings.len() + 1).to_string());
        bindings.push(rusqlite::types::Value::Text(device_id.to_string()));
    }
    let entity_trimmed = entity_id.map(str::trim).filter(|s| !s.is_empty());
    if let Some(entity) = entity_trimmed {
        sql.push_str(" AND c.entity_id = ?");
        sql.push_str(&(bindings.len() + 1).to_string());
        bindings.push(rusqlite::types::Value::Text(entity.to_string()));
    }
    sql.push_str(" ORDER BY c.timestamp DESC, c.id DESC LIMIT ?");
    sql.push_str(&(bindings.len() + 1).to_string());
    bindings.push(rusqlite::types::Value::Integer(limit));

    rows_from_query(
        conn,
        &sql,
        rusqlite::params_from_iter(bindings.iter()),
        |row| {
            // #2367: MCP-side destructive writes persist their undo
            // token JSON directly in `ai_changelog.undo_token`, so a
            // process restart during the undo window still exposes the
            // Undo button (the MCP server runs in a separate process
            // from the Tauri app — the in-process cache the Tauri-side
            // complete/cancel undo uses cannot cross that boundary).
            // Prefer the persisted column when present; fall back to
            // the in-process cache (keyed by entity id) for
            // Tauri-originated task writes.
            let persisted_undo_token: Option<String> = row.get(10)?;
            let row_entity_id: Option<String> = row.get(4)?;
            let undo_token = persisted_undo_token
                .or_else(|| row_entity_id.as_deref().and_then(undo_token_cache::lookup));
            // #2373: surface the raw before/after JSON strings so the
            // UI can parse and diff them on demand. Null when the
            // writer didn't populate them (create/delete/legacy rows).
            let before_json_raw: Option<String> = row.get(8)?;
            let after_json_raw: Option<String> = row.get(9)?;
            Ok(serde_json::json!({
                "id": row.get::<_, String>(0)?,
                "timestamp": row.get::<_, String>(1)?,
                "operation": row.get::<_, String>(2)?,
                "entity_type": row.get::<_, String>(3)?,
                "entity_id": row.get::<_, Option<String>>(4)?,
                "summary": row.get::<_, String>(5)?,
                "mcp_tool": row.get::<_, Option<String>>(6)?,
                // provenance field so multi-device UI
                // can surface "which device did this". Null for
                // local-only installs.
                "source_device_id": row.get::<_, Option<String>>(7)?,
                // #2373: structured before/after snapshots for update
                // operations. The UI parses these strings client-side
                // to render a field-level diff inside the Activity Log.
                "before_json": before_json_raw,
                "after_json": after_json_raw,
                // non-null when a serialized undo token is available
                // for this row — persisted (MCP writes) or cached
                // in-process while the undo window is open (Tauri
                // task writes). UI renders an Undo button when this
                // is non-null.
                "undo_token": undo_token,
            }))
        },
    )
}

/// Revert a changelog row's underlying mutation by delegating to the
/// existing `undo_task_lifecycle` pipeline.
///
/// Accepts the serialized `UndoToken` JSON that `get_changelog`
/// surfaces on the row. This is a thin wrapper so the Changelog view's
/// Undo affordance flows through the same tested undo machinery used
/// by the success-toast buttons on complete/cancel — no separate
/// reverse-state pipeline.
///
/// Opportunistically drops the cached token for the mutation's task
/// after a successful undo so a stale changelog query that fires
/// between the DB write and the event bus invalidation can't hand the
/// same token out a second time.
#[tauri::command]
pub fn undo_changelog_entry(token: String) -> Result<crate::commands::Task, String> {
    // Best-effort extraction of the task id for cache consumption
    // post-success. Parsing failure is silently tolerated: the undo
    // itself still validates the token fully inside `undo_task_lifecycle`.
    let task_to_consume: Option<String> = serde_json::from_str::<serde_json::Value>(&token)
        .ok()
        .and_then(|v| {
            v.get("task_id")
                .and_then(|g| g.as_str())
                .map(std::string::ToString::to_string)
        })
        .filter(|s| !s.is_empty());

    // The Changelog view has no redo affordance — the row-level Undo
    // button is a one-shot per #2547. Discard the redo token that
    // `undo_task_lifecycle` now emits (#2536) and surface only the
    // restored task to the caller.
    let result = crate::commands::undo_task_lifecycle(token)?;

    if let Some(task_id) = task_to_consume {
        undo_token_cache::consume(&task_id);
    }
    Ok(result.task)
}
