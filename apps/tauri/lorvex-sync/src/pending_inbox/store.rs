use rusqlite::{params, Connection, OptionalExtension};

use super::types::PendingInboxEntry;
use crate::envelope::SyncEnvelope;
use crate::error::SyncError;

/// per-entry retry cap. Without this, an envelope whose
/// FK target never arrives (e.g., parent tombstone that was GC'd before
/// the child envelope could be applied) re-tries forever until the
/// horizon expiry triggers a full reseed — which is a much heavier
/// hammer than giving up on a single entry. Drains are infrequent, so
/// 50 attempts is generous: even at one drain/hour that's two days of
/// retries before the entry is shed.
///
/// Outbox uses `MAX_RETRIES = 10` (failed-push per envelope); pending
/// inbox was the only retry surface without a cap.
pub(super) const MAX_PENDING_INBOX_ATTEMPTS: i64 = 50;
/// Fetch a single pending row by id.
///
/// The drain loop snapshots only candidate ids, then calls this helper
/// just before processing each one. If a prior entry's apply removed a
/// later row as a side effect, this returns `None` and the drain skips
/// it instead of using stale envelope/attempt metadata.
pub(super) fn pending_entry_by_id(
    conn: &Connection,
    id: i64,
) -> Result<Option<PendingInboxEntry>, rusqlite::Error> {
    conn.prepare_cached(
        "SELECT id, envelope, reason, missing_entity_type, missing_entity_id,
                first_attempted_at, last_attempted_at, attempt_count
         FROM sync_pending_inbox
         WHERE id = ?1
         LIMIT 1",
    )?
    .query_row(params![id], PendingInboxEntry::from_row)
    .optional()
}

pub(super) fn pending_entry_ids_for_drain(
    conn: &Connection,
    limit: usize,
) -> Result<Vec<i64>, rusqlite::Error> {
    let mut stmt = conn.prepare_cached(
        "SELECT id
         FROM sync_pending_inbox
         ORDER BY last_attempted_at ASC, id ASC
         LIMIT ?1",
    )?;
    let rows = stmt.query_map(params![limit as i64], |row| row.get::<_, i64>(0))?;
    rows.collect()
}

/// Get all pending envelopes for re-attempt.
///
/// Results are ordered by `id ASC` (FIFO, preserving original arrival order).
pub fn get_all_pending(conn: &Connection) -> Result<Vec<PendingInboxEntry>, rusqlite::Error> {
    // The SQL is fully static and this helper drains at every apply
    // cycle plus startup, so use `prepare_cached` to amortize the
    // parse + plan across the process lifetime instead of paying it
    // every drain.
    let mut stmt = conn.prepare_cached(
        "SELECT id, envelope, reason, missing_entity_type, missing_entity_id,
                first_attempted_at, last_attempted_at, attempt_count
         FROM sync_pending_inbox
         ORDER BY id ASC",
    )?;

    let rows = stmt.query_map([], PendingInboxEntry::from_row)?;

    rows.collect()
}

/// Remove a successfully resolved pending entry.
pub fn remove_pending(conn: &Connection, id: i64) -> Result<(), rusqlite::Error> {
    conn.prepare_cached("DELETE FROM sync_pending_inbox WHERE id = ?1")?
        .execute(params![id])?;
    Ok(())
}

