//! Diagnostics commands that surface sync-related debugging state:
//! - `get_sync_conflict_log` exposes the local `sync_conflict_log` table
//!   (LWW / tag-merge / FK-stalled / reseed-required outcomes) so a user
//!   can see why a record "changed mysteriously" after a sync round.
//! - `get_diagnostics_device_ids` powers the "device scope" filter in
//!   Settings → Diagnostics from changelog source devices plus conflict
//!   loser devices.
//!
//! Surfaces `sync_conflict_log` to the Diagnostics panel so users
//! debugging sync issues don't need to open the DB with `sqlite3` to
//! see this information.

use crate::db::get_read_conn;
use crate::error::{AppError, AppResult};
use lorvex_domain::naming::EntityKind;
use lorvex_store::repositories::ai_changelog_actor_filter::ai_changelog_assistant_actor_filter_sql;
use rusqlite::params;
use serde::{Deserialize, Serialize};

use super::super::shared::clamp_limit;

const MAX_CONFLICT_LOG_LIMIT: i64 = 1_000;
const DEFAULT_CONFLICT_LOG_LIMIT: i64 = 200;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct SyncConflictLogEntry {
    pub id: i64,
    pub kind: String,
    pub entity_type: EntityKind,
    pub entity_id: String,
    pub local_version: String,
    pub remote_version: String,
    pub loser_device_id: String,
    pub occurred_at: String,
    pub details: Option<String>,
}

/// Read the `sync_conflict_log` table. Rows are ordered newest-first.
/// `limit` defaults to 200, capped at 1_000. `since_iso`, if provided,
/// filters to rows with `resolved_at >= since_iso` (lexicographic,
/// which is correct because both values are RFC3339 UTC). Invalid
/// `since_iso` is silently ignored — a filter only narrows, never
/// widens, the result set.
pub(crate) fn read_sync_conflict_log(
    conn: &rusqlite::Connection,
    limit: Option<i64>,
    since_iso: Option<&str>,
    source_device_id: Option<&str>,
) -> AppResult<Vec<SyncConflictLogEntry>> {
    let lim = clamp_limit(limit, DEFAULT_CONFLICT_LOG_LIMIT, 1, MAX_CONFLICT_LOG_LIMIT);
    let since_trimmed = since_iso.map(str::trim).filter(|s| !s.is_empty());
    let device_trimmed = source_device_id.map(str::trim).filter(|s| !s.is_empty());

    const BASE_SELECT: &str = "SELECT id, entity_type, entity_id, winner_version, loser_version,
                                      loser_device_id, loser_payload, resolved_at, resolution_type
                               FROM sync_conflict_log";

    match (since_trimmed, device_trimmed) {
        (Some(since), Some(device)) => {
            let sql = format!(
                "{BASE_SELECT} WHERE resolved_at >= ?1 AND loser_device_id = ?2 ORDER BY id DESC LIMIT ?3"
            );
            let mut stmt = conn.prepare_cached(&sql).map_err(AppError::from)?;
            let rows: Vec<SyncConflictLogEntry> = stmt
                .query_map(params![since, device, lim], row_to_conflict_entry)
                .map_err(AppError::from)?
                .collect::<Result<_, _>>()
                .map_err(AppError::from)?;
            Ok(rows)
        }
        (Some(since), None) => {
            let sql = format!("{BASE_SELECT} WHERE resolved_at >= ?1 ORDER BY id DESC LIMIT ?2");
            let mut stmt = conn.prepare_cached(&sql).map_err(AppError::from)?;
            let rows: Vec<SyncConflictLogEntry> = stmt
                .query_map(params![since, lim], row_to_conflict_entry)
                .map_err(AppError::from)?
                .collect::<Result<_, _>>()
                .map_err(AppError::from)?;
            Ok(rows)
        }
        (None, Some(device)) => {
            let sql = format!("{BASE_SELECT} WHERE loser_device_id = ?1 ORDER BY id DESC LIMIT ?2");
            let mut stmt = conn.prepare_cached(&sql).map_err(AppError::from)?;
            let rows: Vec<SyncConflictLogEntry> = stmt
                .query_map(params![device, lim], row_to_conflict_entry)
                .map_err(AppError::from)?
                .collect::<Result<_, _>>()
                .map_err(AppError::from)?;
            Ok(rows)
        }
        (None, None) => {
            let sql = format!("{BASE_SELECT} ORDER BY id DESC LIMIT ?1");
            let mut stmt = conn.prepare_cached(&sql).map_err(AppError::from)?;
            let rows: Vec<SyncConflictLogEntry> = stmt
                .query_map(params![lim], row_to_conflict_entry)
                .map_err(AppError::from)?
                .collect::<Result<_, _>>()
                .map_err(AppError::from)?;
            Ok(rows)
        }
    }
}

