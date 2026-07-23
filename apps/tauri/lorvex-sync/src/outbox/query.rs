use rusqlite::types::Type;
use rusqlite::{params, Connection};

use super::constants::{MAX_PENDING_FETCH, MAX_RETRIES, RECORD_MANY_RETRIES_SENTINEL_ID};
use super::types::OutboxEntry;
use crate::envelope::{SyncEnvelope, SyncOperation};
use lorvex_domain::naming::{OP_DELETE, OP_UPSERT};

pub(super) fn decode_sync_operation(
    operation_str: &str,
    column_index: usize,
) -> Result<SyncOperation, rusqlite::Error> {
    match operation_str {
        OP_DELETE => Ok(SyncOperation::Delete),
        OP_UPSERT => Ok(SyncOperation::Upsert),
        other => Err(rusqlite::Error::FromSqlConversionFailure(
            column_index,
            Type::Text,
            Box::new(std::io::Error::other(format!(
                "invalid sync_outbox operation '{other}'"
            ))),
        )),
    }
}

/// Get all envelopes ready to emit.
///
/// An entry is ready when:
/// - `synced_at` is NULL (not yet pushed), AND
/// - `retry_count < MAX_RETRIES` (not permanently failed)
///
/// Results are ordered by `id ASC` (FIFO).
///
/// previous implementation used
/// `query_map(...).collect::<Result<Vec<_>, _>>()` which short-circuits on
/// the first `Err`. A SINGLE malformed outbox row (unknown operation
/// string, bad column charset, truncated bytes) poisoned every push pass,
/// and since the bad row stayed `synced_at IS NULL AND retry_count <
/// MAX_RETRIES`, it blocked every subsequent run until the provider circuit
/// breaker tripped and sync silently stopped.
///
/// Fix: iterate row-by-row, keep the well-formed rows, and quarantine
/// the bad ones by bumping their `retry_count` to `MAX_RETRIES` (which
/// excludes them from this filter) and recording a diagnostic in the
/// row's `last_error`. Individual row failures no longer abort the
/// whole pass.
pub fn get_pending(conn: &Connection) -> Result<Vec<OutboxEntry>, rusqlite::Error> {
    // Cap the materialized batch at `MAX_PENDING_FETCH`. An unbounded
    // query with a 10k-row backlog would allocate 10k owned
    // `OutboxEntry` values (each carrying up to a 1 MiB payload)
    // inside a single transaction before the push transport saw the
    // first row. The cap keeps the per-pass memory cost flat; the next
    // push cycle drains the next slice (transport callers already
    // re-trigger this on every sync tick). Same chunk-then-loop posture
    // as `record_many_retries`'s `CHUNK = 500` shape.
    //
    // The SQL is fully static, so use `prepare_cached` to amortize the
    // per-cycle parse + plan across every sync tick (transport callers
    // re-trigger this once per push).
    let mut stmt = conn.prepare_cached(
        "SELECT id, entity_type, entity_id, operation, version,
                payload_schema_version, payload, device_id,
                created_at, synced_at, retry_count, last_retry_at
         FROM sync_outbox
         WHERE synced_at IS NULL
           AND retry_count < ?1
         ORDER BY id ASC
         LIMIT ?2",
    )?;

    let rows = stmt.query_map(params![MAX_RETRIES, MAX_PENDING_FETCH], |row| {
        // Read columns defensively so we can quarantine a corrupt row
        // by id without losing the whole batch. The only value we
        // absolutely need to quarantine is `id`; everything else may
        // fail individually.
        let id: Result<i64, rusqlite::Error> = row.get(0);
        let decoded = (|| -> Result<OutboxEntry, rusqlite::Error> {
            let operation_str: String = row.get(3)?;
            let operation = decode_sync_operation(&operation_str, 3)?;
            Ok(OutboxEntry {
                id: row.get(0)?,
                envelope: SyncEnvelope {
                    // parse the SQL TEXT column into the
                    // typed `EntityKind`. The outbox writer always
                    // stores the canonical `as_str()` form, so an
                    // unrecognized value here is a schema-side
                    // invariant violation; surface it as a
                    // FromSqlConversionFailure so the pending-row
                    // catch_unwind harness can quarantine the row.
                    entity_type: {
                        let raw: String = row.get(1)?;
                        lorvex_domain::naming::EntityKind::parse(&raw).ok_or_else(|| {
                            rusqlite::Error::FromSqlConversionFailure(
                                1,
                                rusqlite::types::Type::Text,
                                Box::new(lorvex_domain::naming::UnknownEntityKind(raw)),
                            )
                        })?
                    },
                    entity_id: row.get(2)?,
                    operation,
                    // `version` is typed `Hlc` at the wire
                    // boundary; storage is `TEXT`. Reads parse into the
                    // canonical type, surfacing any taint as a typed
                    // FromSqlConversionFailure (mirrors the
                    // `entity_type` path above).
                    version: {
                        let raw: String = row.get(4)?;
                        lorvex_domain::hlc::Hlc::parse(&raw).map_err(|err| {
                            rusqlite::Error::FromSqlConversionFailure(
                                4,
                                rusqlite::types::Type::Text,
                                Box::new(err),
                            )
                        })?
                    },
                    payload_schema_version: row.get(5)?,
                    payload: row.get(6)?,
                    device_id: row.get(7)?,
                },
                created_at: row.get(8)?,
                synced_at: row.get(9)?,
                retry_count: row.get(10)?,
                last_retry_at: row.get(11)?,
            })
        })();
        Ok((id, decoded))
    })?;

    let mut entries = Vec::new();
    let mut poisoned: Vec<(i64, String)> = Vec::new();
    for row_result in rows {
        // Outer query error (statement-level) — escalate; we can't
        // continue reading.
        let (id_result, decoded) = row_result?;
        match decoded {
            Ok(entry) => entries.push(entry),
            Err(decode_err) => {
                let msg = format!("outbox row decode failed: {decode_err}");
                // durably record the decode failure so
                // Settings → Diagnostics surfaces it. Without this,
                // schema drift that renders outbox rows undecodable
                // left sync silently dead while the UI showed "last
                // synced: just now". The row is then quarantined by
                // bumping retry_count to MAX_RETRIES below, so this
                // error_logs row fires exactly once per bad row.
                crate::error_log::log_sync_error(conn, "sync.outbox.decode", &msg, None);
                // We need an id to quarantine; if even that failed
                // the row is so corrupt we can't target it. The row
                // stays eligible but the error_logs row above means
                // the user can at least see it.
                if let Ok(id) = id_result {
                    poisoned.push((id, msg));
                }
            }
        }
    }

    // Quarantine by bumping retry_count to MAX_RETRIES. Uses a
    // separate statement so the main SELECT has been fully consumed.
    //
    // also stamp the row's `last_error` with the
    // decode failure message. The retention GC (`gc_synced`) gates
    // permanent-failure deletion on `last_error IS NOT NULL` so a
    // crashed quarantine that left a malformed row at MAX_RETRIES
    // without diagnostic context cannot be silently swept after the
    // retention window. The decode message is also persisted to
    // `error_logs` above (the user-visible diagnostics surface), so
    // both rendering surfaces — the row's per-attempt `last_error`
    // and the global feed — agree on the failure cause.
    //
    // The loop must NOT swallow UPDATE failures — a mid-loop UPDATE
    // error that goes unobserved would leave the row in its prior
    // retry state with no `last_error` annotation, and crucially no
    // signal anywhere that the quarantine bookkeeping had failed.
    // Tally each failure and write a single `error_logs` row at the
    // end of the loop so sync stalls remain observable in Settings →
    // Diagnostics.
    if !poisoned.is_empty() {
        let mut update_failures: Vec<(i64, String)> = Vec::new();
        for (id, err_msg) in poisoned {
            if let Err(e) = conn.execute(
                "UPDATE sync_outbox SET retry_count = ?1, last_error = ?2 WHERE id = ?3",
                rusqlite::params![MAX_RETRIES, err_msg, id],
            ) {
                update_failures.push((id, e.to_string()));
            }
        }
        if !update_failures.is_empty() {
            let preview = update_failures
                .iter()
                .take(5)
                .map(|(id, msg)| format!("outbox_id={id}: {msg}"))
                .collect::<Vec<_>>()
                .join("; ");
            let detail = if update_failures.len() > 5 {
                format!("{preview} (+{} more)", update_failures.len() - 5)
            } else {
                preview
            };
            crate::error_log::log_sync_error(
                conn,
                "sync.outbox.quarantine_update_failed",
                &format!(
                    "{count} poisoned-row UPDATE(s) failed during outbox decode; \
                     affected rows stay in their prior retry state without a \
                     last_error annotation",
                    count = update_failures.len()
                ),
                Some(&detail),
            );
        }
    }

    Ok(entries)
}

