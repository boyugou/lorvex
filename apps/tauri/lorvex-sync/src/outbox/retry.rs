use lorvex_store::error::StoreError;
use lorvex_store::transaction::with_savepoint;
use rusqlite::{params, Connection, OptionalExtension};

use super::constants::{
    truncate_outbox_last_error, MAX_RETRIES, RECORD_MANY_RETRIES_SENTINEL_ID,
    SAME_ERROR_ESCALATION_THRESHOLD,
};
use super::types::RecordRetryOutcome;

/// Increment the retry count and update `last_retry_at` for a failed push.
///
/// When `error` is `Some`, the helper also persists it in the new
/// `last_error` column and compares against the previous value. If
/// the incoming error matches the previous one AND the retry_count
/// would reach or exceed `SAME_ERROR_ESCALATION_THRESHOLD`, the row
/// is fast-forwarded to `MAX_RETRIES` — the caller
/// still observes `exhausted_now = true` and can surface the
/// permanent failure immediately instead of waiting for the remaining
/// retry cycles to tick through the same error repeatedly.
///
/// Returns a `RecordRetryOutcome` so callers can detect when the row
/// has just crossed the `MAX_RETRIES` threshold and needs to be
/// surfaced to the user as a permanent sync failure.
pub fn record_retry(
    conn: &Connection,
    outbox_id: i64,
    retried_at: &str,
    error: Option<&str>,
) -> Result<RecordRetryOutcome, rusqlite::Error> {
    // guard on `synced_at IS NULL` so a race between two
    // concurrent sync paths — or a record_retry call against a row
    // that another surface just marked synced — can't bump retry_count
    // on an already-synced row. Defense in depth; the scheduled path
    // only calls this for failed pushes, but the guard prevents any
    // future caller from accidentally inflating retry counts.
    let previous_error: Option<String> = conn
        .query_row(
            "SELECT last_error FROM sync_outbox WHERE id = ?1 AND synced_at IS NULL",
            params![outbox_id],
            |row| row.get(0),
        )
        .optional()?
        .flatten();

    // cap the per-row `last_error` at
    // OUTBOX_LAST_ERROR_MAX_BYTES so a pathological provider response
    // (full envelope dump, chained cause that grows on each retry)
    // cannot bloat the row by orders of magnitude. The same-error
    // escalation below compares the truncated form to its own
    // previously-stored truncated form so the byte-equality check
    // stays consistent across retries.
    let truncated_error = error.map(truncate_outbox_last_error);
    let truncated_error_ref = truncated_error.as_deref();

    conn.prepare_cached(
        "UPDATE sync_outbox
         SET retry_count = retry_count + 1,
             last_retry_at = ?1,
             last_error = COALESCE(?3, last_error)
         WHERE id = ?2 AND synced_at IS NULL",
    )?
    .execute(params![retried_at, outbox_id, truncated_error_ref])?;
    let mut new_retry_count: i64 = conn
        .prepare_cached("SELECT retry_count FROM sync_outbox WHERE id = ?1")?
        .query_row(params![outbox_id], |row| row.get(0))
        .optional()?
        .unwrap_or(0);

    // Same-error escalation: if the caller supplied an error AND it
    // matches the prior `last_error`, jump retry_count to MAX so the
    // row quarantines without burning the remaining cycles. Compare
    // the truncated form so a >4 KiB error that was stored
    // unchanged but is now capped doesn't appear "different" from its
    // own retry — see #2999-L20.
    if let (Some(err), Some(prev)) = (truncated_error_ref, previous_error.as_deref()) {
        if err == prev && (SAME_ERROR_ESCALATION_THRESHOLD..MAX_RETRIES).contains(&new_retry_count)
        {
            conn.prepare_cached("UPDATE sync_outbox SET retry_count = ?1 WHERE id = ?2")?
                .execute(params![MAX_RETRIES, outbox_id])?;
            new_retry_count = MAX_RETRIES;
        }
    }

    // "Just exhausted" = this call brought the count to exactly
    // MAX_RETRIES. Subsequent `record_retry` calls on the same row
    // still increment (for observability — users can see how many
    // extra attempts were made post-exhaustion), but only the first
    // crossing fires the user notification.
    let exhausted_now = new_retry_count == MAX_RETRIES;
    Ok(RecordRetryOutcome {
        new_retry_count,
        exhausted_now,
    })
}

