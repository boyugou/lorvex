//! Orchestrator for the redirected-tombstone apply path.

use rusqlite::Connection;

use lorvex_domain::capability::EnvelopeAcceptance;

use super::super::super::{ApplyError, ApplyResult};
use super::super::{apply_entity, finalize_payload_shadow};
use super::delete_drop::drop_redirected_delete;
use super::remap_envelope::build_remapped_envelope;
use super::rewrite_payload::rewrite_remapped_payload;
use super::upsert_gate::gate_redirected_upsert;
use crate::envelope::SyncEnvelope;
use crate::tombstone::Tombstone;

pub(in crate::apply::envelope) fn apply_redirected_tombstone(
    conn: &Connection,
    envelope: &SyncEnvelope,
    ts: &Tombstone,
    acceptance: EnvelopeAcceptance,
    apply_ts: &str,
) -> Result<ApplyResult, ApplyError> {
    let (hops, mut remapped) = build_remapped_envelope(conn, envelope)?;

    if let Some(result) = drop_redirected_delete(conn, envelope, &remapped, &hops, ts, apply_ts)? {
        return Ok(result);
    }

    rewrite_remapped_payload(conn, envelope, &mut remapped, &hops)?;

    if let Some(result) = gate_redirected_upsert(conn, envelope, &remapped, acceptance, apply_ts)? {
        return Ok(result);
    }

    // Apply the remapped envelope (tombstone checks already done above;
    // LWW guarded for upserts).
    apply_entity(conn, &remapped, apply_ts)?;
    finalize_payload_shadow(conn, acceptance, &remapped)?;
    Ok(ApplyResult::Remapped {
        from_entity_id: envelope.entity_id.clone(),
        to_entity_id: remapped.entity_id,
    })
}
