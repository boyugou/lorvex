use crate::contract::ListPendingOutboxEntriesArgs;
use crate::error::McpError;
use crate::json_row::query_all_as_json;
use crate::system::handler_support::{bounded_limit_or_default, next_offset_for_page};
use rusqlite::{types::Value as SqlValue, Connection};
use serde_json::json;

pub(crate) fn list_pending_outbox_entries(
    conn: &Connection,
    args: &ListPendingOutboxEntriesArgs,
) -> Result<String, McpError> {
    let &ListPendingOutboxEntriesArgs { limit, offset } = args;
    let limit = bounded_limit_or_default(limit, 100, 500);
    let offset = offset.unwrap_or(0);

    // #3019-M1: count first so the response can flag truncation
    // and emit `next_offset` for the next page.
    let total_matching: i64 = conn.query_row(
        "SELECT COUNT(*) FROM sync_outbox WHERE synced_at IS NULL",
        [],
        |row| row.get(0),
    )?;

    let rows = query_all_as_json(
        conn,
        "
        SELECT
          id, entity_type, entity_id, operation, payload,
          created_at, device_id, synced_at, retry_count, last_retry_at
        FROM sync_outbox
        WHERE synced_at IS NULL
        ORDER BY created_at ASC, id ASC
        LIMIT ? OFFSET ?
        ",
        [
            SqlValue::Integer(i64::from(limit)),
            SqlValue::Integer(i64::from(offset)),
        ],
    )?;

    let returned = rows.len() as i64;
    let consumed = i64::from(offset).saturating_add(returned);
    let truncated = total_matching > consumed;
    let next_offset = next_offset_for_page(truncated, consumed, returned);
    let payload = json!({
        "count": rows.len(),
        "returned": rows.len(),
        "total_matching": total_matching,
        "limit": limit,
        "offset": offset,
        "next_offset": next_offset,
        "truncated": truncated,
        "entries": rows,
    });
    Ok(serde_json::to_string_pretty(&payload)?)
}
