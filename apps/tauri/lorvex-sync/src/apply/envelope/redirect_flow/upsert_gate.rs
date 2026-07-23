//! Tombstone-on-target check + LWW gate + FK preflight for the
//! redirected upsert branch.

use rusqlite::Connection;

use lorvex_domain::capability::EnvelopeAcceptance;
use lorvex_domain::hlc::Hlc;
use lorvex_domain::merge::{resolve_lww, MergeOutcome};

use super::super::super::conflict::{reap_shadow_for_skipped, record_lww_conflict_and_skip};
use super::super::super::{ApplyError, ApplyResult, DeferralReason};
use super::super::{
    apply_entity, check_fk_dependencies, finalize_payload_shadow, get_local_version,
};
use crate::envelope::{SyncEnvelope, SyncOperation};

pub(super) fn gate_redirected_upsert(
    conn: &Connection,
    envelope: &SyncEnvelope,
    remapped: &SyncEnvelope,
    acceptance: EnvelopeAcceptance,
    apply_ts: &str,
) -> Result<Option<ApplyResult>, ApplyError> {
    // Tombstone-on-target check + LWW gate run BEFORE the FK
    // preflight on the remapped envelope — both gates must admit
    // the envelope before the FK preflight runs. The non-redirect
    // branch routes (1) tombstone, (2) LWW, (3) FK in that order,
    // and the redirect branch follows the same order. Running FK
    // first would let an envelope whose remapped (redirect-target)
    // row was already tombstoned AND was missing a transient
    // parent FK target sit in `sync_pending_inbox` for
    // `MAX_PENDING_INBOX_ATTEMPTS` retries before the dominating
    // tombstone got a chance to skip it — burning retention on
    // envelopes whose ultimate outcome is "lost to tombstone"
    // anyway.
    if remapped.operation != SyncOperation::Upsert {
        return Ok(None);
    }
    if let Some(result) = check_target_tombstone(conn, envelope, remapped, apply_ts)? {
        return Ok(Some(result));
    }
    if let Some(result) = check_target_lww(conn, envelope, remapped, acceptance, apply_ts)? {
        return Ok(Some(result));
    }
    check_target_fk(conn, remapped)
}

/// Audit F11 (#2830): the redirect target itself may be tombstoned
/// with a real DELETE (not a redirect). The tombstone check at the
/// start of the redirect flow only ran against the ORIGINAL
/// entity_id, so without this guard the upsert lands on a tombstoned
/// target, resurrecting the row and defeating the tombstone semantics
/// — exactly the failure mode the delete-vs-upsert LWW gate exists to
/// prevent.
fn check_target_tombstone(
    conn: &Connection,
    envelope: &SyncEnvelope,
    remapped: &SyncEnvelope,
    apply_ts: &str,
) -> Result<Option<ApplyResult>, ApplyError> {
    let Some(target_ts) =
        crate::tombstone::get_tombstone(conn, remapped.entity_type.as_str(), &remapped.entity_id)?
    else {
        return Ok(None);
    };
    if target_ts.redirect_entity_id.is_some() {
        return Ok(None);
    }
    let target_ts_version = Hlc::parse(&target_ts.version)?;
    // `remapped.version` is typed `Hlc`.
    let envelope_version = &remapped.version;
    if envelope_version <= &target_ts_version {
        // Surface tombstone-vs-upsert skips in conflict_log so the
        // diagnostics panel sees them. Returning `Skipped` with a
        // free-form reason string and no log row would let the user
        // lose visibility into late-replayed envelopes that lost to a
        // real delete tombstone.
        crate::conflict_log::log_conflict(
            conn,
            &crate::conflict_log::ConflictLogEntry {
                id: 0,
                entity_type: std::borrow::Cow::Borrowed(remapped.entity_type.as_str()),
                entity_id: remapped.entity_id.clone(),
                winner_version: target_ts.version.clone(),
                loser_version: remapped.version.to_string(),
                loser_device_id: remapped.device_id.clone(),
                loser_payload: Some(remapped.payload.clone()),
                resolved_at: apply_ts.to_string(),
                resolution_type: std::borrow::Cow::Borrowed(
                    lorvex_domain::naming::RESOLUTION_TOMBSTONE_WINS,
                ),
            },
        )?;
        // reap any payload shadow for the redirect target whose
        // base_version is older than the tombstone's version. Without
        // this, a future promote pass would attempt to resurrect the
        // tombstoned target.
        reap_shadow_for_skipped(
            conn,
            remapped.entity_type.as_str(),
            &remapped.entity_id,
            &target_ts.version,
        )?;
        return Ok(Some(ApplyResult::Skipped {
            reason: format!(
                "redirect target {}:{} is tombstoned with version {} >= remapped envelope version {}",
                remapped.entity_type,
                remapped.entity_id,
                target_ts.version,
                remapped.version
            ),
            winner_version: Some(target_ts_version),
        }));
    }
    // Envelope is strictly newer than the delete tombstone —
    // concurrent-update-wins-over-concurrent-delete. Log the
    // resolution before removing the tombstone and falling through
    // to apply, mirroring every other LWW outcome in this module
    // (the prior shape silently undid a real DELETE the cluster had
    // agreed on, leaving operators with no audit trail for "why did
    // this previously-deleted entity reappear?" in Settings →
    // Diagnostics).
    crate::conflict_log::log_conflict(
        conn,
        &crate::conflict_log::ConflictLogEntry {
            id: 0,
            entity_type: std::borrow::Cow::Borrowed(remapped.entity_type.as_str()),
            entity_id: remapped.entity_id.clone(),
            winner_version: remapped.version.to_string(),
            loser_version: target_ts.version,
            loser_device_id: envelope.device_id.clone(),
            loser_payload: None,
            resolved_at: apply_ts.to_string(),
            resolution_type: std::borrow::Cow::Borrowed(
                lorvex_domain::naming::RESOLUTION_UPSERT_WINS_OVER_DELETE,
            ),
        },
    )?;
    crate::tombstone::remove_tombstone(conn, remapped.entity_type.as_str(), &remapped.entity_id)?;
    Ok(None)
}