/// Re-check a selected pending batch against the current
/// outbox state and keep only rows that are STILL dispatchable now.
///
/// This closes the "selector snapshot vs concurrent writer" race: a
/// push cycle may read pending rows, release the DB lock, and only
/// then start transport I/O. If a concurrent push cycle marks a row
/// synced (or a coalescing write replaces it) in that window, the
/// transport still holds an in-memory copy of the old batch.
/// Filtering right before dispatch makes the transport drop any row
/// that was replaced or newly synced after the initial read.
///
/// Takes `entries: Vec<OutboxEntry>` by value and uses
/// `Vec::retain` to drop the no-longer-dispatchable rows in place.
/// entry into a fresh Vec — `OutboxEntry` carries `envelope.payload`
/// which can be up to ~1 MiB per row, so an N-row batch with no
/// undo races still paid up to N MiB of payload-clone allocations
/// on every push cycle. `Vec::retain` shifts the kept elements
/// without reallocating; dropped entries are released in place.
pub fn retain_still_dispatchable(
    conn: &Connection,
    mut entries: Vec<OutboxEntry>,
) -> Result<Vec<OutboxEntry>, rusqlite::Error> {
    if entries.is_empty() {
        return Ok(entries);
    }

    // Apply the sentinel-pad pattern that `record_many_retries_chunk`
    // already uses so every chunk — including the trailing partial
    // one — feeds an identical-shape SQL string into `prepare_cached`,
    // paying parse + plan once per process instead of once per chunk.
    // Outbox ids come from `INTEGER PRIMARY KEY AUTOINCREMENT` and
    // are strictly positive, so a `-1` sentinel slot in
    // `id IN (...)` is guaranteed to match nothing — padded slots
    // are inert.
    //
    // Reviewed under #3368: the alternative is binding only live ids
    // (`?N` with N = live_ids.len()), which would parse the SQL once
    // per length variant. Since `CHUNK` is a fixed compile-time
    // constant here, every call hits the cached prepared statement on
    // the first iteration, and bind cost on the trailing partial
    // chunk's sentinel slots is negligible compared to a fresh parse.
    // Keep the pad. If `CHUNK` ever becomes runtime-variable, switch
    // to the live-id-only form (delete the resize, plumb a dynamic
    // placeholder string) — the trade-off flips at that point.
    const CHUNK: usize = 500;
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        let placeholders = lorvex_domain::sql_csv_placeholders(CHUNK);
        format!(
            "SELECT id FROM sync_outbox
             WHERE synced_at IS NULL
               AND retry_count < ?
               AND id IN ({placeholders})"
        )
    });

    let mut live_ids = std::collections::HashSet::with_capacity(entries.len());
    let mut padded: Vec<i64> = Vec::with_capacity(CHUNK);
    for chunk in entries.chunks(CHUNK) {
        padded.clear();
        padded.extend(chunk.iter().map(|entry| entry.id));
        // pad the trailing partial chunk so the bind count matches
        // the cached statement's placeholder count.
        padded.resize(CHUNK, RECORD_MANY_RETRIES_SENTINEL_ID);

        let mut params: Vec<&dyn rusqlite::ToSql> = Vec::with_capacity(1 + CHUNK);
        params.push(&MAX_RETRIES);
        for id in &padded {
            params.push(id);
        }
        let mut stmt = conn.prepare_cached(sql)?;
        let rows = stmt.query_map(rusqlite::params_from_iter(params), |row| {
            row.get::<_, i64>(0)
        })?;
        for id in rows {
            live_ids.insert(id?);
        }
    }

    entries.retain(|entry| live_ids.contains(&entry.id));
    Ok(entries)
}
