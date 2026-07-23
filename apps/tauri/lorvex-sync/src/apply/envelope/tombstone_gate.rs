//! Gates envelopes against existing non-redirect tombstones.

use rusqlite::Connection;

use lorvex_domain::hlc::Hlc;

use super::super::conflict::reap_shadow_for_skipped;
use super::super::{ApplyError, ApplyResult};
use crate::envelope::{SyncEnvelope, SyncOperation};
use crate::tombstone::{create_tombstone, remove_tombstone, Tombstone};

pub(super) fn gate_existing_tombstone(
    conn: &Connection,
    envelope: &SyncEnvelope,
    ts: &Tombstone,
    apply_ts: &str,
) -> Result<Option<ApplyResult>, ApplyError> {
    // Normal delete tombstone — compare versions.
    // `envelope.version` is typed `Hlc` at the wire
    // boundary; tombstone rows still carry storage-side `String`.
    let tombstone_version = Hlc::parse(&ts.version)?;
    let envelope_version = &envelope.version;

    if envelope.operation == SyncOperation::Upsert {
        if envelope_version > &tombstone_version {
            // Concurrent-update-wins-over-concurrent-delete: the upsert is
            // strictly newer than the delete. Log the resolution
            // before removing the tombstone, mirroring every other
            // LWW outcome in this module (the prior shape silently
            // undid a real DELETE the cluster had agreed on, leaving
            // operators with no audit trail for "why did this
            // previously-deleted entity reappear?" in Settings →
            // Diagnostics).
            crate::conflict_log::log_conflict(
                conn,
                &crate::conflict_log::ConflictLogEntry {
                    id: 0,
                    entity_type: std::borrow::Cow::Borrowed(envelope.entity_type.as_str()),
                    entity_id: envelope.entity_id.clone(),
                    winner_version: envelope.version.to_string(),
                    loser_version: ts.version.clone(),
                    loser_device_id: envelope.device_id.clone(),
                    loser_payload: None,
                    resolved_at: apply_ts.to_string(),
                    resolution_type: std::borrow::Cow::Borrowed(
                        lorvex_domain::naming::RESOLUTION_UPSERT_WINS_OVER_DELETE,
                    ),
                },
            )?;
            remove_tombstone(conn, envelope.entity_type.as_str(), &envelope.entity_id)?;
            // Fall through to apply the upsert below.
        } else {
            // Delete is newer or concurrent-equal: discard the upsert.
            // log the conflict so the diagnostics
            // panel shows the dropped envelope. The non-redirect
            // tombstone-vs-upsert skip vanish silently.
            crate::conflict_log::log_conflict(
                conn,
                &crate::conflict_log::ConflictLogEntry {
                    id: 0,
                    entity_type: std::borrow::Cow::Borrowed(envelope.entity_type.as_str()),
                    entity_id: envelope.entity_id.clone(),
                    winner_version: ts.version.clone(),
                    loser_version: envelope.version.to_string(),
                    loser_device_id: envelope.device_id.clone(),
                    loser_payload: Some(envelope.payload.clone()),
                    resolved_at: apply_ts.to_string(),
                    resolution_type: std::borrow::Cow::Borrowed(
                        lorvex_domain::naming::RESOLUTION_TOMBSTONE_WINS,
                    ),
                },
            )?;
            // reap any payload shadow whose
            // base_version is older than the tombstone version
            // — the entity is dead, the shadow can never legally
            // promote.
            reap_shadow_for_skipped(
                conn,
                envelope.entity_type.as_str(),
                &envelope.entity_id,
                &ts.version,
            )?;
            // typed winner = the tombstone HLC.
            // `tombstone_version` was already parsed above.
            return Ok(Some(ApplyResult::Skipped {
                reason: format!(
                    "entity {}:{} is tombstoned with version {} >= envelope version {}",
                    envelope.entity_type, envelope.entity_id, ts.version, envelope.version
                ),
                winner_version: Some(tombstone_version),
            }));
        }
    }
    if envelope.operation == SyncOperation::Delete {
        if envelope_version > &tombstone_version {
            // The entity row is already gone, but a later delete
            // is still semantically meaningful: it advances the
            // delete frontier that future stale upserts must lose
            // against. Do the tombstone write here instead of
            // short-circuiting so the same monotonic primitive owns
            // redirects, shadow cleanup, and storage taint handling.
            create_tombstone(
                conn,
                envelope.entity_type.as_str(),
                &envelope.entity_id,
                &envelope.version.to_string(),
                apply_ts,
                None,
                None,
            )?;
            return Ok(Some(ApplyResult::Applied));
        }
        // Older/equal replays remain idempotent no-ops. Any lingering
        // shadow older than the winning tombstone is permanently
        // obsolete, so reap it before returning.
        reap_shadow_for_skipped(
            conn,
            envelope.entity_type.as_str(),
            &envelope.entity_id,
            &ts.version,
        )?;
        return Ok(Some(ApplyResult::Skipped {
            reason: format!(
                "entity {}:{} is already tombstoned at version {} >= delete envelope version {}",
                envelope.entity_type, envelope.entity_id, ts.version, envelope.version
            ),
            winner_version: Some(tombstone_version),
        }));
    }
    Ok(None)
}
