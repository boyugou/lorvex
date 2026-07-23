use rusqlite::{params, Connection};

use crate::envelope::{SyncEnvelope, SyncOperation};
use lorvex_domain::naming::{OP_DELETE, OP_UPSERT};

use super::error::OutboxError;

/// Enqueue a sync event to the outbox.
///
/// Every enqueue path runs `envelope.validate()` so the per-field caps
/// (`MAX_ENVELOPE_PAYLOAD_BYTES`, `MAX_ENVELOPE_DEVICE_ID_LEN`, the
/// `payload_schema_version` headroom, etc.) are enforced at every
/// entry into `sync_outbox`. Today's production callers (the
/// `outbox_enqueue` orchestrator, sync replay tools) all build
/// envelopes from in-process state, but a future audit / re-emit
/// utility that loads raw bytes off disk would otherwise slip a
/// malformed envelope straight into the outbox and remote-provider /
/// filesystem-bridge push. Validation is cheap (substring + length
/// checks); failures map into `rusqlite::Error::InvalidQuery` so the
/// caller's existing error surface continues to work without a new
/// error type.
pub fn enqueue(conn: &Connection, envelope: &SyncEnvelope) -> Result<(), OutboxError> {
    if let Err(err) = envelope.validate() {
        return Err(OutboxError::Sql(rusqlite::Error::ToSqlConversionFailure(
            Box::new(std::io::Error::other(format!(
                "sync_outbox enqueue rejected malformed envelope: {err}"
            ))),
        )));
    }
    let operation_str = match &envelope.operation {
        SyncOperation::Upsert => OP_UPSERT,
        SyncOperation::Delete => OP_DELETE,
    };
    // write `created_at` explicitly with the canonical
    // millisecond RFC-3339 form via `sync_timestamp_now()` (see
    // `lorvex-domain/src/time/sync_timestamp.rs`) instead of letting the DB's
    // own DEFAULT fire. Mixing formats within the same table makes
    // payload-canonicalization hashes differ for rows written via
    // different code paths, and breaks exact-string equality in
    // export roundtrip tests.
    let now = lorvex_domain::sync_timestamp_now();
    // `prepare_cached` so the parsed plan amortizes across every MCP
    // tool call's per-entity outbox enqueue (often 2-5× per call —
    // the single hottest write-path SQL in the system).
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
    Ok(())
}