/// Bulk-record retries for a batch of failed push outbox ids. Two
/// SQL queries total — one UPDATE (bumps retry_count + sets
/// last_retry_at, guarded by `synced_at IS NULL`) and one SELECT
/// (reads back the new retry_counts keyed by id). Replaces the per-
/// id `record_retry` loop that cost 2N queries under the writer lock.
///
/// Returns a map from outbox_id to `RecordRetryOutcome`. Ids that were
/// not present or were already synced are omitted from the map;
/// callers that need to distinguish "not-retried" from "present but
/// already synced" should do their own pre-check.
pub fn record_many_retries(
    conn: &Connection,
    outbox_ids: &[i64],
    retried_at: &str,
    error: Option<&str>,
) -> Result<std::collections::HashMap<i64, RecordRetryOutcome>, StoreError> {
    // The batch path must mirror the single-row `record_retry`:
    //   - write `error` into `last_error` so batch failures keep
    //     per-row diagnostics for the Diagnostics surface;
    //   - apply same-error escalation so rows repeatedly failing
    //     with the SAME error quarantine at
    //     `SAME_ERROR_ESCALATION_THRESHOLD` instead of burning
    //     through the full retry budget;
    //   - report `exhausted_now` based on a "this call crossed the
    //     threshold for the first time" semantic, not on
    //     `new_retry_count == MAX_RETRIES` (which would falsely fire
    //     on a row whose escalation jump happened in a prior call
    //     and is already at MAX coming in).
    if outbox_ids.is_empty() {
        return Ok(std::collections::HashMap::new());
    }
    // the pre-state SELECT, the bulk UPDATE, and the
    // per-row classification UPDATE must observe the same row set —
    // otherwise a concurrent `mark_synced` (or any other writer that
    // flips `synced_at IS NULL` between the SELECT and the
    // classification loop) would leave the caller unable to
    // distinguish "row not present" from "row already synced". A
    // SAVEPOINT (rather than the outer txn the apply pipeline owns)
    // keeps this primitive callable from any context: it nests
    // cleanly when an outer txn is active and creates an implicit
    // transaction otherwise. Each chunk gets its own SAVEPOINT so a
    // partial failure rolls back cleanly without abandoning earlier
    // chunks.
    const CHUNK: usize = 500;
    let mut out: std::collections::HashMap<i64, RecordRetryOutcome> =
        std::collections::HashMap::with_capacity(outbox_ids.len());
    // Build the placeholder list once for a CHUNK-sized statement.
    // The shape never varies for full chunks, so produce the SQL
    // once and route every chunk through `prepare_cached`. Re-
    // rendering the SQL string per chunk would re-prepare both
    // statements (pre-state SELECT + bulk UPDATE) and pay the
    // prepare cost CHUNKS×2 times. The final partial chunk is
    // handled by sentinel-padding its bind list up to CHUNK using
    // `RECORD_MANY_RETRIES_SENTINEL_ID = -1` — outbox ids come from
    // `INTEGER PRIMARY KEY AUTOINCREMENT` and are strictly
    // positive, so the sentinel can never match a real row in
    // `id IN (...)`. The padded slots are inert.
    let placeholders = lorvex_domain::sql_csv_placeholders(CHUNK);
    let pre_sql = format!(
        "SELECT id, retry_count, last_error \
         FROM sync_outbox \
         WHERE synced_at IS NULL AND id IN ({placeholders})"
    );
    let update_sql = format!(
        "UPDATE sync_outbox \
         SET retry_count = retry_count + 1, \
             last_retry_at = ?, \
             last_error = COALESCE(?, last_error) \
         WHERE synced_at IS NULL AND id IN ({placeholders})"
    );
    for chunk in outbox_ids.chunks(CHUNK) {
        // Route every chunk through the canonical savepoint helper so a
        // panic inside `record_many_retries_chunk` (e.g. allocator OOM
        // mid-`HashMap::insert`) tears the savepoint down before the
        // unwind resumes — the next writer otherwise inherits a
        // dangling `record_many_retries` frame and fails with
        // "no such savepoint" once the outer Mutex recovers from poison.
        with_savepoint(conn, "record_retries", |c| {
            record_many_retries_chunk(c, chunk, retried_at, error, &pre_sql, &update_sql, &mut out)
                .map_err(StoreError::from)
        })?;
    }
    Ok(out)
}

