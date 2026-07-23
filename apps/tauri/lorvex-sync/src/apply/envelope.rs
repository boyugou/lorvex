//! `apply_envelope` entry point and its supporting plumbing — the
//! pipeline that processes a single inbound sync envelope.
//!
//! The entry point owns envelope-stage ordering; focused child modules
//! own payload-shadow finalization, FK preflight, local-version lookup,
//! and dispatch wrappers so the apply boundary stays readable.

use rusqlite::Connection;

use lorvex_domain::capability::{check_envelope_version, EnvelopeAcceptance};
use lorvex_domain::naming::EntityKind;
use lorvex_domain::version::PAYLOAD_SCHEMA_VERSION;

use super::collision::check_device_identity_collision;
use super::{ApplyError, ApplyResult, DeferralReason};
use crate::envelope::SyncEnvelope;
use crate::tombstone::get_tombstone;

mod delete_flow;
mod dispatching;
mod fk;
mod lww_gate;
mod payload_shadow;
mod redirect_flow;
mod tombstone_gate;
mod version;

use self::dispatching::apply_entity;
pub(super) use self::dispatching::apply_entity_with_version_mode;
pub(super) use self::fk::check_fk_dependencies;
use self::payload_shadow::finalize_payload_shadow;
pub(crate) use self::version::get_local_version;

fn validate_apply_entity_id(envelope: &SyncEnvelope) -> Result<(), ApplyError> {
    lorvex_domain::validate_sync_entity_id_for_kind(envelope.entity_type, &envelope.entity_id)
        .map_err(|error| {
            ApplyError::InvalidPayload(format!(
                "sync envelope entity_id for {} must be canonical: {error}",
                envelope.entity_type
            ))
        })
}

fn defer_forward_compatible_append_only_changelog(
    acceptance: EnvelopeAcceptance,
    envelope: &SyncEnvelope,
) -> Option<ApplyResult> {
    if matches!(acceptance, EnvelopeAcceptance::ParseForwardCompat)
        && envelope.entity_type == EntityKind::AiChangelog
    {
        return Some(ApplyResult::Deferred {
            reason: DeferralReason::SchemaTooNew {
                remote_version: envelope.payload_schema_version,
                local_version: PAYLOAD_SCHEMA_VERSION,
            },
        });
    }
    None
}

