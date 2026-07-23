//! DB-side row collection for the diagnostic bundle: error_logs,
//! ai_changelog, sync_conflict_log, plus the `system_info.json`
//! header. Every reader swallows a "no such table" error so a
//! partially-initialized DB still produces a usable bundle.

use lorvex_domain::naming::EntityKind;
use lorvex_store::repositories::ai_changelog_actor_filter::ai_changelog_assistant_actor_filter_sql;
use rusqlite::params;
use serde::Serialize;

use crate::db::db_path;
use crate::error::{AppError, AppResult};

use super::super::error_logs::ErrorLogEntry;
use super::super::sync_conflicts::SyncConflictLogEntry;
use super::BUNDLE_RETENTION_DAYS;
use super::MAX_CONFLICT_LOG_ROWS;

#[derive(Debug, Serialize)]
pub(super) struct SystemInfo {
    app_version: String,
    mcp_server_version: String,
    schema_version: u32,
    payload_schema_version: u32,
    os: &'static str,
    arch: &'static str,
    family: &'static str,
    generated_at: String,
    retention_days: i64,
    runtime_paths: RuntimePaths,
}

#[derive(Debug, Serialize)]
struct RuntimePaths {
    db_path: String,
}

#[derive(Debug, Serialize)]
pub(super) struct ChangelogBundleRow {
    id: String,
    timestamp: String,
    operation: String,
    entity_type: EntityKind,
    entity_id: Option<String>,
    summary: String,
    mcp_tool: Option<String>,
    source_device_id: Option<String>,
}

/// Cutoff clause fragment shared by the error-log + changelog readers.
/// Built via SQLite's `strftime` so the comparison stays lexicographic
/// against the stored RFC3339-with-milliseconds text.
const fn retention_cutoff_clause() -> &'static str {
    "strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?1)"
}

/// Build the `system_info.json` contents.
pub(super) fn build_system_info(conn: &rusqlite::Connection) -> AppResult<SystemInfo> {
    // PRAGMA user_version is SQLite's "which migration generation is
    // installed" marker. `lorvex-domain::version::SCHEMA_VERSION` is the
    // compile-time constant the code expects; we prefer the PRAGMA so
    // the bundle reflects the actual DB state, not what the app *thinks*
    // it should be — useful when a stale binary is running against a
    // freshly-migrated DB (or vice versa).
    let schema_version: u32 = conn
        .query_row("PRAGMA user_version", [], |row| row.get::<_, i64>(0))
        .map_err(AppError::from)?
        .try_into()
        .unwrap_or(0);

    // pass the runtime paths through
    // `redact_diagnostic_text` before they land in the bundle. The
    // bundle is what users mail to support, so a raw
    // `/Users/<realname>/Library/Application Support/Lorvex/db.sqlite`
    // leaks the macOS account name (and on Windows the AD username).
    // The redactor collapses `/Users/<name>/...` and `C:\Users\<name>\...`
    // to `[~]/...` while preserving everything else the responder
    // needs (drive root, app-relative subpath, file name).
    let db = db_path();
    let raw_db_path = db.to_string_lossy().to_string();

    Ok(SystemInfo {
        app_version: env!("CARGO_PKG_VERSION").to_string(),
        mcp_server_version: env!("CARGO_PKG_VERSION").to_string(),
        schema_version,
        payload_schema_version: lorvex_domain::version::PAYLOAD_SCHEMA_VERSION,
        os: std::env::consts::OS,
        arch: std::env::consts::ARCH,
        family: std::env::consts::FAMILY,
        generated_at: crate::commands::sync_timestamp_now(),
        retention_days: BUNDLE_RETENTION_DAYS,
        runtime_paths: RuntimePaths {
            db_path: lorvex_domain::diagnostics::redact_diagnostic_text(&raw_db_path),
        },
    })
}

/// Read recent error_log rows (already redacted at write time).
/// Swallows a "no such table" error so a partially-initialized DB
/// still produces a usable bundle.
pub(super) fn read_recent_error_logs(conn: &rusqlite::Connection) -> AppResult<Vec<ErrorLogEntry>> {
    let sql = format!(
        "SELECT id, source, level, message, details, created_at
         FROM error_logs
         WHERE created_at >= {cutoff}
         ORDER BY created_at DESC",
        cutoff = retention_cutoff_clause()
    );
    let cutoff_arg = format!("-{BUNDLE_RETENTION_DAYS} days");
    match conn.prepare_cached(&sql) {
        Ok(mut stmt) => {
            let rows: Vec<ErrorLogEntry> = stmt
                .query_map(params![cutoff_arg], |row| {
                    Ok(ErrorLogEntry {
                        id: row.get(0)?,
                        source: row.get(1)?,
                        level: row.get(2)?,
                        message: row.get(3)?,
                        details: row.get(4)?,
                        created_at: row.get(5)?,
                    })
                })
                .map_err(AppError::from)?
                .collect::<Result<_, _>>()
                .map_err(AppError::from)?;
            Ok(rows)
        }
        Err(err) if is_missing_table(&err) => Ok(Vec::new()),
        Err(err) => Err(AppError::from(err)),
    }
}

