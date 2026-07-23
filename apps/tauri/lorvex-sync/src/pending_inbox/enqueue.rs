use rusqlite::{params, Connection};

use super::quarantine::{is_quarantined, record_quarantine};
use super::store::MAX_PENDING_INBOX_ATTEMPTS;
use crate::apply::DeferralReason;
use crate::conflict_log::{log_conflict, ConflictLogEntry};
use crate::envelope::SyncEnvelope;
use crate::error::SyncError;
use lorvex_domain::naming;

/// Add an unresolved envelope to the pending inbox.
///
/// The `envelope` is serialized to JSON for durable storage.
///
/// the stored `payload` is whatever string the caller
/// passed in. In production every caller is the apply pipeline,
/// which has already round-tripped the payload through
/// `canonicalize::canonicalize_json` at the outbox boundary on the
/// authoring side — so the bytes that arrive here are the canonical
/// form a peer would emit. The defense-in-depth check below
/// (`canonicalize_json(&payload_value)`) re-parses the payload to
/// validate it conforms to `MAX_JSON_DEPTH` and is well-formed JSON,
/// but the raw payload string is preserved as-is so the eventual
/// drain replay sees byte-exact what the peer sent. Re-serializing
/// here would defeat content-addressable hashing on the apply side.
pub fn enqueue_pending(
    conn: &Connection,
    envelope: &SyncEnvelope,
    reason: &str,
    missing_entity_type: Option<&str>,
    missing_entity_id: Option<&str>,
) -> Result<(), SyncError> {
    enqueue_pending_inner(
        conn,
        envelope,
        reason,
        missing_entity_type,
        missing_entity_id,
        true,
        true,
    )
}

