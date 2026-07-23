use rusqlite::Connection;
use std::collections::HashSet;

use super::diagnostics::{
    log_fk_stalled, log_fk_unresolved_discard, quarantine_unparseable_entry, should_log_stalled,
    sync_error_for_pending_apply_failure,
};
use super::quarantine::record_quarantine;
use super::remap::remap_missing_dependency;
use super::store::{
    bump_attempt_count_to_cap, pending_entry_by_id, pending_entry_ids_for_drain,
    read_attempt_count, record_reattempt, record_reattempt_busy, record_reattempt_with_error,
    remove_pending, update_pending_entry, MAX_PENDING_INBOX_ATTEMPTS,
};
use super::types::PendingDrainSummary;
use crate::apply::{apply_envelope, ApplyError, ApplyResult, DeferralReason};
use crate::conflict_log::{log_conflict, ConflictLogEntry};
use crate::error::SyncError;
use crate::tombstone::get_tombstone;
use lorvex_domain::naming;

/// Soft upper bound on the number of pending inbox entries any single
/// `drain_pending_inbox` pass will visit. A massive backlog (e.g. a
/// device coming back online after a 30-day outage with thousands of
/// queued envelopes) is capped to this many entries per pass so the
/// SQLite writer is released within bounded latency and never starves
/// concurrent IPC / MCP writes. The next sync tick re-drives the drain
/// to make further forward progress.
///
/// #3658 — first-sync convergence note. A first device coming online
/// against a populated remote folder/provider routinely lands 5-10 k pending
/// envelopes in the inbox before the apply pipeline can resolve their
/// FK dependencies; at 500 entries per pass that is 10–20 passes to
/// drain. With the default sync tick of 30 s between rounds the
/// initial convergence takes roughly 5–10 minutes of background work
/// before the inbox empties. The cap is intentionally chosen for the
/// steady state where each pass rarely fills it; the longer
/// first-sync horizon is the trade-off for never starving foreground
/// writes.
const MAX_DRAIN_ENTRIES_PER_PASS: usize = 500;

/// Re-attempt all entries in the pending inbox using typed dependency rules.
///
/// Processing rules:
/// - successful apply / skip => remove entry
/// - missing dependency tombstoned with no redirect => discard + conflict log
/// - missing dependency tombstoned with redirect => rewrite envelope and retry
/// - still deferred/error => keep entry, update attempt metadata
/// - entries stalled for >1 hour => log `fk_stalled` once for visibility
pub fn drain_pending_inbox(conn: &Connection) -> Result<PendingDrainSummary, SyncError> {
    if conn.is_autocommit() {
        return lorvex_store::with_immediate_transaction(conn, drain_pending_inbox_in_transaction);
    }
    drain_pending_inbox_in_transaction(conn)
}

