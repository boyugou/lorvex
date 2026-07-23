//! Coalesced enqueue entry point + bounded-retry wrapper.
//!
//! Production callers go through [`enqueue_coalesced`], which wraps
//! [`body::enqueue_coalesced_body`] in a bounded retry loop +
//! per-attempt savepoint to absorb the rare `(entity_type, entity_id)`
//! UNIQUE-partial-index race between concurrent writers. The siblings
//! split the body by concern:
//!
//! - [`types`] — shared row tuple + UNIQUE-violation predicate.
//! - [`stale`] — stale-incoming detection.
//! - [`delete_audit`] — peer-visible audit hop for the
//!   `Upsert → Delete → Upsert` collapse.
//! - [`body`] — single-attempt SELECT → DELETE → INSERT body.

mod body;
mod delete_audit;
mod stale;
mod types;

use rusqlite::Connection;

use self::body::enqueue_coalesced_body;
use self::types::is_unique_constraint_violation;
use crate::envelope::SyncEnvelope;
use crate::outbox::error::OutboxError;

/// Coalesced enqueue: if an unsynced entry for the same `(entity_type,
/// entity_id)` already exists, replace it with the new envelope.
/// Otherwise, insert a new entry.
///
/// Returns `Some(outbox_id)` when a fresh row was inserted (either
/// a first-time enqueue or a replacement of a stale coalesced row),
/// and `None` when the incoming envelope was stale/identical relative
/// to the already-queued row and the existing row was preserved
/// untouched. Callers use the id to wire side-band metadata to the
/// new row.
pub fn enqueue_coalesced(
    conn: &Connection,
    envelope: &SyncEnvelope,
) -> Result<Option<i64>, OutboxError> {
    // every SAVEPOINT site below assumes the caller is
    // already inside an outer transaction (the `BEGIN IMMEDIATE` the
    // apply pipeline / Tauri write surface owns). If a future caller
    // forgets that contract and invokes this on an autocommit handle,
    // the SAVEPOINTs degenerate into independent statements and the
    // per-attempt rollback semantics quietly break. Catch that drift
    // loudly in debug builds.
    debug_assert!(
        !conn.is_autocommit(),
        "enqueue_coalesced requires an outer transaction; \
         the per-attempt SAVEPOINT contract assumes the connection is \
         not in autocommit mode"
    );
    // validate at every enqueue path. See the contract
    // note on `enqueue`; we keep both surfaces in sync so every row
    // landing in `sync_outbox` has cleared the per-field caps and
    // forward-compat headroom.
    if let Err(err) = envelope.validate() {
        return Err(OutboxError::Sql(rusqlite::Error::ToSqlConversionFailure(
            Box::new(std::io::Error::other(format!(
                "sync_outbox coalesced enqueue rejected malformed envelope: {err}"
            ))),
        )));
    }
    // Bounded retry on the UNIQUE-partial-index constraint violation
    // that fires when two writer connections race the SELECT →
    // DELETE → INSERT body. The UNIQUE index
    // `idx_sync_outbox_unsynced_per_entity (entity_type, entity_id)
    // WHERE synced_at IS NULL` is the schema-level safety net: when
    // two writers (Tauri main + MCP server, or two parallel MCP
    // commands) both pass the SELECT, both DELETE zero rows, and
    // both INSERT, the second INSERT hard-errors with
    // `SQLITE_CONSTRAINT_UNIQUE`. Without a retry, that error would
    // poison the caller's transaction — visible to the user as
    // "writes pile up
    // but never push." The retry loop wraps the body so the second
    // pass re-runs the SELECT (now seeing the racing writer's row),
    // which lets the LWW gate at the top of the body decide
    // correctly between "preserve the existing row" and "replace
    // it." A small bounded retry budget guards against pathological
    // live-lock; in practice the loop fires at most once.
    const MAX_CONFLICT_RETRIES: u32 = 3;
    let mut attempt: u32 = 0;
    loop {
        // Wrap each attempt in a per-attempt SAVEPOINT so a
        // UNIQUE-constraint failure mid-body rolls back EVERY write
        // the failed attempt made — most critically the SELECT →
        // DELETE → INSERT body's DELETE of the prior unsynced row.
        // Without the SAVEPOINT, a colliding INSERT inside the outer
        // enclosing transaction would leave the racing row already
        // deleted when the retry's SELECT runs.
        //
        // Routes through `lorvex_store::transaction::with_savepoint_mapped`
        // so a panic inside `enqueue_coalesced_body` (e.g. an
        // assertion fault on a malformed in-flight row) rolls the
        // savepoint back BEFORE the unwind resumes, matching the
        // panic-safety contract every other savepoint site in the
        // sync pipeline uses.
        let attempt_result = lorvex_store::transaction::with_savepoint_mapped(
            conn,
            "enqueue_coalesce_attempt",
            OutboxError::Internal,
            |conn| enqueue_coalesced_body(conn, envelope),
        );
        match attempt_result {
            Ok(out) => return Ok(out),
            Err(OutboxError::Sql(err)) if is_unique_constraint_violation(&err) => {
                // Helper already rolled the savepoint back; the next
                // attempt's SELECT sees the racing row.
                attempt += 1;
                if attempt > MAX_CONFLICT_RETRIES {
                    lorvex_store::error_log::append_error_log_best_effort(
                        conn,
                        "sync.outbox.coalesce_conflict_retry_exhausted",
                        &format!(
                            "outbox coalesce hit UNIQUE constraint after {attempt} retries for \
                             entity_type={}, entity_id={}",
                            envelope.entity_type, envelope.entity_id
                        ),
                        None,
                        Some("error"),
                    );
                    // Surface a typed `ContentionExhausted` so the
                    // caller can render a retry affordance instead of
                    // showing a generic SQL error toast (#4583 B20).
                    // The underlying SQLITE_CONSTRAINT_UNIQUE is now
                    // an implementation detail of the retry loop, not
                    // a leak across the outbox boundary.
                    let _ = err; // preserved for diagnostics via the log line above
                    return Err(OutboxError::ContentionExhausted {
                        entity_type: envelope.entity_type,
                        entity_id: envelope.entity_id.clone(),
                        attempts: attempt,
                    });
                }
            }
            Err(err) => {
                // Non-UNIQUE error (or `TaintedVersion` boundary
                // refusal). The helper already rolled back; just
                // propagate.
                return Err(err);
            }
        }
    }
}
