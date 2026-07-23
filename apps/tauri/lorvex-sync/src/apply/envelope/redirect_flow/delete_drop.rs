//! Drop redirected DELETE envelopes authored against a merge loser.

use rusqlite::Connection;

use lorvex_domain::hlc::Hlc;

use super::super::super::redirect::RedirectHop;
use super::super::super::{ApplyError, ApplyResult};
use crate::envelope::{SyncEnvelope, SyncOperation};
use crate::tombstone::Tombstone;

pub(super) fn drop_redirected_delete(
    conn: &Connection,
    envelope: &SyncEnvelope,
    remapped: &SyncEnvelope,
    hops: &[RedirectHop],
    ts: &Tombstone,
    apply_ts: &str,
) -> Result<Option<ApplyResult>, ApplyError> {
    // hoist the Delete-vs-redirect drop check
    // BEFORE the per-hop payload identity rewrites + canonical
    // re-serialization. Delete envelopes carry no payload body
    // worth rewriting (they're identity-only at the wire level),
    // and the conflict_log row records `envelope.device_id`
    // (the original peer that authored the stale delete), not
    // the locally-attributed `remapped.device_id`. So all the
    // per-hop work below — local-attribution capture, payload
    // FK rewrites, canonical re-serialization, the
    // post-rewrite size cap — is wasted on Delete envelopes
    // that the next branch immediately drops. Hoisting the
    // check saves O(hops × payload size) work per redirected
    // delete envelope, which matters most on cluster-wide
    // tag-merge cascades (every device replays peer deletes
    // against tags it has already merged locally).
    //
    // a Delete envelope that lands on the
    // redirect path was authored against the merge LOSER's
    // identity (the original entity_id before remap). Such a
    // delete can only have come from a peer that hadn't yet
    // observed the merge — a peer that observed the merge
    // would have routed the delete to the winner directly.
    // Propagating the delete to the redirect target would be
    // unauthorized data destruction (the merge winner is a
    // different identity that may carry concurrent edits or
    // children). Drop the delete and record a conflict_log
    // entry so the diagnostics surface sees it.
    if remapped.operation == SyncOperation::Delete {
        // the merge tombstone that claimed
        // the loser identity is `hops[0]` (the first hop in
        // the chase). Its version is the winner that
        // dominates anything authored against the pre-merge
        // id. The hops vector is non-empty here because the
        // outer `redirect_entity_id.is_some()` guard
        // guaranteed at least one redirect hop.
        let merge_tombstone_version = hops
            .first()
            .map_or_else(|| ts.version.clone(), |h| h.version.clone());
        crate::conflict_log::log_conflict(
            conn,
            &crate::conflict_log::ConflictLogEntry {
                id: 0,
                entity_type: std::borrow::Cow::Borrowed(envelope.entity_type.as_str()),
                entity_id: envelope.entity_id.clone(),
                winner_version: merge_tombstone_version.clone(),
                loser_version: envelope.version.to_string(),
                loser_device_id: envelope.device_id.clone(),
                // No payload to log — Delete envelopes are
                // identity-only.
                loser_payload: None,
                resolved_at: apply_ts.to_string(),
                resolution_type: std::borrow::Cow::Borrowed(
                    lorvex_domain::naming::RESOLUTION_REDIRECTED_DELETE_DROPPED,
                ),
            },
        )?;
        // typed winner = the merge tombstone
        // version that beat this redirected delete envelope.
        // Audit (silent-failure-hunter):
        // discarded a corrupt-HLC parse failure, so `winner_version`
        // became `None` and the `Skipped` result lost its arbitration
        // provenance. Log the corruption so diagnostics can surface
        // the data drift; the `None` fallback is preserved because
        // dropping the redirected delete is still the correct
        // outcome — only the provenance metadata is degraded.
        let winner_version = match Hlc::parse(&merge_tombstone_version) {
            Ok(v) => Some(v),
            Err(parse_err) => {
                crate::error_log::log_sync_error(
                    conn,
                    "sync.apply.redirect_corrupt_winner_hlc",
                    &format!(
                        "merge tombstone HLC '{merge_tombstone_version}' for redirect-loser \
                         {}:{} -> {} is not a valid HLC: {parse_err}",
                        envelope.entity_type, envelope.entity_id, remapped.entity_id,
                    ),
                    None,
                );
                None
            }
        };
        return Ok(Some(ApplyResult::Skipped {
            reason: format!(
                "delete envelope for merge-loser {}:{} dropped (target now {})",
                envelope.entity_type, envelope.entity_id, remapped.entity_id,
            ),
            winner_version,
        }));
    }
    Ok(None)
}
