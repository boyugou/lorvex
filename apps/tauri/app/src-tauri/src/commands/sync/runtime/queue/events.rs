use super::types::outbox_entry_from_row;
use super::*;
use crate::error::AppResult;

#[tauri::command]
pub fn get_pending_outbox_entries(limit: Option<i64>) -> Result<Vec<SyncOutboxEntry>, String> {
    get_pending_outbox_entries_inner(limit).map_err(String::from)
}

fn get_pending_outbox_entries_inner(limit: Option<i64>) -> AppResult<Vec<SyncOutboxEntry>> {
    let conn = get_read_conn()?;
    let cap = clamp_limit(limit, 200, 1, MAX_SYNC_EVENTS_LIMIT);

    rows_from_query(
        &conn,
        "SELECT id, entity_type, entity_id, operation, payload, created_at, device_id, synced_at, retry_count, last_retry_at
         FROM sync_outbox
         WHERE synced_at IS NULL
         ORDER BY created_at ASC, id ASC
         LIMIT ?1",
        params![cap],
        outbox_entry_from_row,
    )
}

#[tauri::command]
pub fn get_recent_outbox_entries(limit: Option<i64>) -> Result<Vec<SyncOutboxEntry>, String> {
    get_recent_outbox_entries_inner(limit).map_err(String::from)
}

fn get_recent_outbox_entries_inner(limit: Option<i64>) -> AppResult<Vec<SyncOutboxEntry>> {
    let conn = get_read_conn()?;
    let cap = clamp_limit(limit, 200, 1, MAX_SYNC_EVENTS_LIMIT);

    rows_from_query(
        &conn,
        "SELECT id, entity_type, entity_id, operation, payload, created_at, device_id, synced_at, retry_count, last_retry_at
         FROM sync_outbox
         ORDER BY created_at DESC, id DESC
         LIMIT ?1",
        params![cap],
        outbox_entry_from_row,
    )
}
