use crate::contract::LogLevelFilter;
use crate::error::McpError;
use crate::json_row::query_all_as_json;
use crate::system::diagnostics::{
    increment_source_count, log_level_to_str, sanitize_diagnostic_text,
};
use rusqlite::{types::Value as SqlValue, Connection};
use serde_json::{json, Value};

use super::RecentLogCollection;

pub(super) fn append_sync_outbox_entries(
    conn: &Connection,
    collection: &mut RecentLogCollection<'_>,
) -> Result<(), McpError> {
    let rows = if let Some(since) = collection.since {
        query_all_as_json(
            conn,
            "
            SELECT id, entity_type, entity_id, operation, created_at, device_id, synced_at, retry_count
            FROM sync_outbox
            WHERE created_at > ?
            ORDER BY created_at DESC
            LIMIT ?
            ",
            [
                SqlValue::Text(since.to_string()),
                SqlValue::Integer(i64::from(collection.fetch_limit)),
            ],
        )?
    } else {
        query_all_as_json(
            conn,
            "
            SELECT id, entity_type, entity_id, operation, created_at, device_id, synced_at, retry_count
            FROM sync_outbox
            ORDER BY created_at DESC
            LIMIT ?
            ",
            [SqlValue::Integer(i64::from(collection.fetch_limit))],
        )?
    };

    for row in rows {
        let Some(timestamp) = row
            .get("created_at")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
        else {
            increment_source_count(collection.malformed_source_counts, "sync_outbox");
            continue;
        };
        let Some(retry_count) = row.get("retry_count").and_then(Value::as_i64) else {
            increment_source_count(collection.malformed_source_counts, "sync_outbox");
            continue;
        };
        let synced_at = row.get("synced_at").cloned().unwrap_or(Value::Null);
        let level = if !synced_at.is_null() {
            LogLevelFilter::Debug
        } else if retry_count > 0 {
            LogLevelFilter::Warn
        } else {
            LogLevelFilter::Info
        };
        if !collection.active_levels.contains(&level) {
            continue;
        }

        let Some(entity_type) = row
            .get("entity_type")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
        else {
            increment_source_count(collection.malformed_source_counts, "sync_outbox");
            continue;
        };
        let Some(operation) = row
            .get("operation")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
        else {
            increment_source_count(collection.malformed_source_counts, "sync_outbox");
            continue;
        };
        let Some(entity_id) = row
            .get("entity_id")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
        else {
            increment_source_count(collection.malformed_source_counts, "sync_outbox");
            continue;
        };
        let raw_summary = format!("{entity_type}:{operation} {entity_id}");
        let summary = sanitize_diagnostic_text(Some(raw_summary.as_str()), 280, collection.redact);
        let Some(summary) = summary else {
            increment_source_count(collection.malformed_source_counts, "sync_outbox");
            continue;
        };

        collection.merged.push(json!({
            "timestamp": timestamp,
            "source": "sync_outbox",
            "level": log_level_to_str(level),
            "summary": summary,
            "metadata": {
                "id": row.get("id").cloned().unwrap_or(Value::Null),
                "device_id": row.get("device_id").cloned().unwrap_or(Value::Null),
                "synced_at": synced_at,
                "retry_count": retry_count,
            },
        }));
        increment_source_count(collection.source_counts, "sync_outbox");
    }

    Ok(())
}
