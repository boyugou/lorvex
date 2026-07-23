use crate::contract::LogLevelFilter;
use crate::error::McpError;
use crate::json_row::query_all_as_json;
use crate::system::diagnostics::{
    increment_source_count, log_level_to_str, normalize_log_level, sanitize_diagnostic_text,
};
use rusqlite::{types::Value as SqlValue, Connection};
use serde_json::{json, Value};

use super::RecentLogCollection;

pub(super) fn append_error_log_entries(
    conn: &Connection,
    collection: &mut RecentLogCollection<'_>,
) -> Result<(), McpError> {
    let rows = if let Some(since) = collection.since {
        query_all_as_json(
            conn,
            "
            SELECT id, source, level, message, details, created_at
            FROM error_logs
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
            SELECT id, source, level, message, details, created_at
            FROM error_logs
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
            increment_source_count(collection.malformed_source_counts, "error_log");
            continue;
        };
        let level = normalize_log_level(
            row.get("level").and_then(Value::as_str),
            LogLevelFilter::Error,
        );
        if !collection.active_levels.contains(&level) {
            continue;
        }
        let Some(emitter) = row
            .get("source")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
        else {
            increment_source_count(collection.malformed_source_counts, "error_log");
            continue;
        };
        let summary = sanitize_diagnostic_text(
            row.get("message").and_then(Value::as_str),
            280,
            collection.redact,
        );
        let Some(summary) = summary else {
            increment_source_count(collection.malformed_source_counts, "error_log");
            continue;
        };
        let details = if collection.include_details {
            sanitize_diagnostic_text(
                row.get("details").and_then(Value::as_str),
                1600,
                collection.redact,
            )
        } else {
            None
        };

        let mut entry = json!({
            "timestamp": timestamp,
            "source": "error_log",
            "level": log_level_to_str(level),
            "summary": summary,
            "metadata": {
                "id": row.get("id").cloned().unwrap_or(Value::Null),
                "emitter": emitter,
            },
        });
        if let Some(details) = details {
            if let Some(obj) = entry.as_object_mut() {
                obj.insert("details".to_string(), json!(details));
            }
        }
        collection.merged.push(entry);
        increment_source_count(collection.source_counts, "error_log");
    }

    Ok(())
}
