//! JSONL writers for non-versioned export sections.
//!
//! Versioned writers (entities, edges, embedded-children aggregates) live
//! under [`super::writers`] behind the `VersionedTableWriter` trait. The
//! sections below carry their own bespoke wire shape — no version
//! column, no shadow merge — so they stay imperative.

use std::io::Write;

use rusqlite::Connection;

use lorvex_domain::naming::{EntityKind, EDGE_TASK_PROVIDER_EVENT_LINK, ENTITY_AI_CHANGELOG};

use crate::cancellation::check_export_cancelled;
use crate::repositories::ai_changelog_actor_filter::ai_changelog_assistant_actor_filter_sql;
use crate::CancellationToken;

use super::{sqlite_value_to_json, ExportError};

/// Write `task_provider_event_links` rows to `provider_links.jsonl`.
///
/// This table is local-only (no `version` column), so it uses the unversioned
/// `JsonExportRecord` format: `{"entity_type":"...","payload":{...}}`.
/// Returns the number of rows written.
pub(in crate::export) fn write_provider_link_rows(
    conn: &Connection,
    buf: &mut dyn Write,
    cancellation: &dyn CancellationToken,
) -> Result<u64, ExportError> {
    check_export_cancelled(cancellation)?;
    let columns = [
        "task_id",
        "provider_kind",
        "provider_scope",
        "provider_event_key",
        "created_at",
        "updated_at",
    ];
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        let cols = [
            "task_id",
            "provider_kind",
            "provider_scope",
            "provider_event_key",
            "created_at",
            "updated_at",
        ]
        .join(", ");
        format!("SELECT {cols} FROM task_provider_event_links")
    });
    let mut stmt = conn.prepare(sql)?;

    let mut count = 0u64;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        check_export_cancelled(cancellation)?;
        let mut payload = serde_json::Map::new();
        for (i, &col) in columns.iter().enumerate() {
            let val: rusqlite::types::Value = row.get(i)?;
            payload.insert(col.to_string(), sqlite_value_to_json(val));
        }
        let line = serde_json::json!({
            "entity_type": EDGE_TASK_PROVIDER_EVENT_LINK,
            "payload": serde_json::Value::Object(payload),
        });
        serde_json::to_writer(&mut *buf, &line)?;
        buf.write_all(b"\n").map_err(ExportError::Io)?;
        count += 1;
    }
    Ok(count)
}

/// Write canonical ai_changelog entries to audit.jsonl. Returns the count.
/// Only exports entries initiated by AI/MCP — excludes human/system/user/manual
/// entries that may have leaked into the table (spec doc 12: canonical audit boundary).
pub(in crate::export) fn write_audit_rows(
    conn: &Connection,
    buf: &mut dyn Write,
    cancellation: &dyn CancellationToken,
) -> Result<u64, ExportError> {
    check_export_cancelled(cancellation)?;
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        let actor_filter = ai_changelog_assistant_actor_filter_sql();
        let select_clause = crate::repositories::columns::AI_CHANGELOG.select_clause;
        format!(
            "SELECT {select_clause}
             FROM ai_changelog
             WHERE {actor_filter}
             ORDER BY timestamp ASC"
        )
    });
    let mut stmt = conn.prepare(sql)?;

    let mut count = 0u64;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        check_export_cancelled(cancellation)?;
        let id: String = row.get(0)?;
        let timestamp: String = row.get(1)?;
        let operation: String = row.get(2)?;
        let entity_type_raw: String = row.get(3)?;
        let entity_type = EntityKind::parse(&entity_type_raw).ok_or_else(|| {
            ExportError::Store(crate::error::StoreError::Validation(format!(
                "invalid ai_changelog.entity_type column value: {entity_type_raw}"
            )))
        })?;
        let entity_id: Option<String> = row.get(4)?;
        let entity_ids: Option<String> = row.get(5)?;
        let summary: String = row.get(6)?;
        let initiated_by: String = row.get(7)?;
        let mcp_tool: Option<String> = row.get(8)?;
        let source_device_id: Option<String> = row.get(9)?;
        // #2373: structured before/after snapshots round-trip through
        // audit.jsonl so an import restore keeps the diff metadata.
        let before_json: Option<String> = row.get(10)?;
        let after_json: Option<String> = row.get(11)?;
        let undo_token: Option<String> = row.get(12)?;
        let is_preview: i64 = row.get(13)?;

        let payload = serde_json::json!({
            "id": id,
            "timestamp": timestamp,
            "operation": operation,
            "entity_type": entity_type.as_str(),
            "entity_id": entity_id,
            "entity_ids": entity_ids,
            "summary": summary,
            "initiated_by": initiated_by,
            "mcp_tool": mcp_tool,
            "source_device_id": source_device_id,
            "before_json": before_json,
            "after_json": after_json,
            "undo_token": undo_token,
            "is_preview": is_preview != 0,
        });

        let line = serde_json::json!({
            "entity_type": ENTITY_AI_CHANGELOG,
            "entity_id": id,
            "payload": payload,
        });
        serde_json::to_writer(&mut *buf, &line)?;
        buf.write_all(b"\n").map_err(ExportError::Io)?;
        count += 1;
    }

    Ok(count)
}