/// Apply a single sync envelope to the database.
///
/// Returns whether the envelope was applied, skipped, deferred, or remapped.
///
/// This function is idempotent: calling it N times with the same envelope
/// produces the same database state as calling it once.
///
/// # Transaction invariant
///
/// `apply_envelope` MUST be called inside an outer transaction (in
/// production via `with_immediate_transaction`; in unit tests via the
/// `BEGIN IMMEDIATE` opened in `test_db`). The pipeline does many
/// writes — version stamping, tombstone creation, payload-shadow
/// finalization, FK preflight, conflict-log + error-log inserts —
/// that must commit or roll back atomically. A partial-failure
/// window (disk full, FK violation, panic) without an outer txn
/// would leave divergent local state: tombstone written but row not
/// removed, shadow promoted but conflict log not written, etc.
///
/// The aggregate / edge / tag apply paths nest SAVEPOINTs inside
/// this outer txn (`apply/edge/dependency.rs`, `apply/aggregate/recurrence.rs`,
/// `apply/tag.rs`); SAVEPOINTs require a transaction to nest into.
/// A release-mode guard on `!conn.is_autocommit()` trips immediately
/// when a future caller forgets the wrapper, surfacing the bug at
/// the apply boundary instead of as a confusing "cannot start a
/// transaction within a transaction" or silent partial-write later.
pub fn apply_envelope(
    conn: &Connection,
    envelope: &SyncEnvelope,
) -> Result<ApplyResult, ApplyError> {
    if conn.is_autocommit() {
        return Err(ApplyError::TransactionRequired);
    }

    // Capture the apply timestamp ONCE at envelope entry and thread
    // it through every helper that needs a `resolved_at` /
    // `deleted_at` timestamp. Calling
    // `lorvex_domain::sync_timestamp_now()` at every site (tombstone
    // creation, cascading-children helpers, conflict-log inserts,
    // recurrence / tag merges) would
    // make every clock read independent — within a single envelope
    // apply the resulting timestamps could differ by microseconds,
    // producing mismatched correlated `deleted_at` rows in the
    // cascade tombstones a single delete authored. Threading one
    // captured value gives every site the same atomic moment of
    // apply.
    let apply_ts = lorvex_domain::sync_timestamp_now();
    // detect full-device-id collision at apply time. If
    // the envelope's HLC version carries our own 8-char device_suffix
    // but the envelope's `device_id` field doesn't match our
    // `sync_checkpoints.device_id`, the remote is almost certainly a
    // cloned/forked DB (remote restore to a new machine, filesystem copy
    // to a second user profile) whose suffix happens to match ours.
    // The collision is catastrophic and silent: our LWW tie-break is
    // suffix-equal-means-same-device, which is now false; HLC seeding
    // inadvertently pulls in the other device's max HLC; subsequent
    // legitimate writes from either device lose LWW on rebroadcast.
    //
    // Log one `error_logs` row per process lifetime (guarded by a
    // static `AtomicBool`) so a clone-DB scenario surfaces visibly in
    // Settings → Diagnostics without flooding the log during a single
    // sync batch. Fix: user regenerates `sync_checkpoints.device_id`
    // on the cloned install. (A stronger fix — provider device
    // registry uniqueness, suffix widening — is tracked as follow-ups
    // under #2192's layer 2/3.)
    check_device_identity_collision(conn, envelope);

    // 1. Check envelope payload_schema_version
    let acceptance =
        check_envelope_version(envelope.payload_schema_version, PAYLOAD_SCHEMA_VERSION);
    match acceptance {
        // Both parse paths fall through to apply; ParseForwardCompat
        // simply means we proceed with the known fields and ignore
        // any extras the payload may carry.
        EnvelopeAcceptance::ParseFully | EnvelopeAcceptance::ParseForwardCompat => {}
        EnvelopeAcceptance::DeferToPendingInbox => {
            return Ok(ApplyResult::Deferred {
                reason: DeferralReason::SchemaTooNew {
                    remote_version: envelope.payload_schema_version,
                    local_version: PAYLOAD_SCHEMA_VERSION,
                },
            });
        }
    }

    if let Some(result) = defer_forward_compatible_append_only_changelog(acceptance, envelope) {
        return Ok(result);
    }

    // Filter local-only kinds (`device_state`, `feedback`,
    // `saved_query`, `import_session`) that must never round-trip
    // through cross-device sync even if a peer somehow emitted one.
    //
    // post #3004-H1 the wire boundary is typed: `entity_type` is an
    // `EntityKind`, so an unrecognized string already fails at
    // `serde_json::from_str` and never reaches here. The remaining
    // job of this gate is purely to filter local-only kinds: observe
    // the HLC, skip the envelope, surface the reason. The envelope
    // still consumes the receive_watermark so the cluster continues
    // to converge on the rest of the schema.
    if !envelope.entity_type.is_syncable_kind() {
        return Ok(ApplyResult::Skipped {
            reason: format!(
                "non-syncable entity_type {} — ignored (local-only kind)",
                envelope.entity_type
            ),
            // Forward-compat skip: no LWW comparison happened, so no
            // typed winner exists.
            winner_version: None,
        });
    }

    validate_apply_entity_id(envelope)?;

    // 2. Check if entity is tombstoned
    let tombstone = get_tombstone(conn, envelope.entity_type.as_str(), &envelope.entity_id)?;

    if let Some(ts) = tombstone {
        if ts.redirect_entity_id.is_some() {
            return redirect_flow::apply_redirected_tombstone(
                conn, envelope, &ts, acceptance, &apply_ts,
            );
        }

        if let Some(result) =
            tombstone_gate::gate_existing_tombstone(conn, envelope, &ts, &apply_ts)?
        {
            return Ok(result);
        }
    }

    if let Some(result) = lww_gate::gate_lww_and_fk(conn, envelope, &apply_ts)? {
        return Ok(result);
    }

    // 4. Delegate to entity-specific handler.
    let entity_outcome = apply_entity(conn, envelope, &apply_ts)?;

    delete_flow::finalize_entity_outcome(conn, envelope, entity_outcome, acceptance, &apply_ts)
}