/// Check if any pending entries have expired (version older than `horizon_days`).
///
/// An expired pending entry means incremental sync cannot resolve the missing
/// dependency. Per spec: this triggers `reseed_required` state on the transport.
///
/// This checks `first_attempted_at` against the horizon since the envelope's
/// version is embedded in the JSON payload and we want to avoid parsing it for
/// a lightweight check. The first attempt timestamp is a conservative proxy.
///
/// `first_attempted_at` is a wall-clock proxy for the
/// envelope's HLC age, not a perfect substitute. A pathological case
/// is a *fresh-HLC* envelope (new write, just authored by a peer)
/// that arrives stuck on a missing dependency: its
/// `first_attempted_at` is recent, so this check correctly does NOT
/// flag it as expired (the dep can still arrive). The opposite — an
/// *old-HLC* envelope re-delivered after the horizon — would also
/// correctly trigger reseed because the row's `first_attempted_at`
/// would have aged past the horizon. The only edge case the proxy
/// misclassifies is a brand-new local row whose
/// `first_attempted_at` was somehow backdated (clock skew, manual
/// DB edit), which is not a real production scenario. If a future
/// hardening pass needs version-aware expiry, the typed identity
/// columns added in #2909-H1 (`envelope_version`) would let us
/// parse and compare HLC directly without re-deserializing the
/// full envelope JSON.
pub fn has_expired_entries(conn: &Connection, horizon_days: u32) -> Result<bool, rusqlite::Error> {
    let count: i64 = conn
        .prepare_cached(
            "SELECT COUNT(*) FROM sync_pending_inbox
             WHERE first_attempted_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?1)",
        )?
        .query_row(params![format!("-{horizon_days} days")], |row| row.get(0))?;
    Ok(count > 0)
}

/// Delete pending-inbox rows older than `horizon_days`. These will never
/// succeed on re-drain (their parent entity has not arrived in the horizon
/// window) and accumulate forever otherwise. Without this,
/// orphan envelopes from a previous sync session stayed in the table
/// indefinitely even after sync was disabled.
///
/// Also GCs the `sync_quarantine_blocklist` (#3028-H3) on the same
/// horizon. The blocklist exists to short-circuit poison-envelope
/// redeliveries; once a row's `quarantined_at` is older than the
/// horizon, any future replay of the same identity should get a fresh
/// shot — the FK target may have arrived via a reseed, the schema may
/// have caught up, or the user may have toggled sync off and back on.
/// Pinning the blocklist horizon to the same window as the inbox keeps
/// both surfaces' GC discipline aligned and prevents permanent
/// shadow-banning of legitimate envelopes.
///
/// Returns the number of pending-inbox rows deleted (the blocklist
/// sweep is best-effort and not folded into the count, so callers
/// keep reporting the same metric they did pre-blocklist).
pub fn gc_expired_entries(conn: &Connection, horizon_days: u32) -> Result<usize, rusqlite::Error> {
    let deleted = conn
        .prepare_cached(
            "DELETE FROM sync_pending_inbox \
             WHERE first_attempted_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?1)",
        )?
        .execute(params![format!("-{horizon_days} days")])?;
    // GC blocklist on the same horizon. Errors are logged via the
    // best-effort error_log channel rather than propagated — a
    // transient blocklist-GC failure should not abort the inbox GC
    // pass that the caller cares about.
    if let Err(err) = conn
        .prepare_cached(
            "DELETE FROM sync_quarantine_blocklist \
             WHERE quarantined_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?1)",
        )
        .and_then(|mut stmt| stmt.execute(params![format!("-{horizon_days} days")]))
    {
        lorvex_store::error_log::append_error_log_best_effort(
            conn,
            "sync.pending_inbox.blocklist_gc",
            &format!("sync_quarantine_blocklist GC failed at horizon={horizon_days}d: {err}"),
            None,
            Some("warn"),
        );
    }
    Ok(deleted)
}

/// Increment the attempt count and update `last_attempted_at` for a re-attempt.
///
/// Used for the deferral and FK-stalled paths where there is no
/// failure-class error message to remember. Leaves `last_error`
/// untouched (so a previously-recorded error remains the dedup key
/// for the next failed drain).
pub fn record_reattempt(conn: &Connection, id: i64) -> Result<(), rusqlite::Error> {
    conn.prepare_cached(
        "UPDATE sync_pending_inbox
         SET attempt_count = attempt_count + 1,
             last_attempted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
         WHERE id = ?1",
    )?
    .execute(params![id])?;
    Ok(())
}

