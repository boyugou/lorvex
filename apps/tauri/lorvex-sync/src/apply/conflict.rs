//! Conflict-log + shadow-reap helpers for LWW-loser and tombstone-loser
//! skip paths.
//!
//! The two skip-and-log helpers (`record_lww_conflict_and_skip`,
//! `reap_shadow_for_skipped`) live together because both paths share
//! the invariant that any payload shadow whose `base_version` is older
//! than the superseding version must be reaped before the next promote
//! pass.

use rusqlite::Connection;

use lorvex_domain::hlc::Hlc;
use lorvex_domain::naming;

use super::{ApplyError, ApplyResult};
use crate::conflict_log::{log_conflict, ConflictLogEntry};
use crate::envelope::SyncEnvelope;

/// Record an LWW-loser conflict and return the matching `Skipped` apply
/// result. Both the redirect-target branch and the normal-LWW branch
/// share this exact shape: the same `ConflictLogEntry` plus an
/// identical "local newer than remote" message format.
///
/// Centralizing the construction prevents drift if either site grows a
/// new field (e.g. a `resolution_reason` distinguishing "local edit
/// wins" from "remote stale by N hours") in the future.
///
/// takes a typed [`Hlc`] for `local_version` rather
/// than a raw string. Both call sites have already round-tripped the
/// local-version string through `Hlc::parse` (it is the gate that
/// selects the LWW-loser branch in the first place), so the prior
/// shape — re-deriving the typed `winner_version` from the string
/// inside this helper — re-parsed an already-parsed value AND papered
/// over the rare-but-possible case where the caller's gate parsed
/// successfully but a corrupt string later sneaked through (e.g. a
/// future caller that bypassed the gate). Threading the typed `Hlc`
/// makes `winner_version` infallibly populated and the canonical
/// `to_string()` serializes the conflict-log row.
pub(super) fn record_lww_conflict_and_skip(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    local_version: &Hlc,
    envelope: &SyncEnvelope,
    skip_reason: String,
    apply_ts: &str,
) -> Result<ApplyResult, ApplyError> {
    let local_version_str = local_version.to_string();
    log_conflict(
        conn,
        &ConflictLogEntry {
            id: 0,
            entity_type: std::borrow::Cow::Owned(entity_type.to_string()),
            entity_id: entity_id.to_string(),
            winner_version: local_version_str.clone(),
            loser_version: envelope.version.to_string(),
            loser_device_id: envelope.device_id.clone(),
            loser_payload: Some(envelope.payload.clone()),
            resolved_at: apply_ts.to_string(),
            resolution_type: std::borrow::Cow::Borrowed(naming::RESOLUTION_LWW),
        },
    )?;
    // a Skipped envelope where the local version is
    // strictly greater than ANY shadow's `base_version` for the same
    // (entity_type, entity_id) means that shadow can never legally
    // promote — promoting it would either resurrect stale forward-
    // compat fields or refuse the INSERT under the SQL `>=` gate
    // and silently drop the shadow's contents. Reap it now so a
    // future `promote_payload_shadows` pass can't accidentally
    // replay it. The helper bails out cleanly when no shadow exists
    // or its base_version is newer than the local version, so it's
    // safe to call unconditionally on every LWW-loser skip.
    lorvex_sync_payload::payload_shadow::remove_shadow_if_superseded(
        conn,
        entity_type,
        entity_id,
        &local_version_str,
    )?;
    // typed `winner_version` is the caller's own
    // parsed `Hlc`, no re-parse needed.
    Ok(ApplyResult::Skipped {
        reason: skip_reason,
        winner_version: Some(local_version.clone()),
    })
}

/// companion to `record_lww_conflict_and_skip` for
/// the non-LWW Skipped paths (tombstone-wins,
/// delete-on-already-tombstoned). Same shape: when we know the
/// entity has a definite "current version" — typically the
/// tombstone's version — every payload shadow whose `base_version`
/// is older than that version is obsolete and must be dropped
/// before the next promote pass.
pub(super) fn reap_shadow_for_skipped(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    superseding_version: &str,
) -> Result<(), ApplyError> {
    lorvex_sync_payload::payload_shadow::remove_shadow_if_superseded(
        conn,
        entity_type,
        entity_id,
        superseding_version,
    )?;
    Ok(())
}