/// Write sync_tombstones rows to tombstones.jsonl.
pub(in crate::export) fn write_tombstone_rows(
    conn: &Connection,
    buf: &mut dyn Write,
    cancellation: &dyn CancellationToken,
) -> Result<(), ExportError> {
    check_export_cancelled(cancellation)?;
    let mut stmt = conn.prepare(
        "SELECT entity_type, entity_id, version, deleted_at, redirect_entity_id, redirect_entity_type
         FROM sync_tombstones",
    )?;

    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        check_export_cancelled(cancellation)?;
        let entity_type_raw: String = row.get(0)?;
        let entity_type = EntityKind::parse(&entity_type_raw).ok_or_else(|| {
            ExportError::Store(crate::error::StoreError::Validation(format!(
                "invalid sync_tombstones.entity_type column value: {entity_type_raw}"
            )))
        })?;
        let entity_id: String = row.get(1)?;
        let version: String = row.get(2)?;
        let deleted_at: String = row.get(3)?;
        let redirect_entity_id: Option<String> = row.get(4)?;
        let redirect_entity_type_raw: Option<String> = row.get(5)?;
        let redirect_entity_type = redirect_entity_type_raw
            .map(|raw| {
                EntityKind::parse(&raw).ok_or_else(|| {
                    ExportError::Store(crate::error::StoreError::Validation(format!(
                        "invalid sync_tombstones.redirect_entity_type column value: {raw}"
                    )))
                })
            })
            .transpose()?;

        let line = serde_json::json!({
            "entity_type": entity_type.as_str(),
            "entity_id": entity_id,
            "version": version,
            "deleted_at": deleted_at,
            "redirect_entity_id": redirect_entity_id,
            "redirect_entity_type": redirect_entity_type.map(|k| k.as_str()),
        });
        serde_json::to_writer(&mut *buf, &line)?;
        buf.write_all(b"\n").map_err(ExportError::Io)?;
    }

    Ok(())
}

pub(in crate::export) fn write_payload_shadow_rows(
    conn: &Connection,
    buf: &mut dyn Write,
    cancellation: &dyn CancellationToken,
) -> Result<(), ExportError> {
    check_export_cancelled(cancellation)?;
    for row in lorvex_sync_payload::payload_shadow::list_shadows(conn)? {
        check_export_cancelled(cancellation)?;
        let line = serde_json::json!({
            "entity_type": row.entity_type.as_str(),
            "entity_id": row.entity_id,
            "base_version": row.base_version,
            "payload_schema_version": row.payload_schema_version,
            "raw_payload_json": row.raw_payload_json,
            "source_device_id": row.source_device_id,
            "updated_at": row.updated_at,
        });
        serde_json::to_writer(&mut *buf, &line)?;
        buf.write_all(b"\n").map_err(ExportError::Io)?;
    }

    Ok(())
}
