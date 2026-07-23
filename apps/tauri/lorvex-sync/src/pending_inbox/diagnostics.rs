use rusqlite::{params, Connection, OptionalExtension};

use super::quarantine::record_quarantine;
use super::store::remove_pending;
use super::types::PendingInboxEntry;
use crate::apply::ApplyError;
use crate::conflict_log::{log_conflict, ConflictLogEntry};
use crate::envelope::SyncEnvelope;
use crate::error::SyncError;
use lorvex_domain::naming;

/// Promote an unparseable pending row to a permanent `EXHAUSTED`
/// conflict and remove it from the inbox.
///
/// The conflict_log entry is synthesized from the persisted identity
/// columns (`envelope_entity_type` / `envelope_entity_id` /
/// `envelope_version`) so the diagnostic surface still records the
/// poisoned identity even when the envelope body itself is corrupt
/// JSON. `loser_payload` carries the raw `envelope` JSON blob (still
/// useful for forensic recovery — the bytes are a deserialization
/// failure, not necessarily an unrecoverable scramble) capped at the
/// usual conflict_log size budget.
pub(super) fn quarantine_unparseable_entry(conn: &Connection, id: i64) -> Result<(), SyncError> {
    let row: Option<(String, String, String, String)> = conn
        .query_row(
            "SELECT envelope_entity_type, envelope_entity_id, envelope_version, envelope
             FROM sync_pending_inbox WHERE id = ?1",
            params![id],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                ))
            },
        )
        .optional()?;
    let Some((entity_type, entity_id, version, envelope_json)) = row else {
        // Row vanished between the drain SELECT and this UPDATE —
        // a concurrent writer (e.g. `gc_expired_entries`) won the race;
        // nothing to do.
        return Ok(());
    };
    log_conflict(
        conn,
        &ConflictLogEntry {
            id: 0,
            entity_type: std::borrow::Cow::Owned(entity_type.clone()),
            entity_id: entity_id.clone(),
            winner_version: String::new(),
            loser_version: version.clone(),
            loser_device_id: String::new(),
            loser_payload: Some(envelope_json),
            resolved_at: lorvex_domain::sync_timestamp_now(),
            resolution_type: std::borrow::Cow::Borrowed(naming::RESOLUTION_PENDING_INBOX_EXHAUSTED),
        },
    )?;
    // mirror the enqueue-side blocklist write so a
    // poison redelivery short-circuits at the next `enqueue_pending`
    // call instead of climbing the retry ladder again. The
    // unparseable-entry branch is reached when the envelope JSON
    // itself failed to deserialize, so a future redelivery of the
    // same identity is just as poisoned and benefits from the
    // same suppression.
    record_quarantine(conn, &entity_type, &entity_id, &version)?;
    remove_pending(conn, id)?;
    Ok(())
}
pub(super) fn sync_error_for_pending_apply_failure(
    entry_id: i64,
    envelope: &SyncEnvelope,
    error: ApplyError,
) -> SyncError {
    match error {
        ApplyError::TransactionRequired => SyncError::Envelope(format!(
            "pending inbox entry {entry_id} ({}/{}) attempted apply without an outer transaction",
            envelope.entity_type, envelope.entity_id
        )),
        ApplyError::Db(error) => SyncError::Sql(error),
        ApplyError::InvalidVersion(message) => SyncError::Envelope(format!(
            "pending inbox entry {entry_id} ({}/{}) has invalid version: {message}",
            envelope.entity_type, envelope.entity_id
        )),
        ApplyError::UnknownEntityType(entity_type) => SyncError::Envelope(format!(
            "pending inbox entry {entry_id} ({}/{}) has unknown entity type {entity_type}",
            envelope.entity_type, envelope.entity_id
        )),
        ApplyError::InvalidPayload(message) => SyncError::Envelope(format!(
            "pending inbox entry {entry_id} ({}/{}) has invalid payload: {message}",
            envelope.entity_type, envelope.entity_id
        )),
        ApplyError::Store(store_err) => SyncError::Store(store_err),
        ApplyError::TombstoneRedirectCycle {
            entity_type,
            entity_id,
        } => SyncError::Envelope(format!(
            "pending inbox entry {entry_id} ({}/{}) hit a tombstone redirect cycle resolving to {entity_type} {entity_id}",
            envelope.entity_type, envelope.entity_id
        )),
        // a chain longer than `REDIRECT_CHAIN_CAP`
        // is structurally distinct from a cycle — the chain is
        // simply deeper than the apply pipeline is willing to
        // chase. Surface enough context that the diagnostics
        // surface can name the deepest hop reached.
        ApplyError::TombstoneRedirectChainTooDeep {
            entity_type,
            entity_id,
            chain_length,
            terminal_id,
        } => SyncError::Envelope(format!(
            "pending inbox entry {entry_id} ({}/{}) hit a tombstone redirect chain of {chain_length}+ hops \
             resolving from {entity_type} {entity_id} (terminal id {terminal_id}) — refusing to apply",
            envelope.entity_type, envelope.entity_id
        )),
        ApplyError::InvalidOperation {
            entity_type,
            operation,
        } => SyncError::Envelope(format!(
            "pending inbox entry {entry_id} ({}/{}) carried an invalid operation '{operation}' for entity type '{entity_type}'",
            envelope.entity_type, envelope.entity_id
        )),
        // A redirect-chase rewrite that grew past the raw-payload
        // cap. The payload itself is structurally over-sized (wire
        // boundary), but for routing it like the other envelope-
        // shape failures use `Envelope` — the wire encoder maps
        // both to non-retryable, and unifying lets us delete the
        // free-form `Serialization(String)` variant entirely.
        ApplyError::RedirectPayloadTooLarge {
            entity_type,
            entity_id,
            size_bytes,
        } => SyncError::Envelope(format!(
            "pending inbox entry {entry_id} ({}/{}) hit redirect-chase payload-size cap: \
             remapped to {entity_type} {entity_id}, canonical re-serialization is {size_bytes} bytes",
            envelope.entity_type, envelope.entity_id
        )),
    }
}
pub(super) fn should_log_stalled(
    conn: &Connection,
    entry: &PendingInboxEntry,
    envelope: &SyncEnvelope,
) -> Result<bool, rusqlite::Error> {
    let older_than_one_hour: bool = conn.query_row(
        "SELECT ?1 < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-1 hour')",
        params![entry.first_attempted_at],
        |row| row.get(0),
    )?;
    if !older_than_one_hour {
        return Ok(false);
    }

    let already_logged: bool = conn.query_row(
        "SELECT EXISTS(
            SELECT 1
            FROM sync_conflict_log
            WHERE resolution_type = ?1
              AND entity_type = ?2
              AND entity_id = ?3
              AND loser_version = ?4
         )",
        params![
            naming::RESOLUTION_FK_STALLED,
            envelope.entity_type.as_str(),
            envelope.entity_id,
            envelope.version.to_string(),
        ],
        |row| row.get(0),
    )?;
    Ok(!already_logged)
}

