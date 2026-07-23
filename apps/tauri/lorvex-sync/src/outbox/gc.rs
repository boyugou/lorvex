use rusqlite::{params, Connection};

use super::constants::MAX_RETRIES;

/// Delete outbox entries past the retention window.
///
/// Two reasons an entry qualifies:
/// 1. It has been synced (`synced_at IS NOT NULL`) and the sync stamp is
///    older than the retention window — normal happy-path GC.
/// 2. It has exhausted `MAX_RETRIES` and its creation time is older than
///    the window — otherwise permanently failed envelopes (oversized
///    payloads flagged in `mark_outbox_entry_retry_internal`, server-
///    rejected structural errors that never recover) accumulate forever
///    and slowly bloat the outbox. Callers that care about the content
///    should surface it via `persist_sync_issue` before the retention
///    window expires.
///
/// Returns the number of deleted rows.
pub fn gc_synced(conn: &Connection, retention_days: u32) -> Result<u64, rusqlite::Error> {
    let retention_offset = format!("-{retention_days} days");
    // Gate the permanent-failure cleanup branch on
    // `last_error IS NOT NULL`. Without that gate, any unsynced row
    // at `retry_count >= MAX_RETRIES` would be eligible regardless
    // of whether the user had been surfaced the failure cause —
    // a same-error escalation that crossed `MAX_RETRIES` without
    // ever populating `last_error` (a decode-poison quarantine
    // shape, or a race in `mark_permanently_failed` mid-write)
    // would silently disappear after the retention window without
    // a diagnostic trace. With
    // the gate, only rows whose `last_error` is populated — meaning
    // the per-row `last_error` is stamped AND (in every code path
    // that reaches MAX_RETRIES) an `error_logs` row was written
    // alongside it — are eligible for retention cleanup. A row
    // missing `last_error` is left in place; the next manual reset
    // or transport switch can revive it, and at worst it sits
    // visibly in the table as a flag that a permanent failure
    // escaped surfacing.
    let deleted = conn
        .prepare_cached(
            "DELETE FROM sync_outbox
             WHERE (
                     synced_at IS NOT NULL
                     AND synced_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?1)
                   )
                OR (
                     synced_at IS NULL
                     AND retry_count >= ?2
                     AND last_error IS NOT NULL
                     AND created_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?1)
                   )",
        )?
        .execute(params![retention_offset, MAX_RETRIES])?;
    Ok(deleted as u64)
}
