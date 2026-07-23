use crate::error::McpError;
use crate::json_row::query_all_as_json;
use crate::system::diagnostics::{
    increment_source_count, level_for_changelog_operation, log_level_to_str,
    sanitize_diagnostic_text,
};
use rusqlite::{types::Value as SqlValue, Connection};
use serde_json::{json, Value};

use super::RecentLogCollection;

/// parse a keyset cursor of the form
/// `<timestamp>|<id>`. Returns `None` for any input that doesn't
/// carry the `|` separator or whose halves are empty, so legacy
/// callers passing a bare timestamp transparently fall through to
/// the timestamp-watermark branch in the caller. The pair is
/// returned as `&str` slices borrowed from the input — bindings
/// are owned `String`s at the call site.
fn parse_changelog_cursor(since: &str) -> Option<(&str, &str)> {
    let (ts, id) = since.split_once('|')?;
    if ts.is_empty() || id.is_empty() {
        return None;
    }
    Some((ts, id))
}

pub(super) fn append_ai_changelog_entries(
    conn: &Connection,
    collection: &mut RecentLogCollection<'_>,
) -> Result<(), McpError> {
    // order by `(timestamp DESC, id DESC)` so that
    // same-millisecond rows have a deterministic ranking. The `since`
    // watermark accepts an optional `<timestamp>|<id>` keyset cursor
    // form; legacy callers that pass a bare timestamp still get the
    // With the composite
    // form, the WHERE clause becomes the canonical keyset predicate
    // `(timestamp, id) < (?, ?)` (DESC → strictly older than the
    // cursor pair), eliminating the same-millisecond drop window.
    let rows = if let Some(since) = collection.since {
        if let Some((cursor_ts, cursor_id)) = parse_changelog_cursor(since) {
            query_all_as_json(
                conn,
                "
                SELECT id, timestamp, operation, entity_type, entity_id, summary, initiated_by, mcp_tool
                FROM ai_changelog
                WHERE timestamp < ? OR (timestamp = ? AND id < ?)
                ORDER BY timestamp DESC, id DESC
                LIMIT ?
                ",
                [
                    SqlValue::Text(cursor_ts.to_string()),
                    SqlValue::Text(cursor_ts.to_string()),
                    SqlValue::Text(cursor_id.to_string()),
                    SqlValue::Integer(i64::from(collection.fetch_limit)),
                ],
            )?
        } else {
            query_all_as_json(
                conn,
                "
                SELECT id, timestamp, operation, entity_type, entity_id, summary, initiated_by, mcp_tool
                FROM ai_changelog
                WHERE timestamp > ?
                ORDER BY timestamp DESC, id DESC
                LIMIT ?
                ",
                [
                    SqlValue::Text(since.to_string()),
                    SqlValue::Integer(i64::from(collection.fetch_limit)),
                ],
            )?
        }
    } else {
        query_all_as_json(
            conn,
            "
            SELECT id, timestamp, operation, entity_type, entity_id, summary, initiated_by, mcp_tool
            FROM ai_changelog
            ORDER BY timestamp DESC, id DESC
            LIMIT ?
            ",
            [SqlValue::Integer(i64::from(collection.fetch_limit))],
        )?
    };

    for row in rows {
        let Some(timestamp) = row
            .get("timestamp")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
        else {
            increment_source_count(collection.malformed_source_counts, "ai_changelog");
            continue;
        };
        let Some(operation) = row
            .get("operation")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
        else {
            increment_source_count(collection.malformed_source_counts, "ai_changelog");
            continue;
        };
        let level = level_for_changelog_operation(operation);
        if !collection.active_levels.contains(&level) {
            continue;
        }
        let summary = sanitize_diagnostic_text(
            row.get("summary").and_then(Value::as_str),
            280,
            collection.redact,
        );
        let Some(summary) = summary else {
            increment_source_count(collection.malformed_source_counts, "ai_changelog");
            continue;
        };
        collection.merged.push(json!({
            "timestamp": timestamp,
            "source": "ai_changelog",
            "level": log_level_to_str(level),
            "summary": summary,
            "metadata": {
                "id": row.get("id").cloned().unwrap_or(Value::Null),
                "operation": row.get("operation").cloned().unwrap_or(Value::Null),
                "entity_type": row.get("entity_type").cloned().unwrap_or(Value::Null),
                "entity_id": row.get("entity_id").cloned().unwrap_or(Value::Null),
                "initiated_by": row.get("initiated_by").cloned().unwrap_or(Value::Null),
                "mcp_tool": row.get("mcp_tool").cloned().unwrap_or(Value::Null),
            },
        }));
        increment_source_count(collection.source_counts, "ai_changelog");
    }

    Ok(())
}