fn enqueue_pending_inner(
    conn: &Connection,
    envelope: &SyncEnvelope,
    reason: &str,
    missing_entity_type: Option<&str>,
    missing_entity_id: Option<&str>,
    increment_duplicate_attempts: bool,
    enforce_attempt_cap: bool,
) -> Result<(), SyncError> {
    // short-circuit known-poison identities. A previous
    // attempt against this `(entity_type, entity_id, version)` triple
    // exhausted the per-row retry budget, was promoted to an
    // EXHAUSTED conflict, and recorded in `sync_quarantine_blocklist`.
    // Without this gate, a peer that keeps redelivering the same
    // poison envelope (remote provider retrying after a transient pull
    // failure, a chatty file-bridge replay) would re-enter the
    // pending inbox at `attempt_count = 1`, defeat the cap, and
    // ping-pong the conflict logger forever — one fresh
    // EXHAUSTED row per redelivery instead of converging.
    //
    // Treat the short-circuit as a benign success: the caller's
    // apply path already deferred the envelope by reaching this
    // function, and re-deferring it to no-op is the right shape.
    // The blocklist row's `quarantined_at` doubles as a diagnostic
    // surface (counts of suppressed redeliveries via the row's
    // mtime trail, GC alongside the pending-inbox horizon).
    if is_quarantined(
        conn,
        envelope.entity_type.as_str(),
        &envelope.entity_id,
        &envelope.version.to_string(),
    )? {
        return Ok(());
    }

    // Defense-in-depth: validate that the envelope's payload respects
    // `canonicalize::MAX_JSON_DEPTH` *before* storing. Without this, a
    // pathological envelope with 100-deep nesting (that passed a future
    // payload_schema_version check and thus was deferred rather than
    // rejected) would be re-parsed on every drain cycle with serde_json's
    // default 128-deep recursion — cheap per-cycle but wasted forever.
    // Parsing here is also the natural point to reject a malformed
    // payload string that somehow reached this surface.
    // Parse via `From<serde_json::Error>` so the failure carries
    // the parse-class discriminant (Syntax/Eof/Data/Io) rather than
    // collapsing to a free-form string. The pending-inbox surface
    // routes by class when deciding whether to retry vs reject
    // permanently.
    let payload_value: serde_json::Value = serde_json::from_str(&envelope.payload)?;
    crate::canonicalize::canonicalize_json(&payload_value).map_err(|e| {
        SyncError::Envelope(format!("payload exceeds canonicalization limits: {e}"))
    })?;

    let envelope_json = serde_json::to_string(envelope)?;

    // UPSERT on the (entity_type, entity_id, version)
    // identity triple. A duplicate enqueue (the same envelope being
    // redelivered before its FK target arrives, or apply_envelope being
    // called twice on a deferred envelope) increments the existing
    // row's `attempt_count` instead of creating a fresh row at
    // `attempt_count = 1`. Without this, a chatty puller could re-enqueue
    // the same stuck envelope thousands of times and the per-row
    // `MAX_PENDING_INBOX_ATTEMPTS` cap would never bite — the row count
    // grew until horizon GC reaped everything 90 days later. The latest
    // `reason` / `missing_entity_*` / `envelope` payload wins on
    // conflict because a more recent attempt may carry more accurate
    // diagnostic info (e.g., the deferral reason changed from
    // SchemaTooNew to MissingDependency once the schema caught up).
    conn.execute(
        "INSERT INTO sync_pending_inbox
            (envelope, reason, missing_entity_type, missing_entity_id,
             envelope_entity_type, envelope_entity_id, envelope_version,
             first_attempted_at, last_attempted_at, attempt_count)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7,
                 strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
                 strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
                 1)
         ON CONFLICT(envelope_entity_type, envelope_entity_id, envelope_version)
         DO UPDATE SET
             envelope            = excluded.envelope,
             reason              = excluded.reason,
             -- Preserve the previously-recorded missing dependency when the
             -- new envelope's deferral reason doesn't carry one (audit
             -- #3021-M6). A re-enqueue under a reason variant
             -- without `missing_entity_*` columns (e.g. SchemaTooNew on a
             -- row originally deferred for MissingDependency) used to NULL
             -- out the diagnostic identity, breaking the late-tombstone
             -- remap branch and the diagnostics surface.
             missing_entity_type = COALESCE(excluded.missing_entity_type, missing_entity_type),
             missing_entity_id   = COALESCE(excluded.missing_entity_id, missing_entity_id),
             last_attempted_at   = excluded.last_attempted_at,
             attempt_count       = CASE
                                      WHEN ?8 THEN attempt_count + 1
                                      ELSE attempt_count
                                   END",
        params![
            envelope_json,
            reason,
            missing_entity_type,
            missing_entity_id,
            envelope.entity_type.as_str(),
            envelope.entity_id,
            envelope.version.to_string(),
            increment_duplicate_attempts,
        ],
    )?;

    // enforce the per-envelope retry budget at the
    // enqueue boundary too, not only at drain time. The drain loop
    // already discards entries whose `attempt_count` reaches
    // [`MAX_PENDING_INBOX_ATTEMPTS`], but a pathological FK pair
    // where every fresh `apply_envelope` call re-enqueues the same
    // envelope (without going through drain) could ping-pong the
    // `attempt_count` past the cap forever — drain only sees the
    // row when it's iterated, and another fresh enqueue between
    // iterations keeps bumping the count and resetting nothing.
    // Read back the post-UPSERT `attempt_count` and, when it has
    // crossed the cap, record an EXHAUSTED conflict + remove the
    // row so the same poison envelope cannot keep redelivering.
    let post_count: i64 = conn
        .query_row(
            "SELECT attempt_count FROM sync_pending_inbox \
             WHERE envelope_entity_type = ?1 \
               AND envelope_entity_id = ?2 \
               AND envelope_version = ?3",
            params![
                envelope.entity_type.as_str(),
                envelope.entity_id,
                envelope.version.to_string()
            ],
            |row| row.get(0),
        )
        .map_err(|err| match err {
            rusqlite::Error::QueryReturnedNoRows => SyncError::Sql(err),
            other => SyncError::Sql(other),
        })?;

    if enforce_attempt_cap && post_count >= MAX_PENDING_INBOX_ATTEMPTS {
        // Promote the row to a permanent EXHAUSTED conflict and drop
        // it. Mirror the cap-discard branch in `drain_pending_inbox`
        // so both surfaces emit the same diagnostic shape (callers
        // querying `sync_conflict_log` see one canonical record per
        // exhausted envelope regardless of whether the cap fired in
        // a fresh enqueue or in a drain replay).
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
                resolution_type: std::borrow::Cow::Borrowed(
                    naming::RESOLUTION_PENDING_INBOX_EXHAUSTED,
                ),
            },
        )?;
        conn.execute(
            "DELETE FROM sync_pending_inbox \
             WHERE envelope_entity_type = ?1 \
               AND envelope_entity_id = ?2 \
               AND envelope_version = ?3",
            params![
                envelope.entity_type.as_str(),
                envelope.entity_id,
                envelope.version.to_string()
            ],
        )?;
        crate::error_log::log_sync_error(
            conn,
            "sync.pending_inbox.enqueue_exhausted",
            &format!(
                "pending_inbox enqueue exhausted retry budget ({MAX_PENDING_INBOX_ATTEMPTS}) for \
                 {}:{} version={}; envelope quarantined as poison (#3009-M6)",
                envelope.entity_type, envelope.entity_id, envelope.version
            ),
            None,
        );
        // record the poison identity in the
        // blocklist so future redeliveries short-circuit at the top
        // of `enqueue_pending` instead of climbing the retry ladder
        // again from `attempt_count = 1`. Best-effort: if the write
        // fails (e.g. transient SQL error), the next redelivery
        // simply re-runs the cap-promote branch — no correctness
        // loss, just a duplicated conflict row in the worst case.
        record_quarantine(
            conn,
            envelope.entity_type.as_str(),
            &envelope.entity_id,
            &envelope.version.to_string(),
        )?;
    }

    Ok(())
}

/// Convenience wrapper: enqueue a deferred envelope using a typed `DeferralReason`.
///
/// Extracts `missing_entity_type` / `missing_entity_id` from the reason
/// automatically, avoiding duplicated pattern matching at every call site.
pub fn enqueue_deferred(
    conn: &Connection,
    envelope: &SyncEnvelope,
    reason: &DeferralReason,
) -> Result<(), SyncError> {
    // invariant-blocked deletes record the aggregate identity in the
    // same diagnostic columns as a normal missing-dependency defer so
    // the diagnostics panel can surface "still alive: list X (waiting
    // for another list to arrive)". The drain doesn't FK-resolve the
    // invariant-blocked entry — it just retries on every drain cycle
    // until the invariant relaxes naturally (another list lands).
    let (missing_type, missing_id) = match reason {
        DeferralReason::MissingDependency {
            entity_type,
            entity_id,
        }
        | DeferralReason::AggregateInvariantBlocked {
            entity_type,
            entity_id,
            ..
        } => (Some(entity_type.as_str()), Some(entity_id.as_str())),
        _ => (None, None),
    };

    let preserves_for_upgrade = matches!(reason, DeferralReason::SchemaTooNew { .. });
    enqueue_pending_inner(
        conn,
        envelope,
        &reason.to_string(),
        missing_type,
        missing_id,
        !preserves_for_upgrade,
        !preserves_for_upgrade,
    )
}