fn drain_pending_inbox_in_transaction(conn: &Connection) -> Result<PendingDrainSummary, SyncError> {
    // Snapshot only the id batch, then re-read each row from the live
    // table before processing it. That preserves the stale-row safety
    // the old id-cursor loop needed (side effects may have removed an
    // entry before we reach it), but orders each pass by
    // `last_attempted_at ASC, id ASC` instead of always starting from
    // the lowest id. A capped pass can update the first 500 stalled
    // children; the next pass then gives older untouched rows (for
    // example the missing parent at id 501) a chance before those same
    // children burn another retry slot.
    let mut summary = PendingDrainSummary::default();
    let entry_ids = pending_entry_ids_for_drain(conn, MAX_DRAIN_ENTRIES_PER_PASS)?;
    let mut coalesced_target_ids = HashSet::new();

    for entry_id in entry_ids {
        if coalesced_target_ids.remove(&entry_id) {
            continue;
        }
        let Some(entry) = pending_entry_by_id(conn, entry_id)? else {
            continue;
        };
        let mut envelope = match entry.parse_envelope() {
            Ok(env) => env,
            Err(err) => {
                // Defensive: an envelope that fails to deserialize
                // (corrupt JSON, unrecognized typed `entity_type`,
                // malformed version string) is a poison pill that must
                // not abort the drain — every sibling row would be
                // blocked from retrying. Match `outbox::get_pending`'s
                // defensive style: log to `error_logs` so Settings →
                // Diagnostics surfaces the row, bump `attempt_count`
                // to the cap so `enqueue_pending`'s quarantine logic
                // catches the row on the next enqueue, and continue
                // past this entry. If a second drain pass encounters
                // the same unparseable row already at the cap, the
                // discard branch directly below promotes it to an
                // EXHAUSTED conflict and removes it — bounding the
                // diagnostic feed and the queue depth.
                lorvex_store::error_log::append_error_log_best_effort(
                    conn,
                    "sync.pending_inbox.unparseable_envelope",
                    &format!(
                        "pending_inbox entry {} carries an envelope that cannot be \
                         deserialized; quarantining as poison: {err}",
                        entry.id,
                    ),
                    None,
                    Some("error"),
                );
                if entry.attempt_count >= MAX_PENDING_INBOX_ATTEMPTS {
                    // Already at the cap from a prior drain — promote
                    // to a permanent EXHAUSTED conflict and drop the
                    // row so we don't keep re-logging the same parse
                    // failure forever. We synthesize a minimal
                    // conflict_log row from the persisted identity
                    // columns (envelope_entity_type / _id / _version)
                    // so the diagnostic surface still gets a record
                    // even when the envelope body itself is corrupt.
                    if let Err(bookkeeping) = quarantine_unparseable_entry(conn, entry.id) {
                        let follow = format!(
                            "pending_inbox entry {} unparseable-quarantine failed: {bookkeeping}",
                            entry.id,
                        );
                        crate::error_log::log_sync_error(conn, "sync.pending_inbox", &follow, None);
                    } else {
                        summary.discarded += 1;
                    }
                } else if let Err(bookkeeping) =
                    bump_attempt_count_to_cap(conn, entry.id, MAX_PENDING_INBOX_ATTEMPTS)
                {
                    let follow = format!(
                        "pending_inbox entry {} attempt-cap bump failed: {bookkeeping}",
                        entry.id,
                    );
                    crate::error_log::log_sync_error(conn, "sync.pending_inbox", &follow, None);
                }
                summary.errors += 1;
                continue;
            }
        };

        // Tombstone-redirect handling first — a tombstone that arrives
        // late should still be able to rescue an exhausted entry via
        // remapping before the cap check discards it.
        if let (Some(missing_type), Some(missing_id)) = (
            entry.missing_entity_type.as_deref(),
            entry.missing_entity_id.as_deref(),
        ) {
            if let Some(tombstone) = get_tombstone(conn, missing_type, missing_id)? {
                if let Some(redirect_id) = tombstone.redirect_entity_id.as_deref() {
                    let redirect_type = tombstone
                        .redirect_entity_type
                        .as_deref()
                        .unwrap_or(missing_type);
                    if let Some(remapped) = remap_missing_dependency(
                        &envelope,
                        missing_type,
                        missing_id,
                        redirect_type,
                        redirect_id,
                    )? {
                        envelope = remapped;
                        summary.remapped += 1;
                    } else {
                        log_fk_unresolved_discard(conn, &envelope, &tombstone.version)?;
                        remove_pending(conn, entry.id)?;
                        summary.discarded += 1;
                        continue;
                    }
                } else {
                    log_fk_unresolved_discard(conn, &envelope, &tombstone.version)?;
                    remove_pending(conn, entry.id)?;
                    summary.discarded += 1;
                    continue;
                }
            }
        }

        match apply_envelope(conn, &envelope) {
            Ok(ApplyResult::Applied | ApplyResult::Remapped { .. }) => {
                remove_pending(conn, entry.id)?;
                summary.replayed += 1;
                // track distinct entity types so the
                // caller can fan out `data-changed` events for rows
                // the inbox just unblocked. Dedup at insertion time
                // (not on read) so the Vec stays small even when a
                // single drain replays hundreds of envelopes of the
                // same kind.
                if !summary
                    .replayed_entity_types
                    .contains(&envelope.entity_type)
                {
                    summary.replayed_entity_types.push(envelope.entity_type);
                }
            }
            // split `Skipped` out of `replayed` so
            // the metric reflects actual forward progress. Also reap
            // any payload shadow whose `base_version` is older than
            // the envelope's version — a Skipped result here means
            // either tombstone-wins or LWW-loss; the envelope's
            // `version` dominates everything older, so an obsolete
            // shadow at this site cannot legally promote.
            // `remove_shadow_if_superseded` is the same helper called
            // by the early-skip branches in `apply_envelope` (audit
            // #2946-H6), keeping the shadow lifecycle uniform across
            // all skip paths.
            Ok(ApplyResult::Skipped { .. }) => {
                lorvex_sync_payload::payload_shadow::remove_shadow_if_superseded(
                    conn,
                    envelope.entity_type.as_str(),
                    &envelope.entity_id,
                    &envelope.version.to_string(),
                )?;
                remove_pending(conn, entry.id)?;
                summary.skipped += 1;
            }
            Ok(ApplyResult::Deferred { reason }) => {
                let is_schema_too_new = matches!(reason, DeferralReason::SchemaTooNew { .. });
                let (missing_type, missing_id) = match &reason {
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
                let active_pending_id = update_pending_entry(
                    conn,
                    entry.id,
                    &envelope,
                    &reason.to_string(),
                    missing_type,
                    missing_id,
                )?;
                if active_pending_id != entry.id {
                    coalesced_target_ids.insert(active_pending_id);
                }
                if is_schema_too_new {
                    record_reattempt_busy(conn, active_pending_id)?;
                    continue;
                }
                record_reattempt(conn, active_pending_id)?;

                // Cap on the on-disk post-bump value rather than the
                // pre-bump snapshot + 1. The on-disk value is the only
                // value that can be trusted when a concurrent drain or
                // bookkeeping retry has pushed `attempt_count` past the
                // snapshot — otherwise a row could slip past the cap or
                // trip it a cycle late. A missing row means another
                // writer already discarded it — skip the cap branch
                // entirely.
                let post_count = read_attempt_count(conn, active_pending_id)?.unwrap_or(i64::MIN);
                if post_count >= MAX_PENDING_INBOX_ATTEMPTS {
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
                    record_quarantine(
                        conn,
                        envelope.entity_type.as_str(),
                        &envelope.entity_id,
                        &envelope.version.to_string(),
                    )?;
                    remove_pending(conn, active_pending_id)?;
                    summary.discarded += 1;
                } else if should_log_stalled(conn, &entry, &envelope)? {
                    log_fk_stalled(conn, &envelope)?;
                    summary.stalled_logged += 1;
                }
            }
            Err(error) => {
                // Classify `SQLITE_BUSY` / `SQLITE_LOCKED` as
                // transient and re-record `last_attempted_at` WITHOUT
                // bumping `attempt_count`. A drain that lost a race
                // with another writer must not count toward the
                // [`MAX_PENDING_INBOX_ATTEMPTS`] cap — the transient
                // class is recoverable by definition and the very next
                // drain (typically milliseconds later) will succeed,
                // so consuming retries here would let queues full of
                // legitimate envelopes exhaust and discard rows that
                // were never actually re-applied.
                if is_transient_busy_or_locked(&error) {
                    if let Err(bookkeeping) = record_reattempt_busy(conn, entry.id) {
                        let follow = format!(
                            "pending_inbox entry {} busy-reattempt bookkeeping failed: {bookkeeping}",
                            entry.id,
                        );
                        crate::error_log::log_sync_error(conn, "sync.pending_inbox", &follow, None);
                    }
                    summary.errors += 1;
                    continue;
                }

                // Do NOT abort the entire drain on a single entry's
                // error. A permanently-invalid envelope (corrupt JSON,
                // unknown entity type, invalid version string) would
                // otherwise block every other pending entry from ever
                // being retried — the "poison-pill" problem (R24 fix).
                //
                // Persist to error_logs so Settings → Diagnostics
                // surfaces invalid envelopes. Both the Tauri release
                // binary and the MCP stdio server run with a closed
                // stderr, so eprintln-only diagnostics would lose the
                // signal — a permanently-invalid remote envelope could
                // silently fail apply for the full FULL_RESYNC_HORIZON_DAYS
                // before horizon GC quietly drops it, taking user data
                // with it.
                let se = sync_error_for_pending_apply_failure(entry.id, &envelope, error);
                let msg = format!(
                    "pending_inbox entry {} (entity {}:{} version {}): {se}",
                    entry.id, envelope.entity_type, envelope.entity_id, envelope.version,
                );
                // Only write to `error_logs` when the failure mode
                // actually changed since the last drain — a
                // permanently-erroring entry must not duplicate the
                // same row every drain cycle, since the diagnostic
                // feed would otherwise grow for the full
                // FULL_RESYNC_HORIZON_DAYS even though the user can
                // act on a single occurrence. The bookkeeping error
                // path below logs unconditionally — it's a separate
                // failure class (DB write itself failed) and should
                // always be visible.
                let prior_error = match record_reattempt_with_error(conn, entry.id, &msg) {
                    Ok(prior) => prior,
                    Err(bookkeeping) => {
                        let follow = format!(
                            "pending_inbox entry {} reattempt bookkeeping failed: {bookkeeping}",
                            entry.id,
                        );
                        crate::error_log::log_sync_error(conn, "sync.pending_inbox", &follow, None);
                        // Log the apply error too — we don't have a
                        // prior value to dedup against, so default to
                        // "log it" rather than dropping the trace.
                        crate::error_log::log_sync_error(conn, "sync.pending_inbox", &msg, None);
                        summary.errors += 1;
                        continue;
                    }
                };
                if prior_error.as_deref() != Some(msg.as_str()) {
                    crate::error_log::log_sync_error(conn, "sync.pending_inbox", &msg, None);
                }
                summary.errors += 1;

                // Mirror the cap-discard branch from the Ok(Deferred)
                // path. A permanently-erroring entry (e.g.
                // TombstoneRedirectCycle, malformed payload surviving
                // validate, unknown entity type) must not stay in the
                // table for the full FULL_RESYNC_HORIZON_DAYS (90),
                // burning a fresh reattempt every drain cycle and
                // writing a fresh error_logs row each time. Discard
                // at MAX_PENDING_INBOX_ATTEMPTS so the queue and the
                // diagnostic feed both stay bounded. Read the
                // post-bump value from disk so the cap
                // matches the value `record_reattempt_with_error`
                // actually wrote, not a pre-bump arithmetic guess.
                let post_count = read_attempt_count(conn, entry.id)?.unwrap_or(i64::MIN);
                if post_count >= MAX_PENDING_INBOX_ATTEMPTS {
                    let conflict = ConflictLogEntry {
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
                    };
                    if let Err(bookkeeping) = log_conflict(conn, &conflict) {
                        let follow = format!(
                            "pending_inbox entry {} exhausted-conflict logging failed: {bookkeeping}",
                            entry.id,
                        );
                        crate::error_log::log_sync_error(conn, "sync.pending_inbox", &follow, None);
                    } else if let Err(bookkeeping) = remove_pending(conn, entry.id) {
                        let follow = format!(
                            "pending_inbox entry {} exhausted-remove failed: {bookkeeping}",
                            entry.id,
                        );
                        crate::error_log::log_sync_error(conn, "sync.pending_inbox", &follow, None);
                    } else {
                        // mirror the Ok(Deferred) cap-discard: record
                        // the poison identity so a future redelivery of
                        // the same envelope short-circuits at the
                        // enqueue boundary.
                        if let Err(bookkeeping) = record_quarantine(
                            conn,
                            envelope.entity_type.as_str(),
                            &envelope.entity_id,
                            &envelope.version.to_string(),
                        ) {
                            let follow = format!(
                                "pending_inbox entry {} exhausted-quarantine failed: {bookkeeping}",
                                entry.id,
                            );
                            crate::error_log::log_sync_error(
                                conn,
                                "sync.pending_inbox",
                                &follow,
                                None,
                            );
                        }
                        summary.discarded += 1;
                    }
                }
            }
        }
    }

    Ok(summary)
}

/// a recoverable lock-contention error from SQLite.
///
/// `SQLITE_BUSY` (5) fires when another process / thread holds the
/// reserved lock the apply pipeline needs; `SQLITE_LOCKED` (6) fires
/// when a recursive write inside the same connection collides with
/// the pending inbox drain. Both are transient by nature — the next
/// drain typically resolves them in milliseconds — and must NOT
/// count against [`MAX_PENDING_INBOX_ATTEMPTS`] (50). Counting a
/// lock-race loss as an attempt would let a queue under heavy
/// concurrent write load exhaust its retries without ever having
/// actually run the apply handler.
///
/// All other SQLite error classes (`SQLITE_CONSTRAINT`, `SQLITE_FULL`,
/// `SQLITE_CORRUPT`, …) and every non-SQL `ApplyError` variant are
/// permanent failures and continue down the existing
/// `record_reattempt_with_error` path.
pub(super) const fn is_transient_busy_or_locked(error: &ApplyError) -> bool {
    use rusqlite::ErrorCode;
    // `Store` wraps StoreError which can also carry a SQLite error —
    // inspect that too so a store-layer write contention surfaces with
    // the same tolerance as a direct `Db` error.
    let (ApplyError::Db(sql_err) | ApplyError::Store(lorvex_store::StoreError::Sql(sql_err))) =
        error
    else {
        return false;
    };
    match sql_err {
        rusqlite::Error::SqliteFailure(rusqlite::ffi::Error { code, .. }, _) => {
            matches!(code, ErrorCode::DatabaseBusy | ErrorCode::DatabaseLocked)
        }
        _ => false,
    }
}