/// Read recent ai_changelog rows, re-redacting the summary defensively
/// (see module-level doc).
pub(super) fn read_recent_changelog(
    conn: &rusqlite::Connection,
) -> AppResult<Vec<ChangelogBundleRow>> {
    let actor_filter = ai_changelog_assistant_actor_filter_sql();
    let sql = format!(
        "SELECT id, timestamp, operation, entity_type, entity_id,
                summary, mcp_tool, source_device_id
         FROM ai_changelog
         WHERE timestamp >= {cutoff}
           AND {actor_filter}
         ORDER BY timestamp DESC",
        cutoff = retention_cutoff_clause()
    );
    let cutoff_arg = format!("-{BUNDLE_RETENTION_DAYS} days");
    match conn.prepare_cached(&sql) {
        Ok(mut stmt) => {
            let rows: Vec<ChangelogBundleRow> = stmt
                .query_map(params![cutoff_arg], |row| {
                    let raw_summary: String = row.get(5)?;
                    let redacted_summary =
                        lorvex_domain::diagnostics::redact_diagnostic_text(&raw_summary);
                    let entity_type_raw: String = row.get(3)?;
                    let entity_type = EntityKind::parse(&entity_type_raw).ok_or_else(|| {
                        rusqlite::Error::FromSqlConversionFailure(
                            3,
                            rusqlite::types::Type::Text,
                            Box::new(std::io::Error::new(
                                std::io::ErrorKind::InvalidData,
                                format!(
                                    "invalid ai_changelog.entity_type column value: {entity_type_raw}"
                                ),
                            )),
                        )
                    })?;
                    Ok(ChangelogBundleRow {
                        id: row.get(0)?,
                        timestamp: row.get(1)?,
                        operation: row.get(2)?,
                        entity_type,
                        entity_id: row.get(4)?,
                        summary: redacted_summary,
                        mcp_tool: row.get(6)?,
                        source_device_id: row.get(7)?,
                    })
                })
                .map_err(AppError::from)?
                .collect::<Result<_, _>>()
                .map_err(AppError::from)?;
            Ok(rows)
        }
        Err(err) if is_missing_table(&err) => Ok(Vec::new()),
        Err(err) => Err(AppError::from(err)),
    }
}

/// Read the local `sync_conflict_log` table. Column order mirrors
/// `sync_conflicts.rs::row_to_conflict_entry`.
pub(super) fn read_conflict_log(
    conn: &rusqlite::Connection,
) -> AppResult<Vec<SyncConflictLogEntry>> {
    let sql = "SELECT id, entity_type, entity_id, winner_version, loser_version,
                      loser_device_id, loser_payload, resolved_at, resolution_type
               FROM sync_conflict_log
               ORDER BY id DESC
               LIMIT ?1";
    match conn.prepare_cached(sql) {
        Ok(mut stmt) => {
            let rows: Vec<SyncConflictLogEntry> = stmt
                .query_map(params![MAX_CONFLICT_LOG_ROWS], |row| {
                    let entity_type_raw: String = row.get(1)?;
                    let entity_type = EntityKind::parse(&entity_type_raw).ok_or_else(|| {
                        rusqlite::Error::FromSqlConversionFailure(
                            1,
                            rusqlite::types::Type::Text,
                            Box::new(std::io::Error::new(
                                std::io::ErrorKind::InvalidData,
                                format!(
                                    "invalid sync_conflict_log.entity_type column value: {entity_type_raw}"
                                ),
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
                })
                .map_err(AppError::from)?
                .collect::<Result<_, _>>()
                .map_err(AppError::from)?;
            Ok(rows)
        }
        Err(err) if is_missing_table(&err) => Ok(Vec::new()),
        Err(err) => Err(AppError::from(err)),
    }
}

fn is_missing_table(err: &rusqlite::Error) -> bool {
    // SQLite reports missing tables via `SqliteFailure` with a message
    // that includes "no such table". A locked DB, by contrast, reports
    // a distinct error code that we want to propagate so the caller
    // knows the bundle is empty because the DB was busy, not because
    // the table never existed.
    err.to_string()
        .to_ascii_lowercase()
        .contains("no such table")
}
