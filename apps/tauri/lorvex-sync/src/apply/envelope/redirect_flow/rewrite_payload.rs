//! Per-hop payload identity rewrite + canonical re-serialization.

use rusqlite::Connection;

use lorvex_domain::hlc::Hlc;
use lorvex_sync_payload::payload_shadow::MAX_RAW_PAYLOAD_JSON_BYTES;

use super::super::super::collision::read_local_device_identity;
use super::super::super::redirect::{remap_payload_identity_fields, RedirectHop};
use super::super::super::ApplyError;
use crate::canonicalize::canonicalize_json;
use crate::envelope::SyncEnvelope;

pub(super) fn rewrite_remapped_payload(
    conn: &Connection,
    envelope: &SyncEnvelope,
    remapped: &mut SyncEnvelope,
    hops: &[RedirectHop],
) -> Result<(), ApplyError> {
    // when the redirect chain crosses a
    // tombstone authored by the LOCAL device (tag merge,
    // recurrence dedup), the apply that follows is logically
    // a local rewrite of the remote envelope onto the merge
    // winner — the merge tombstone is what caused the remap,
    // and the local device authored that decision. Any
    // conflict_log entry, error_log entry, or payload-shadow
    // promotion the remapped envelope produces must be
    // attributed to the LOCAL device, not the original peer.
    //
    // the capture intentionally happens
    // ONCE before the redirect chase loop and is reused at
    // every hop. This is safe because `apply_envelope` runs
    // under the global writer mutex (the outer `BEGIN
    // IMMEDIATE` documented at the function header is
    // serialized by `with_immediate_transaction`), so no
    // concurrent path can mutate
    // `sync_checkpoints.device_id` or its alias suffix list
    // mid-apply.
    let local_identity = read_local_device_identity(conn);
    let merge_authored_locally = |version: &str| -> bool {
        let Some((_, ref suffixes)) = local_identity else {
            return false;
        };
        Hlc::parse(version).is_ok_and(|h| suffixes.iter().any(|s| s == h.device_suffix()))
    };

    // also rewrite payload-FK identity fields
    // so the apply pipeline (and any forward-compat shadow
    // we finalize at the end) carries the winner's id rather
    // than the loser's. Operating on a parsed `Value` across
    // the chase keeps the multi-hop case (A→B→C) coherent
    // without re-parsing the JSON string at every step.
    //
    // Parse the original `envelope.payload`. `remapped.payload` is
    // initialized empty; the canonical form is written back once the
    // FK rewrites settle. Parsing from the original (rather than
    // cloning into `remapped` first) avoids the eager clone an
    // `envelope.clone()` would pay on every redirected envelope.
    let mut payload_value: Option<serde_json::Value> = serde_json::from_str(&envelope.payload).ok();

    // Per-hop work. Iterating the captured hop log re-attributes on
    // every hop authored locally and rewrites payload identity
    // fields for every hop's (from→to). The hop list already filters
    // out absolute-deletion tombstones and is bounded by
    // `REDIRECT_CHAIN_CAP`.
    for hop in hops {
        if merge_authored_locally(&hop.version) {
            if let Some((ref local_device_id, _)) = local_identity {
                // `clone_from` reuses `remapped.device_id`'s
                // existing String allocation when its capacity is
                // sufficient; on the bulk peer-restore replay path
                // this avoids a fresh heap alloc per hop.
                remapped.device_id.clone_from(local_device_id);
            }
        }
        if let Some(ref mut payload_value) = payload_value {
            // Use the hop's from-type so the rewrite table
            // dispatches against the type the payload was
            // authored under — for cross-type hops the
            // outgoing JSON shape is still the from-type's
            // schema until apply normalizes it.
            remap_payload_identity_fields(
                &hop.from_entity_type,
                payload_value,
                &hop.from_entity_id,
                &hop.to_entity_id,
            );
        }
    }

    // Re-serialize the (possibly mutated) payload into the
    // remapped envelope. If the payload wasn't parseable to
    // begin with we leave it untouched — downstream
    // `apply_entity` will surface the InvalidPayload error
    // with full context rather than swallowing it here.
    //
    // Route the re-serialization through the canonical writer so the
    // resulting bytes are byte-identical to what the authoring peer
    // would have sent post-merge. A bare `serde_json::to_string` only
    // emits alphabetically-sorted keys because `serde_json::Map` is
    // `BTreeMap` by default — switching serde_json's `preserve_order`
    // feature on (or shipping a peer that does) would silently break
    // content-addressed dedupe between this re-serialized form and
    // the canonical form every other writer in the apply / outbox
    // pipeline produces. The canonicalize crate is the single source
    // of truth for "what does the wire form look like for this value
    // tree"; routing through it locks the contract in place. The
    // default-features serde_json contract is documented in
    // `lorvex-sync/Cargo.toml` (`serde_json` dep MUST stay on default
    // features so `Map = BTreeMap`).
    //
    // validate the re-serialized size against
    // `MAX_RAW_PAYLOAD_JSON_BYTES` before forwarding. The
    // input payload was already capped by upstream canonical-
    // ization (`MAX_CANONICAL_PAYLOAD_BYTES = 256 KiB`), but
    // a multi-hop FK rewrite that happens to swap a short
    // loser-id for a longer winner-id (UUIDv7 vs ULID, or a
    // padded-prefix variant) can grow the canonical form past
    // the cap by O(hops × delta-id-bytes × number of FK
    // fields). Surfacing the limit here keeps the diagnostic
    // adjacent to the redirect chain that produced the
    // over-sized result; without this guard the over-sized
    // payload would propagate into `apply_entity` /
    // `finalize_payload_shadow` where the size check fires
    // deep inside the storage boundary, far from the actual
    // cause.
    if let Some(ref payload_value) = payload_value {
        let serialized = canonicalize_json(payload_value).map_err(|e| {
            ApplyError::InvalidPayload(format!(
                "redirect-chase payload re-serialization failed for {}:{} -> {}:{}: {e}",
                envelope.entity_type, envelope.entity_id, remapped.entity_type, remapped.entity_id
            ))
        })?;
        if serialized.len() > MAX_RAW_PAYLOAD_JSON_BYTES {
            return Err(ApplyError::RedirectPayloadTooLarge {
                entity_type: remapped.entity_type,
                entity_id: remapped.entity_id.clone(),
                size_bytes: serialized.len(),
            });
        }
        remapped.payload = serialized;
    } else {
        // Unparseable-payload branch. Restore the original verbatim
        // so downstream `apply_entity` surfaces the same
        // `InvalidPayload` error with the original bytes for
        // diagnostics. (Without this restore, `remapped.payload`
        // would be empty because we deliberately skipped the
        // eager-clone above.) `clone_from` reuses the empty
        // `remapped.payload` allocation if it had any capacity.
        remapped.payload.clone_from(&envelope.payload);
    }
    Ok(())
}
