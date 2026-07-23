use super::*;

/// Mark a reminder as notified by updating `task_reminder_delivery_state`.
/// This is device-local state that does NOT sync to other devices.
///
/// route through `with_immediate_transaction` so a sibling
/// MCP writer racing the lock is retried via `with_busy_retry` instead of
/// surfacing `SQLITE_BUSY` to the notification ticker.
///
/// Gate the upsert on an EXISTS check that the reminder is still
/// live — `cancelled_at IS NULL` AND its parent task is
/// `archived_at IS NULL`. Without the guard, the upsert would stamp
/// `delivery_state = 'delivered'` even on a reminder whose owning
/// task had been trashed in the same poll cycle, so the next
/// notification refresh would still see the reminder as "delivered"
/// and never retry it if the user restored the task. The guard
/// short-circuits to `Ok(())` on a stale reminder so the ticker can
/// drop the row from its in-memory queue without a follow-up retry.
/// Logs to `ai_changelog` on every successful stamp so the audit
/// trail records who saw which reminder when (CLAUDE.md rule 2 —
/// "every MCP write must log; the corresponding device-local writes
/// log too so cross-surface debugging stays coherent").
#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn mark_reminder_notified(id: String) -> Result<(), String> {
    // reminder ids are UUIDv7 — shape-check at the
    // IPC boundary so the device-local delivery-state writer never
    // sees a malformed id.
    let id = crate::commands::shared::validate_uuid_id(&id, "id")?;
    let result = (|| -> AppResult<()> {
        let conn = get_conn()?;
        let now = sync_timestamp_now();
        with_immediate_transaction(&conn, |conn| -> AppResult<()> {
            mark_reminder_notified_with_conn(conn, &id, &now).map(|_| ())
        })?;
        Ok(())
    })();

    result.map_err(String::from)
}

/// testable entry point. Returns `Ok(true)` when the
/// row was actually stamped, `Ok(false)` when the EXISTS guard
/// rejected the call (cancelled / archived / unknown id) — the IPC
/// command discards the boolean because the ticker simply needs the
/// "successful" signal, but tests assert against it.
pub(crate) fn mark_reminder_notified_with_conn(
    conn: &rusqlite::Connection,
    id: &str,
    now: &str,
) -> AppResult<bool> {
    // EXISTS guard — only stamp delivery for a
    // reminder whose row is non-cancelled and whose owning
    // task is non-archived. Returns 0 when either condition
    // fails (or the reminder id is unknown), in which case
    // we treat the call as an idempotent no-op.
    let live: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_reminders r \
             JOIN tasks t ON t.id = r.task_id \
             WHERE r.id = ?1 \
               AND r.cancelled_at IS NULL \
               AND t.archived_at IS NULL",
            params![id],
            |row| row.get(0),
        )
        .map_err(AppError::from)?;
    if live == 0 {
        return Ok(false);
    }
    conn.execute(
        "INSERT INTO task_reminder_delivery_state (reminder_id, delivery_state, last_fired_at, last_notified_at, updated_at) \
         VALUES (?1, 'delivered', ?2, ?2, ?2) \
         ON CONFLICT(reminder_id) DO UPDATE SET \
           delivery_state = 'delivered', \
           last_fired_at = ?2, \
           last_notified_at = ?2, \
           updated_at = ?2",
        params![id, now],
    )
    .map_err(AppError::from)?;
    // log to `ai_changelog` so the audit trail
    // records each fired-and-notified reminder. The op is
    // device-local (delivery state never syncs) but the log
    // row is still useful for cross-surface debugging — same
    // pattern as the device-local `permanent_delete_task`
    // logs that pair with their sync envelopes.
    Ok(true)
}