fn row_to_conflict_entry(row: &rusqlite::Row<'_>) -> rusqlite::Result<SyncConflictLogEntry> {
    let entity_type_raw: String = row.get(1)?;
    let entity_type = EntityKind::parse(&entity_type_raw).ok_or_else(|| {
        rusqlite::Error::FromSqlConversionFailure(
            1,
            rusqlite::types::Type::Text,
            Box::new(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!("invalid sync_conflict_log.entity_type column value: {entity_type_raw}"),
            )),
        )
    })?;
    Ok(SyncConflictLogEntry {
        id: row.get(0)?,
        entity_type,
        entity_id: row.get(2)?,
        local_version: row.get(3)?,
        remote_version: row.get(4)?,
        loser_device_id: row.get(5)?,
        details: row.get(6)?,
        occurred_at: row.get(7)?,
        kind: row.get(8)?,
    })
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn get_sync_conflict_log(
    limit: Option<i64>,
    since_iso: Option<String>,
    source_device_id: Option<String>,
) -> Result<Vec<SyncConflictLogEntry>, String> {
    let conn = get_read_conn()?;
    read_sync_conflict_log(
        &conn,
        limit,
        since_iso.as_deref(),
        source_device_id.as_deref(),
    )
    .map_err(String::from)
}

/// Return distinct device IDs observed in diagnostics rows, ordered by
/// most-recent activity first. Powers the "device scope" dropdown in
/// Settings -> Diagnostics. `error_logs` does not carry a device column,
/// so device-scoped error logs remain intentionally hidden in the UI.
pub(crate) fn read_diagnostics_device_ids(conn: &rusqlite::Connection) -> AppResult<Vec<String>> {
    let actor_filter = ai_changelog_assistant_actor_filter_sql();
    let sql = format!(
        "SELECT device_id, MAX(last_seen) AS last_seen
         FROM (
             SELECT TRIM(source_device_id) AS device_id, MAX(timestamp) AS last_seen
             FROM ai_changelog
             WHERE source_device_id IS NOT NULL
               AND TRIM(source_device_id) != ''
               AND {actor_filter}
             GROUP BY TRIM(source_device_id)

             UNION ALL

             SELECT TRIM(loser_device_id) AS device_id, MAX(resolved_at) AS last_seen
             FROM sync_conflict_log
             WHERE TRIM(loser_device_id) != ''
             GROUP BY TRIM(loser_device_id)
         )
         GROUP BY device_id
         ORDER BY last_seen DESC
         LIMIT 50"
    );
    let mut stmt = conn.prepare(&sql).map_err(AppError::from)?;
    let rows: Vec<String> = stmt
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(AppError::from)?
        .collect::<Result<_, _>>()
        .map_err(AppError::from)?;
    Ok(rows)
}

#[tauri::command]
pub fn get_diagnostics_device_ids() -> Result<Vec<String>, String> {
    let conn = get_read_conn()?;
    read_diagnostics_device_ids(&conn).map_err(String::from)
}