/// (#3054 M7) Sentinel id that fills unused placeholders when the
/// final partial chunk is shorter than `CHUNK`. Outbox rows come from
/// `INTEGER PRIMARY KEY AUTOINCREMENT` and are strictly positive, so
/// a `-1` slot in `id IN (...)` is guaranteed to match nothing — the
/// padded bind values are inert and the prepared SQL string stays
/// stable across every chunk so `prepare_cached` keeps a hit.
fn record_many_retries_chunk(
    conn: &Connection,
    chunk: &[i64],
    retried_at: &str,
    error: Option<&str>,
    pre_sql: &str,
    update_sql: &str,
    out: &mut std::collections::HashMap<i64, RecordRetryOutcome>,
) -> Result<(), rusqlite::Error> {
    // cap the error string before binding it for the
    // bulk UPDATE so the same byte budget the per-row `record_retry`
    // path enforces also covers the batch path. Same-error escalation
    // below uses the truncated form, matching the single-row helper.
    let truncated_error = error.map(truncate_outbox_last_error);
    let error = truncated_error.as_deref();

    // (#3054 M7) Pad the bind list up to CHUNK using the sentinel so
    // the same fixed-shape SQL (cached at prepare time) handles both
    // full and trailing partial chunks.
    const CHUNK: usize = 500;
    let mut padded_ids: [i64; CHUNK] = [RECORD_MANY_RETRIES_SENTINEL_ID; CHUNK];
    for (slot, id) in padded_ids.iter_mut().zip(chunk.iter()) {
        *slot = *id;
    }

    // Snapshot pre-state so we can detect the threshold crossing
    // and run the same-error escalation per row. The `synced_at IS
    // NULL` guard mirrors `record_retry` — already-synced rows are
    // omitted (callers that need to distinguish absent-vs-synced
    // should pre-check).
    {
        let pre_bound: Vec<&dyn rusqlite::ToSql> = padded_ids
            .iter()
            .map(|id| id as &dyn rusqlite::ToSql)
            .collect();
        let mut pre_stmt = conn.prepare_cached(pre_sql)?;
        let pre_rows = pre_stmt.query_map(rusqlite::params_from_iter(pre_bound), |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, i64>(1)?,
                row.get::<_, Option<String>>(2)?,
            ))
        })?;
        let pre: Vec<(i64, i64, Option<String>)> = pre_rows.collect::<Result<_, _>>()?;

        // Bulk UPDATE: bump retry_count, set last_retry_at, and
        // overwrite last_error with the new error (COALESCE keeps the
        // existing message when caller passed `None`).
        let update_bound: Vec<&dyn rusqlite::ToSql> = [
            &retried_at as &dyn rusqlite::ToSql,
            &error as &dyn rusqlite::ToSql,
        ]
        .into_iter()
        .chain(padded_ids.iter().map(|id| id as &dyn rusqlite::ToSql))
        .collect();
        let mut update_stmt = conn.prepare_cached(update_sql)?;
        update_stmt.execute(rusqlite::params_from_iter(update_bound))?;

        // Per-row classification: compute the new retry_count, run the
        // same-error escalation that the single-row `record_retry`
        // applies, and emit the correct `exhausted_now` (true iff the
        // row's pre-call retry_count was below MAX and is now at or
        // above MAX). Keeps the batch's two-statement amortized cost
        // while restoring per-row diagnostics.
        for (id, prev_retry, prev_err) in &pre {
            let mut new_retry = prev_retry + 1;

            let escalates = match (error, prev_err.as_deref()) {
                (Some(err), Some(prev)) if err == prev => {
                    (SAME_ERROR_ESCALATION_THRESHOLD..MAX_RETRIES).contains(&new_retry)
                }
                _ => false,
            };
            if escalates {
                conn.execute(
                    "UPDATE sync_outbox SET retry_count = ?1 WHERE id = ?2",
                    params![MAX_RETRIES, id],
                )?;
                new_retry = MAX_RETRIES;
            }

            let exhausted_now = *prev_retry < MAX_RETRIES && new_retry >= MAX_RETRIES;
            out.insert(
                *id,
                RecordRetryOutcome {
                    new_retry_count: new_retry,
                    exhausted_now,
                },
            );
        }
    }
    Ok(())
}

