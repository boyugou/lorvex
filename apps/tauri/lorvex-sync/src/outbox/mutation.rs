use rusqlite::{params, Connection};

/// Mark an outbox entry as synced.
///
/// Sets the `synced_at` timestamp to indicate the entry has been successfully
/// pushed to the remote transport and clears any stale error text from prior
/// failed attempts.
pub fn mark_synced(
    conn: &Connection,
    outbox_id: i64,
    synced_at: &str,
) -> Result<(), rusqlite::Error> {
    // only overwrite `synced_at` when still NULL. A row
    // already marked synced on a prior cycle (e.g. due to provider
    // idempotent ChangedKeys acceptance of a re-pushed envelope) keeps
    // its original synced_at timestamp rather than regressing to a
    // later one. Retention cleanup uses synced_at < cutoff, so a later
    // timestamp could delay GC; the guard keeps the original.
    conn.prepare_cached(
        "UPDATE sync_outbox \
         SET synced_at = ?1, last_error = NULL \
         WHERE id = ?2 AND synced_at IS NULL",
    )?
    .execute(params![synced_at, outbox_id])?;
    Ok(())
}

/// bulk-mark a batch of outbox entries as synced
/// in a single UPDATE instead of one UPDATE per id. Provider pushes
/// batch up to 400 records; the per-row loop held the
/// writer lock for ~400 sequential UPDATEs on a large successful push.
///
/// Respects the same `synced_at IS NULL` guard as `mark_synced` so a
/// row already marked synced on a prior cycle keeps its original
/// timestamp. Chunks the IN list at a conservative 500 to stay well
/// below SQLite's default variable limit.
pub fn mark_many_synced(
    conn: &Connection,
    outbox_ids: &[i64],
    synced_at: &str,
) -> Result<(), rusqlite::Error> {
    if outbox_ids.is_empty() {
        return Ok(());
    }
    const CHUNK: usize = 500;
    for chunk in outbox_ids.chunks(CHUNK) {
        let placeholders = lorvex_domain::sql_csv_placeholders(chunk.len());
        // Clear `last_error` on every successful sync — this is the
        // canonical place because it's the single transition into
        // the `synced_at IS NOT NULL` state. Without the clear, the
        // Diagnostics panel would render the historical error
        // string forever next to a row that DID eventually sync
        // (e.g. a "Permission denied" left over from an earlier
        // retry chain persisting long after the actual permission
        // was granted and the envelope round-tripped). `retry_count`
        // and `last_retry_at` are intentionally LEFT in place so
        // post-
        // hoc analysis can still see how many retries the row took
        // to land — only the live error display is reset.)
        let sql = format!(
            "UPDATE sync_outbox \
             SET synced_at = ?, last_error = NULL \
             WHERE synced_at IS NULL AND id IN ({placeholders})"
        );
        // Bind synced_at first, then the ids positionally.
        let bound: Vec<&dyn rusqlite::ToSql> = std::iter::once(&synced_at as &dyn rusqlite::ToSql)
            .chain(chunk.iter().map(|id| id as &dyn rusqlite::ToSql))
            .collect();
        // The placeholder count varies with chunk size, but the only
        // distinct sizes in practice are the full-chunk constant and
        // the trailing partial chunk — at most two cache entries per
        // mark-synced batch, which is what `prepare_cached` is for.
        conn.prepare_cached(&sql)?
            .execute(rusqlite::params_from_iter(bound))?;
    }
    Ok(())
}

/// Delete a single outbox entry by id.
///
/// Test-only primitive — no production code path deletes an outbox
/// row directly (undo issues a fresh reverse-write envelope instead
/// of retracting queued rows). Gated behind `cfg(test)` so the
/// production lib doesn't carry the helper; if a future production
/// caller needs single-row deletion, lift the gate explicitly.
#[cfg(test)]
pub(crate) fn delete_entry(conn: &Connection, outbox_id: i64) -> Result<(), rusqlite::Error> {
    conn.prepare_cached("DELETE FROM sync_outbox WHERE id = ?1")?
        .execute(params![outbox_id])?;
    Ok(())
}
