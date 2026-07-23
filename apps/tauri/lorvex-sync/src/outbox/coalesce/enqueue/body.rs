//! Single-attempt SELECT → DELETE → INSERT body of the coalesced
//! enqueue. The bounded-retry wrapper lives in
//! [`super::enqueue_coalesced`]; this module owns the LWW decision and
//! the row replacement.

use rusqlite::{params, Connection, OptionalExtension};

use super::delete_audit::record_coalesced_delete_dropped;
use super::stale::incoming_is_stale;
use super::types::ExistingOutboxRow;
use crate::envelope::{SyncEnvelope, SyncOperation};
use crate::outbox::error::OutboxError;
use lorvex_domain::naming::{OP_DELETE, OP_UPSERT};

pub(super) fn enqueue_coalesced_body(
    conn: &Connection,
    envelope: &SyncEnvelope,
) -> Result<Option<i64>, OutboxError> {
    // SELECT → DELETE → INSERT must coalesce
    // atomically. Two layers of defense:
    //   1. Production callers wrap this inside a transaction (the
    //      `enqueue_payload_internal` debug_assert enforces this on
    //      that surface, which is the only production caller).
    //   2. The UNIQUE partial index `idx_sync_outbox_unsynced_per_entity`
    //      on (entity_type, entity_id) WHERE synced_at IS NULL gives
    //      schema-level enforcement: even if two non-transactional
    //      enqueues raced, the second INSERT would fail rather than
    //      producing a duplicate unsynced row that violates the
    //      single-coalesce invariant. The bounded-retry wrapper in
    //      this function catches the constraint violation so it no
    //      longer poisons the caller's transaction.
    let operation_str = match &envelope.operation {
        SyncOperation::Upsert => OP_UPSERT,
        SyncOperation::Delete => OP_DELETE,
    };

    // Read the existing row's version + operation BEFORE deleting. We
    // need the version for the LWW guard (#2231) and the operation so
    // the H4 audit-trail check below can detect the `Upsert(T1) →
    // Delete(T2) → Upsert(T3)` collapse — i.e. an Upsert that's about
    // to overwrite a queued Delete. The Delete envelope's intent (the
    // cluster wanted the row gone at T2, even if we resurrect at T3)
    // must not be silently dropped: peer audit consumers that
    // reconstruct lifecycle from ai_changelog need a record of every
    // Delete that was ever emitted, not just the final state of the
    // outbox queue.
    let existing: Option<ExistingOutboxRow> = conn
        .prepare_cached(
            "SELECT version, operation FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2 AND synced_at IS NULL
             LIMIT 1",
        )?
        .query_row(
            params![envelope.entity_type.as_str(), envelope.entity_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()?;

    // Guard the coalesce against a stale-snapshot enqueue. An
    // unconditional DELETE of the existing row would let a caller
    // who stamped an older HLC than a concurrently queued newer
    // edit (e.g. a finalize step re-reading task state that was
    // just updated by another transaction) silently discard the
    // newer edit.
    //
    // Prefer typed `Hlc::parse` over a raw byte
    // compare. Today's HLC strings are fixed-width and lex-ordered
    // so the byte compare yields the right answer, but a malformed
    // version (legacy data, future schema bug, hand-edited DB)
    // could make the coalesce decision flip silently. Mirrors the
    // tolerance pattern in `apply_envelope` (lines ~711-728): when
    // either side fails to parse, fall back to the byte compare so
    // we don't trip a panic on a corrupted-but-fixable row, but log
    // the corruption when we can.
    if let Some((existing_version, _existing_op)) = existing.as_ref() {
        if incoming_is_stale(conn, envelope, existing_version) {
            return Ok(None);
        }
    }

    if let Some(existing_row) = existing.as_ref() {
        record_coalesced_delete_dropped(conn, envelope, existing_row);
    }

    // Delete the existing unsynced entry.
    conn.prepare_cached(
        "DELETE FROM sync_outbox
         WHERE entity_type = ?1 AND entity_id = ?2 AND synced_at IS NULL",
    )?
    .execute(params![envelope.entity_type.as_str(), envelope.entity_id])?;

    // Insert the replacement. Audit #2245: use the canonical
    // millisecond timestamp helper (see
    // `lorvex-domain/src/time/sync_timestamp.rs`) instead of the sqlite
    // default so every outbox row shares one format.
    let now = lorvex_domain::sync_timestamp_now();
    conn.prepare_cached(
        "INSERT INTO sync_outbox
            (entity_type, entity_id, operation, version,
             payload_schema_version, payload, device_id, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
    )?
    .execute(params![
        envelope.entity_type.as_str(),
        envelope.entity_id,
        operation_str,
        envelope.version.to_string(),
        envelope.payload_schema_version,
        envelope.payload,
        envelope.device_id,
        now,
    ])?;
    Ok(Some(conn.last_insert_rowid()))
}