/// Read the post-write `attempt_count` for a pending row.
///
/// The cap-discard branches must gate on the on-disk value rather than
/// `entry.attempt_count + 1` arithmetic — `record_reattempt` /
/// `record_reattempt_with_error` write `attempt_count + 1` directly via
/// SQL, so a concurrent drain or a missed bump path can drift the
/// snapshot from the row's truth. Returns `None` when
/// the row has been deleted out from under us (treated as "no cap to
/// enforce" by the caller — the row is already gone).
pub(super) fn read_attempt_count(
    conn: &Connection,
    id: i64,
) -> Result<Option<i64>, rusqlite::Error> {
    conn.prepare_cached("SELECT attempt_count FROM sync_pending_inbox WHERE id = ?1")?
        .query_row(params![id], |row| row.get(0))
        .optional()
}

/// re-record `last_attempted_at` WITHOUT bumping
/// `attempt_count`. Used when the apply attempt failed with a
/// classified-as-transient error (`SQLITE_BUSY` / `SQLITE_LOCKED`)
/// — those failures are caused by another writer holding the DB
/// lock, not by anything wrong with the envelope itself, so they
/// must NOT push the entry toward the [`MAX_PENDING_INBOX_ATTEMPTS`]
/// cap that triggers permanent discard. The `last_attempted_at`
/// timestamp still moves forward so the drain stays observable in
/// diagnostics.
pub fn record_reattempt_busy(conn: &Connection, id: i64) -> Result<(), rusqlite::Error> {
    conn.prepare_cached(
        "UPDATE sync_pending_inbox
         SET last_attempted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
         WHERE id = ?1",
    )?
    .execute(params![id])?;
    Ok(())
}

/// Like [`record_reattempt`] but also records the most recent error
/// message into `last_error`. Returns the `last_error` value that was
/// stored on the row BEFORE this update — callers use it to dedup
/// `error_logs` writes (see M5).
pub fn record_reattempt_with_error(
    conn: &Connection,
    id: i64,
    new_error: &str,
) -> Result<Option<String>, rusqlite::Error> {
    // Read-then-write ordering: the prior error must be captured BEFORE
    // we overwrite it, otherwise the dedup compares the row's new
    // value against itself.
    let prior: Option<String> = conn
        .prepare_cached("SELECT last_error FROM sync_pending_inbox WHERE id = ?1")?
        .query_row(params![id], |row| row.get(0))
        .optional()?
        .flatten();
    conn.prepare_cached(
        "UPDATE sync_pending_inbox
         SET attempt_count = attempt_count + 1,
             last_attempted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
             last_error = ?2
         WHERE id = ?1",
    )?
    .execute(params![id, new_error])?;
    Ok(prior)
}

/// Bump a pending entry's `attempt_count` to (at least) `target`, leaving
/// `last_attempted_at` updated. Used by the drain's unparseable-envelope
/// branch to push a poisonous row toward the
/// [`MAX_PENDING_INBOX_ATTEMPTS`] cap so that the next
/// `enqueue_pending` for the same identity (or the next drain pass)
/// promotes it to an `EXHAUSTED` conflict and removes it.
///
/// The `MAX(attempt_count, ?2)` guard is defensive — if a previous
/// drain already saw the same poison row, we don't want to ratchet
/// the count back down.
pub(super) fn bump_attempt_count_to_cap(
    conn: &Connection,
    id: i64,
    target: i64,
) -> Result<(), rusqlite::Error> {
    conn.prepare_cached(
        "UPDATE sync_pending_inbox
         SET attempt_count = MAX(attempt_count, ?2),
             last_attempted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
         WHERE id = ?1",
    )?
    .execute(params![id, target])?;
    Ok(())
}

/// Get the count of pending inbox entries.
pub fn count_pending(conn: &Connection) -> Result<u64, rusqlite::Error> {
    let count: i64 = conn
        .prepare_cached("SELECT COUNT(*) FROM sync_pending_inbox")?
        .query_row([], |row| row.get(0))?;
    Ok(count as u64)
}

