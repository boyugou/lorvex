//! Delete-side tombstone finalization for envelope apply.

use rusqlite::Connection;

use super::super::conflict::record_lww_conflict_and_skip;
use super::super::{dispatch, ApplyError, ApplyResult, DeferralReason};
use super::finalize_payload_shadow;
use crate::envelope::{SyncEnvelope, SyncOperation};
use crate::tombstone::create_tombstone;
use lorvex_domain::capability::EnvelopeAcceptance;
use lorvex_domain::hlc::Hlc;

pub(super) fn finalize_entity_outcome(
    conn: &Connection,
    envelope: &SyncEnvelope,
    entity_outcome: dispatch::EntityApplyOutcome,
    acceptance: EnvelopeAcceptance,
    apply_ts: &str,
) -> Result<ApplyResult, ApplyError> {
    use dispatch::EntityApplyOutcome;
    // 5. After a successful delete, record the tombstone locally.
    // Per spec (doc 03): receiver-side delete apply is not complete until the
    // delete version is recorded in sync_tombstones.
    //
    // by default a delete envelope writes a
    // tombstone even when the in-handler DELETE was a no-op (idempotent
    // late-replay against an already-deleted row). The tombstone is the
    // forward-looking idempotent marker: future stale upserts for this
    // entity_id get correctly rejected by the tombstone-vs-upsert
    // guard. Two outcomes suppress the tombstone:
    //
    // (a) `LwwRejected` — the in-handler
    //       `:version >= version` gate refused the DELETE because the
    //       local row's version is strictly greater than the
    //       envelope's. Recording a tombstone at the envelope's older
    //       HLC would override the surviving local row on the next
    //       re-sync (the tombstone-vs-upsert gate uses tombstone.version,
    //       not the row's version, to elect a winner). Surface a Skipped
    //       result with a typed winner so diagnostics see it.
    //
    //   (b) `DeleteSkippedByInvariant` — the at-least-one-list
    //       invariant in `apply_list_delete` refused the DELETE
    //       because deleting the row would leave the receiving
    //       device with zero lists. Writing a tombstone at the
    //       envelope's HLC over a still-live row would permanently
    //       block any future re-upsert from any peer (the
    //       tombstone-vs-upsert gate uses
    //       `tombstone.version >= envelope.version`, so a peer
    //       concurrent edit at a lower HLC would silently lose; a
    //       `cleanup_tombstoned_lists` pass on the next list
    //       upsert is meant to reap the orphan, but the gap
    //       between "tombstone written" and "another list arrives"
    //       is a real data-loss window). Defer the envelope to
    //       `sync_pending_inbox`; the drain loop retries the delete on
    //       every apply pass and once another list arrives the
    //       invariant relaxes naturally.
    if envelope.operation == SyncOperation::Delete {
        if let EntityApplyOutcome::LwwRejected { local_version } = &entity_outcome {
            // The local row beat the envelope inside the handler.
            // The handler's pre-DELETE LWW gate already paid the
            // `SELECT version FROM <table> WHERE id = ?1` and
            // surfaced the value through the typed
            // `LwwRejectedDetail.local_version`; the dispatcher
            // re-exposes it here so we don't re-issue the same
            // SELECT. The post-handler LWW
            // path also threads its own `post_version` through this
            // field so unparseable-equal and post_is_strictly_newer
            // branches share the same render path.
            let local_version_str = local_version.clone();
            let reason = format!(
                "delete refused by in-handler LWW gate: local version {} \
                 strictly greater than envelope version {} for {}:{}",
                local_version_str, envelope.version, envelope.entity_type, envelope.entity_id,
            );
            // parse the local version once so
            // `record_lww_conflict_and_skip` receives a typed `Hlc`
            // instead of re-parsing the raw string. If the local
            // version is corrupt (legacy data, manual DB edit) fall
            // back to a synthesized `Hlc` from the envelope's own
            // version — the conflict log row still attributes the
            // skip correctly because `winner_version` is the typed
            // local-side value the handler-gate compared against. We
            // also log the corruption to error_log for symmetry with
            // the parsed-local-version path (#2916-M7).
            let local_version = match Hlc::parse(&local_version_str) {
                Ok(v) => v,
                Err(err) => {
                    let detail = format!(
                        "local version '{local_version_str}' on {}:{} is not a valid HLC at \
                         in-handler LWW reject site: {err}",
                        envelope.entity_type, envelope.entity_id
                    );
                    crate::error_log::log_sync_error(
                        conn,
                        "sync.apply.local_version_corruption",
                        &detail,
                        None,
                    );
                    // `envelope.version` is typed `Hlc`.
                    envelope.version.clone()
                }
            };
            return record_lww_conflict_and_skip(
                conn,
                envelope.entity_type.as_str(),
                &envelope.entity_id,
                &local_version,
                envelope,
                reason,
                apply_ts,
            );
        }
        if let dispatch::EntityApplyOutcome::DeleteSkippedByInvariant { invariant } = entity_outcome
        {
            // the invariant guard refused the DELETE.
            // Return a typed deferral so the caller can park the
            // envelope in `sync_pending_inbox` and retry after the
            // invariant relaxes — another list arrives, or referencing
            // tasks resolve their own deletes. Suppress the tombstone:
            // writing it at the envelope's HLC over a still-live row
            // would block every future re-upsert of the same id, which
            // is the bug this issue closes. The shadow row is also left
            // intact; the deferred envelope replay will clear it via
            // `finalize_payload_shadow` once the delete actually
            // applies.
            let reason = DeferralReason::AggregateInvariantBlocked {
                entity_type: envelope.entity_type,
                entity_id: envelope.entity_id.clone(),
                invariant,
            };
            return Ok(ApplyResult::Deferred { reason });
        }
        // `create_tombstone` gates the shadow side-effect on
        // `if updated > 0` (a monotonicity-rejected INSERT writes
        // nothing and must not touch the shadow either). The
        // in-tombstone gate is the single source of truth — an
        // unconditional `remove_shadow` follow-up here would
        // discard a valid shadow whenever the tombstone INSERT was
        // rejected by the version monotonicity gate, leaving the
        // system inconsistent (shadow gone, live row already
        // promoted past the incoming tombstone's version).
        create_tombstone(
            conn,
            envelope.entity_type.as_str(),
            &envelope.entity_id,
            &envelope.version.to_string(),
            apply_ts,
            None,
            None,
        )?;
    } else {
        finalize_payload_shadow(conn, acceptance, envelope)?;
    }

    Ok(ApplyResult::Applied)
}