/// fast-forward a failed outbox row straight to
/// `MAX_RETRIES` when the provider error code proves the failure is
/// permanent (auth revoked, schema mismatch, quota exceeded, etc.).
///
/// Unlike `record_retry`, this helper does NOT increment — it pins
/// `retry_count` to `MAX_RETRIES` in a single statement so the caller
/// can surface the permanent failure immediately instead of letting
/// the row burn through the remaining retry budget on a failure that
/// will never recover.
///
/// Also stores `error` in `last_error` so the diagnostics surface
/// shows the user why the row stalled. Guarded on
/// `synced_at IS NULL` (defense in depth) so an already-synced row
/// cannot be resurrected as permanently-failed by a late callback.
///
/// Returns the new `retry_count` (always `MAX_RETRIES` when the row
/// was present + unsynced; `0` when the row was missing or already
/// synced, matching the `record_retry` fallback semantics).
pub fn mark_permanently_failed(
    conn: &Connection,
    outbox_id: i64,
    error: &str,
) -> Result<i64, rusqlite::Error> {
    // enforce the shared byte budget on `last_error`
    // even on the permanent-failure shortcut path so a provider
    // disqualifying-error string can't bloat the row beyond what the
    // retry path would store.
    let truncated_error = truncate_outbox_last_error(error);
    conn.prepare_cached(
        "UPDATE sync_outbox \
         SET retry_count = ?1, last_error = ?2 \
         WHERE id = ?3 AND synced_at IS NULL",
    )?
    .execute(params![MAX_RETRIES, truncated_error, outbox_id])?;
    let new_count: i64 = conn
        .prepare_cached("SELECT retry_count FROM sync_outbox WHERE id = ?1")?
        .query_row(params![outbox_id], |row| row.get(0))
        .optional()?
        .unwrap_or(0);
    Ok(new_count)
}
/// Reset `retry_count` (and clear `last_retry_at`) on every unsynced
/// outbox row. Used when switching sync transports — the retry counts
/// accumulated under the previous transport are meaningless to the
/// new one, and leaving them in place means rows that were about to
/// be quarantined as "permanently failed" get resurrected for a
/// fresh retry budget on the new transport.
///
/// Rows whose `retry_count` was already bumped to `MAX_RETRIES` by
/// the decode-poison path (see `get_pending`) are explicitly excluded
/// — those are structurally malformed, not transport-failure casualties,
/// and must stay quarantined regardless of which transport is active.
pub fn reset_retry_counts_for_transport_switch(
    conn: &Connection,
) -> Result<usize, rusqlite::Error> {
    let changes = conn
        .prepare_cached(
            "UPDATE sync_outbox \
             SET retry_count = 0, last_retry_at = NULL \
             WHERE synced_at IS NULL \
               AND retry_count < ?1",
        )?
        .execute(rusqlite::params![MAX_RETRIES])?;
    Ok(changes)
}

/// Reset `retry_count`, `last_retry_at`, and `last_error` on a
/// single unsynced outbox row so the user can manually revive a row
/// that has been excluded from `get_pending` by the retry cap. This
/// per-row helper is a targeted "retry now" primitive a Tauri
/// command (and eventually a UI affordance) can invoke; the only
/// alternative is reset-and-reseed, a sledgehammer that wipes the
/// entire outbox.
///
/// The `synced_at IS NULL` guard mirrors every other retry/mark
/// mutation in this module: a row that has already been pushed must
/// not be resurrected as a pending write. Unlike
/// `reset_retry_counts_for_transport_switch`, this helper *does* reset
/// rows at `MAX_RETRIES` — the user is explicitly opting in to retry
/// this specific row, which is the whole point of the command.
///
/// Returns `true` iff a row was updated (row exists and is unsynced).
pub fn reset_row_retry_count(conn: &Connection, outbox_id: i64) -> Result<bool, rusqlite::Error> {
    let changed = conn
        .prepare_cached(
            "UPDATE sync_outbox \
             SET retry_count = 0, last_retry_at = NULL, last_error = NULL \
             WHERE id = ?1 AND synced_at IS NULL",
        )?
        .execute(rusqlite::params![outbox_id])?;
    Ok(changed > 0)
}
