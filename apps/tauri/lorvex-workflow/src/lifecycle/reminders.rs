use lorvex_domain::TaskId;
use rusqlite::{params, Connection};

use lorvex_store::StoreError;

/// Un-cancel all cancelled (but not dismissed) reminders for a task.
///
/// Returns the IDs of reminders whose `cancelled_at` was cleared. Dismissed
/// reminders are left alone — the user explicitly acknowledged them, so
/// reopening the task should not resurrect them.
///
/// For each restored reminder, the device-local
/// `task_reminder_delivery_state` row is deleted so that the reminder can
/// re-fire a fresh notification.
pub fn uncancel_task_reminders(
    conn: &Connection,
    task_id: &TaskId,
    version: &str,
) -> Result<Vec<String>, StoreError> {
    // The UPDATE is gated on `?2 > version` (LWW) so a
    // stale local un-cancel cannot clobber a peer's freshly-applied
    // dismiss. The SELECT mirrors the gate so we only return ids of
    // reminders that were actually flipped — otherwise the caller
    // would enqueue sync upserts for rows that the peer's row wins
    // anyway, churning the outbox with no-op envelopes.
    let ids: Vec<String> = conn
        .prepare_cached(
            "SELECT id FROM task_reminders \
             WHERE task_id = ?1 AND dismissed_at IS NULL AND cancelled_at IS NOT NULL \
               AND ?2 > version",
        )?
        .query_map(params![task_id, version], |row| row.get(0))?
        .collect::<Result<Vec<_>, _>>()?;

    if !ids.is_empty() {
        conn.prepare_cached(
            "UPDATE task_reminders SET cancelled_at = NULL, version = ?2 \
             WHERE task_id = ?1 AND dismissed_at IS NULL AND cancelled_at IS NOT NULL \
               AND ?2 > version",
        )?
        .execute(params![task_id, version])?;

        // Scope the DELETE to the EXACT ids captured before the
        // UPDATE, not to a post-UPDATE filter `cancelled_at IS NULL`.
        // A `cancelled_at IS NULL` subquery would match BOTH (a) the
        // reminders we just uncancelled AND (b) reminders that were
        // never cancelled to begin with — so a routine "uncancel one
        // restored reminder" call could silently wipe the delivery
        // state for every other still-pending reminder on the same
        // task. Bind the `ids` list directly so the DELETE only
        // touches the rows we mutated.
        let placeholders = lorvex_domain::sql_csv_placeholders(ids.len());
        let sql = format!(
            "DELETE FROM task_reminder_delivery_state WHERE reminder_id IN ({placeholders})",
        );
        let bound: Vec<&dyn rusqlite::ToSql> =
            ids.iter().map(|id| id as &dyn rusqlite::ToSql).collect();
        conn.execute(&sql, rusqlite::params_from_iter(bound))?;
    }
    Ok(ids)
}

/// Cancel all active (non-dismissed, non-cancelled) reminders for a task.
/// Returns the IDs of reminders that were cancelled.
/// Public so that callers handling status transitions in dynamic-update paths
/// can invoke reminder cancellation consistently without reimplementing it.
pub fn cancel_active_reminders(
    conn: &Connection,
    task_id: &TaskId,
    now: &str,
    version: &str,
) -> Result<Vec<String>, StoreError> {
    // Mirror the `uncancel_task_reminders` discipline — capture the
    // ids set BEFORE the UPDATE, then scope the UPDATE to
    // `id IN (captured ids)`. Sharing a `WHERE` body between the
    // SELECT and the UPDATE leaves a TOCTOU window: a peer apply
    // landing in the same outer txn could mutate the row's
    // `cancelled_at` / `dismissed_at` / `version` between the SELECT
    // and the UPDATE, so the returned ids would diverge from the
    // actual write set. Binding the captured ids closes the
    // divergence.
    let ids: Vec<String> = conn
        .prepare_cached(
            "SELECT id FROM task_reminders \
             WHERE task_id = ?1 AND dismissed_at IS NULL AND cancelled_at IS NULL \
               AND ?2 > version",
        )?
        .query_map(params![task_id, version], |row| row.get(0))?
        .collect::<Result<Vec<_>, _>>()?;

    if ids.is_empty() {
        return Ok(ids);
    }

    let placeholders = lorvex_domain::sql_csv_placeholders(ids.len());
    let sql = format!(
        "UPDATE task_reminders SET cancelled_at = ?1, version = ?2 \
         WHERE id IN ({placeholders}) AND ?2 > version",
    );
    let mut bound: Vec<&dyn rusqlite::ToSql> = Vec::with_capacity(2 + ids.len());
    bound.push(&now as &dyn rusqlite::ToSql);
    bound.push(&version as &dyn rusqlite::ToSql);
    for id in &ids {
        bound.push(id as &dyn rusqlite::ToSql);
    }
    let updated = conn.execute(&sql, rusqlite::params_from_iter(bound))?;

    // If the gate rejected some captured ids (a peer apply landed
    // between the SELECT and the UPDATE), trim the returned set so
    // callers only enqueue outbox envelopes for rows that were
    // actually flipped.
    //
    // Re-query by `version`, not by `cancelled_at = ?` bound to the
    // local `now` string. The `cancelled_at` re-read is structurally
    // fragile: any timestamp normalization difference between the
    // UPDATE write and the re-read (e.g. an extra milliseconds-
    // precision drift, or a future change to how `now` is
    // stringified) would silently exclude rows we just cancelled,
    // and a concurrent peer that happened to write `cancelled_at =
    // now` for an unrelated reason would falsely include rows. The
    // `version` column is the unambiguous signal: our UPDATE just
    // stamped `version = ?2` on every row it touched, and HLC values
    // are globally unique per device suffix + physical_ms + counter
    // — no concurrent writer can produce the same string. Matching
    // on `version = ?` therefore returns exactly the IDs this call
    // flipped, regardless of timestamp formatting drift.
    if updated == ids.len() {
        Ok(ids)
    } else {
        let placeholders = lorvex_domain::sql_csv_placeholders(ids.len());
        let sql = format!(
            "SELECT id FROM task_reminders \
             WHERE id IN ({placeholders}) AND version = ?",
        );
        let mut bound: Vec<&dyn rusqlite::ToSql> = Vec::with_capacity(ids.len() + 1);
        for id in &ids {
            bound.push(id as &dyn rusqlite::ToSql);
        }
        bound.push(&version as &dyn rusqlite::ToSql);
        let actually_cancelled: Vec<String> = conn
            .prepare(&sql)?
            .query_map(rusqlite::params_from_iter(bound), |row| row.get(0))?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(actually_cancelled)
    }
}
