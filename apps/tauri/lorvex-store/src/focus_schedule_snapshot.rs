//! Shared focus schedule block normalization for sync/export.
//!
//! Provider-derived event blocks must have their event_id stripped and
//! title neutralized to "Event" before entering any synced payload
//! (doc 19 write-down rule).

use rusqlite::Connection;
use serde_json::Value;

/// Neutral label for provider-derived event blocks in synced payloads.
const NEUTRAL_EVENT_TITLE: &str = "Event";

/// Normalize a single focus schedule block for sync.
///
/// If `is_canonical_event` is false and the block has an event_id,
/// the event_id is stripped and the title neutralized to "Event".
///
/// This is the shared normalization contract. All serialization paths
/// (DB-row based: export/reseed, in-memory struct based: live enqueue/MCP)
/// must call this or apply equivalent logic.
fn normalize_block_for_sync(
    event_id: Option<String>,
    title: Option<String>,
    is_canonical_event: bool,
) -> (Option<String>, Option<String>) {
    let is_provider_block = event_id.is_some() && !is_canonical_event;
    let synced_event_id = if is_provider_block { None } else { event_id };
    let synced_title = if is_provider_block {
        Some(NEUTRAL_EVENT_TITLE.to_string())
    } else {
        title
    };
    (synced_event_id, synced_title)
}

/// Serialize focus_schedule blocks for a given date into a canonical
/// JSON array suitable for sync/export payloads.
///
/// Uses `normalize_block_for_sync` for each block, with a LEFT JOIN
/// to determine canonical status.
pub fn serialize_blocks_for_sync(
    conn: &Connection,
    schedule_date: &str,
) -> Result<Vec<Value>, rusqlite::Error> {
    let mut stmt = conn.prepare_cached(
        "SELECT b.block_type, b.start_time, b.end_time, b.task_id, b.event_id, b.title,
                ce.id AS canonical_event_id
         FROM focus_schedule_blocks b
         LEFT JOIN calendar_events ce ON ce.id = b.event_id
         WHERE b.schedule_date = ?1 ORDER BY b.position ASC",
    )?;

    let mut blocks = Vec::new();
    let mut rows = stmt.query(rusqlite::params![schedule_date])?;
    while let Some(row) = rows.next()? {
        let block_type: String = row.get(0)?;
        let start_time: i64 = row.get(1)?;
        let end_time: i64 = row.get(2)?;
        let task_id: Option<String> = row.get(3)?;
        let event_id: Option<String> = row.get(4)?;
        let title: Option<String> = row.get(5)?;
        let is_canonical: Option<String> = row.get(6)?;

        let (synced_event_id, synced_title) =
            normalize_block_for_sync(event_id, title, is_canonical.is_some());

        blocks.push(serde_json::json!({
            "block_type": block_type,
            "start_time": start_time,
            "end_time": end_time,
            "task_id": task_id,
            "event_id": synced_event_id,
            "title": synced_title,
        }));
    }

    Ok(blocks)
}
