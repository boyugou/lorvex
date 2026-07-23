//! Build the remapped envelope by chasing the redirect chain.

use rusqlite::Connection;

use super::super::super::redirect::{chase_redirect_chain, RedirectHop};
use super::super::super::ApplyError;
use crate::envelope::SyncEnvelope;

pub(super) fn build_remapped_envelope(
    conn: &Connection,
    envelope: &SyncEnvelope,
) -> Result<(Vec<RedirectHop>, SyncEnvelope), ApplyError> {
    // Tombstone with redirect (merge loser) — remap the envelope
    // to point at the redirect target and apply it, so edges
    // like task_tag are re-applied with the winner's ID.
    //
    // the chase is delegated to the shared
    // `chase_redirect_chain` helper so `apply_envelope` and
    // `promote_one_shadow` walk the chain identically (cap,
    // cycle detection, cross-type honor, deep-chain error).
    // The helper returns the per-hop log so this site can
    // still do the per-hop work it always did — payload
    // identity rewrites, local-attribution check — without
    // duplicating the chase logic.
    let (final_type, final_id, hops) =
        chase_redirect_chain(conn, envelope.entity_type.as_str(), &envelope.entity_id)?;
    // Build the remapped envelope without cloning the inbound
    // payload. The redirect-chase path either (a) re-serializes a
    // freshly-canonicalized payload after the FK-rewrite pass — in
    // which case any inbound `payload` clone would be wasted — or
    // (b) leaves payload untouched only when JSON parse failed,
    // where downstream `apply_entity` surfaces `InvalidPayload`.
    // A naive `envelope.clone()` would copy up to
    // `MAX_RAW_PAYLOAD_JSON_BYTES` (256 KiB) on every envelope that
    // takes the redirect branch — a notable cost during cluster-
    // wide tag-merge cascades. Start with an empty placeholder
    // payload and overwrite it after the FK-rewrite loop; the
    // unparseable-payload fallback re-clones once (cheap relative
    // to clone-then-overwrite-and-discard).
    let mut remapped = SyncEnvelope {
        entity_type: envelope.entity_type,
        entity_id: final_id,
        operation: envelope.operation.clone(),
        version: envelope.version.clone(),
        payload_schema_version: envelope.payload_schema_version,
        payload: String::new(),
        device_id: envelope.device_id.clone(),
    };
    // a cross-type chain hop changes the
    // entity_type the apply pipeline routes against. Without
    // this, the dispatcher used the original envelope type
    // and INSERTed against the wrong table.
    //
    // `chase_redirect_chain` still returns the
    // string form (the tombstone table stores TEXT), so parse
    // back into the typed `EntityKind` to satisfy the wire-
    // boundary type. An unknown redirect target here is a
    // schema-side invariant violation, not a forward-compat
    // case — the tombstone writer always stores a known kind.
    remapped.entity_type =
        lorvex_domain::naming::EntityKind::parse(&final_type).ok_or_else(|| {
            ApplyError::UnknownEntityType(format!(
                "redirect chain terminus has unknown entity_type: {final_type}"
            ))
        })?;
    Ok((hops, remapped))
}