/// returns `true` iff any pending inbox row is waiting
/// on the just-created `(entity_type, entity_id)` FK target. The
/// outbox-enqueue path (`outbox_enqueue::enqueue_payload_internal`)
/// calls this after a successful local Upsert so a child envelope that
/// was deferred for a missing parent gets a chance to drain in the
/// same transaction the parent landed in.
/// after each REMOTE apply batch (`apply_remote_sync_records_with
/// _checkpoint_writer`), so a user who locally created the missing
/// parent (e.g. via the UI or MCP) saw the child stall in the inbox
/// for one to several seconds until the next remote pull triggered a
/// drain — visible to the user as "I just made the parent, why does
/// the child still say 'waiting'?".
///
/// The check is a single indexed lookup against the `missing_entity_*`
/// columns and bails on the first match, so the per-write cost is
/// negligible compared to a blind unconditional drain (which would
/// re-iterate every pending row on every local write, including the
/// many writes whose entity_id matches no pending dependency).
pub fn has_pending_for_target(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
) -> Result<bool, rusqlite::Error> {
    let exists: Option<i64> = conn
        .query_row(
            "SELECT 1 FROM sync_pending_inbox \
             WHERE missing_entity_type = ?1 AND missing_entity_id = ?2 \
             LIMIT 1",
            params![entity_type, entity_id],
            |row| row.get(0),
        )
        .optional()?;
    Ok(exists.is_some())
}
pub(super) fn update_pending_entry(
    conn: &Connection,
    id: i64,
    envelope: &SyncEnvelope,
    reason: &str,
    missing_entity_type: Option<&str>,
    missing_entity_id: Option<&str>,
) -> Result<i64, SyncError> {
    let envelope_json = serde_json::to_string(envelope)?;
    let envelope_version = envelope.version.to_string();
    // Identity columns track the *current* envelope: when drain remaps
    // a composite-edge entry through a tombstone redirect, the envelope
    // body changes and so does its (entity_type, entity_id, version)
    // triple. Keeping the identity columns in sync ensures a subsequent
    // enqueue of the post-remap identity coalesces with this row via
    // the UNIQUE index instead of creating a duplicate.
    let collision_id: Option<i64> = conn
        .prepare_cached(
            "SELECT id FROM sync_pending_inbox
             WHERE envelope_entity_type = ?1
               AND envelope_entity_id = ?2
               AND envelope_version = ?3
               AND id <> ?4
             LIMIT 1",
        )?
        .query_row(
            params![
                envelope.entity_type.as_str(),
                envelope.entity_id,
                envelope_version.as_str(),
                id,
            ],
            |row| row.get(0),
        )
        .optional()?;

    if let Some(collision_id) = collision_id {
        conn.prepare_cached(
            "UPDATE sync_pending_inbox
             SET envelope = ?2,
                 reason = ?3,
                 missing_entity_type = COALESCE(?4, missing_entity_type),
                 missing_entity_id = COALESCE(?5, missing_entity_id),
                 first_attempted_at = MIN(
                     first_attempted_at,
                     (SELECT first_attempted_at FROM sync_pending_inbox WHERE id = ?1)
                 ),
                 last_attempted_at = MAX(
                     last_attempted_at,
                     (SELECT last_attempted_at FROM sync_pending_inbox WHERE id = ?1)
                 ),
                 attempt_count = MAX(
                     attempt_count,
                     (SELECT attempt_count FROM sync_pending_inbox WHERE id = ?1)
                 ),
                 last_error = COALESCE(
                     last_error,
                     (SELECT last_error FROM sync_pending_inbox WHERE id = ?1)
                 )
             WHERE id = ?6",
        )?
        .execute(params![
            id,
            envelope_json,
            reason,
            missing_entity_type,
            missing_entity_id,
            collision_id,
        ])?;
        remove_pending(conn, id)?;
        return Ok(collision_id);
    }

    conn.prepare_cached(
        "UPDATE sync_pending_inbox
         SET envelope = ?2,
             reason = ?3,
             missing_entity_type = ?4,
             missing_entity_id = ?5,
             envelope_entity_type = ?6,
             envelope_entity_id = ?7,
             envelope_version = ?8
         WHERE id = ?1",
    )?
    .execute(params![
        id,
        envelope_json,
        reason,
        missing_entity_type,
        missing_entity_id,
        envelope.entity_type.as_str(),
        envelope.entity_id,
        envelope_version.as_str(),
    ])?;
    Ok(id)
}