/// LWW guard against stale envelopes — the redirect target may
/// already carry a newer local version (from a subsequent edit by
/// the merge winner). A late-replayed pre-merge envelope for the
/// loser must NOT overwrite the winner's current row.
fn check_target_lww(
    conn: &Connection,
    envelope: &SyncEnvelope,
    remapped: &SyncEnvelope,
    acceptance: EnvelopeAcceptance,
    apply_ts: &str,
) -> Result<Option<ApplyResult>, ApplyError> {
    let Some(local_version_str) =
        get_local_version(conn, remapped.entity_type.as_str(), &remapped.entity_id)?
    else {
        return Ok(None);
    };
    // Tolerate corrupt local versions here for parity with the non-
    // redirect branch. Treat an unparseable local version as "no
    // local version known" so the remapped envelope applies through
    // the upsert gate (which has its own corruption tolerance). Using
    // the `?` operator on `Hlc::parse` would propagate
    // `ApplyError::InvalidVersion` whenever the redirect target's row
    // carries a stale-shape literal — the rest of the apply pipeline
    // falls through to a benign no-op for the same condition.
    //
    // Also log the corruption to `error_log` so the diagnostics
    // surface sees the bad row (mirroring the non-redirect branch's
    // `sync.apply.local_version_corruption` source). Silently
    // swallowing the parse failure here would make a corrupt row at
    // a redirect-target id invisible in Settings → Diagnostics.
    let local_version = match Hlc::parse(&local_version_str) {
        Ok(v) => v,
        Err(err) => {
            let detail = format!(
                "local version '{local_version_str}' on {}:{} (redirect target) \
                 is not a valid HLC: {err}",
                remapped.entity_type, remapped.entity_id
            );
            crate::error_log::log_sync_error(
                conn,
                "sync.apply.local_version_corruption",
                &detail,
                None,
            );
            apply_entity(conn, remapped, apply_ts)?;
            finalize_payload_shadow(conn, acceptance, remapped)?;
            return Ok(Some(ApplyResult::Remapped {
                from_entity_id: envelope.entity_id.clone(),
                to_entity_id: remapped.entity_id.clone(),
            }));
        }
    };
    // `remapped.version` is typed `Hlc`.
    let remote_version = &remapped.version;
    if !matches!(
        resolve_lww(&local_version, remote_version),
        MergeOutcome::LocalWins
    ) {
        return Ok(None);
    }
    // mirror the non-redirect branch — record a conflict log entry
    // so the skip is visible in Settings → Diagnostics. Without
    // this, a late-replayed pre-merge envelope for a merge loser
    // would vanish with no trail.
    let reason = format!(
        "redirect target {}:{} has newer local version {} than remapped envelope version {}",
        remapped.entity_type, remapped.entity_id, local_version_str, remapped.version
    );
    // `record_lww_conflict_and_skip` reaps the shadow at the
    // REDIRECT TARGET id (`remapped.entity_*`). The shadow at the
    // ORIGINAL (loser) id is NOT reaped here — but it doesn't need
    // to be: when the merge tombstone that produced this redirect
    // was created, `tombstone::create_tombstone` calls
    // `payload_shadow::merge_shadow_into_redirect` (see
    // `tombstone.rs:178-184`) which moves the loser shadow's
    // forward-compat bytes into the winner's shadow and removes the
    // loser row in the same transaction. So in steady state there
    // is no shadow at `(envelope.entity_type, envelope.entity_id)`
    // to reap. The debug_assert below catches a regression in that
    // contract — if a bug ever leaves an orphan shadow at the loser
    // id, this fires loudly in tests and cfg(debug_assertions)
    // builds.
    debug_assert!(
        lorvex_sync_payload::payload_shadow::get_shadow(
            conn,
            envelope.entity_type.as_str(),
            &envelope.entity_id,
        )
        .map_or(true, |opt| opt.is_none()),
        "redirect-LWW skip: orphan shadow at original loser id ({}, {}) — \
         merge_shadow_into_redirect should have moved it on tombstone create",
        envelope.entity_type,
        envelope.entity_id,
    );
    record_lww_conflict_and_skip(
        conn,
        remapped.entity_type.as_str(),
        &remapped.entity_id,
        &local_version,
        remapped,
        reason,
        apply_ts,
    )
    .map(Some)
}

/// FK preflight for the remapped envelope runs LAST in the
/// redirect-upsert branch — after the tombstone-on-target check +
/// LWW gate have admitted the envelope. Running this preflight first
/// would let an envelope whose remapped row is already tombstoned
/// with a real DELETE — and is also waiting on a transient parent FK
/// target — sit in `sync_pending_inbox` for
/// `MAX_PENDING_INBOX_ATTEMPTS` retries before the dominating
/// tombstone could skip it. Mirrors the non-redirect branch ordering.
fn check_target_fk(
    conn: &Connection,
    remapped: &SyncEnvelope,
) -> Result<Option<ApplyResult>, ApplyError> {
    if let Some((dep_type, dep_id)) = check_fk_dependencies(
        conn,
        remapped.entity_type.as_str(),
        &remapped.entity_id,
        &remapped.payload,
    )? {
        return Ok(Some(ApplyResult::Deferred {
            reason: DeferralReason::MissingDependency {
                entity_type: dep_type,
                entity_id: dep_id,
            },
        }));
    }
    Ok(None)
}