pub(super) fn log_fk_stalled(
    conn: &Connection,
    envelope: &SyncEnvelope,
) -> Result<(), rusqlite::Error> {
    log_conflict(
        conn,
        &ConflictLogEntry {
            id: 0,
            entity_type: std::borrow::Cow::Borrowed(envelope.entity_type.as_str()),
            entity_id: envelope.entity_id.clone(),
            winner_version: String::new(),
            loser_version: envelope.version.to_string(),
            loser_device_id: envelope.device_id.clone(),
            loser_payload: Some(envelope.payload.clone()),
            resolved_at: lorvex_domain::sync_timestamp_now(),
            resolution_type: std::borrow::Cow::Borrowed(naming::RESOLUTION_FK_STALLED),
        },
    )
}

pub(super) fn log_fk_unresolved_discard(
    conn: &Connection,
    envelope: &SyncEnvelope,
    winner_version: &str,
) -> Result<(), rusqlite::Error> {
    log_conflict(
        conn,
        &ConflictLogEntry {
            id: 0,
            entity_type: std::borrow::Cow::Borrowed(envelope.entity_type.as_str()),
            entity_id: envelope.entity_id.clone(),
            winner_version: winner_version.to_string(),
            loser_version: envelope.version.to_string(),
            loser_device_id: envelope.device_id.clone(),
            loser_payload: Some(envelope.payload.clone()),
            resolved_at: lorvex_domain::sync_timestamp_now(),
            resolution_type: std::borrow::Cow::Borrowed(naming::RESOLUTION_FK_UNRESOLVED),
        },
    )
}
