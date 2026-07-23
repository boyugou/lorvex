//! Per-row unindexed payload-shadow overlay path.
//!
//! [`merge_payload_with_shadow`] reconstructs the live payload for a
//! single `(entity_type, entity_id)` by overlaying the locally-known
//! fields onto the shadow's preserved forward-compat keys. It issues
//! two point-SELECTs (`sync_payload_shadow` and `sync_tombstones`) and
//! delegates the actual merge to
//! [`super::helpers::merge_payload_with_shadow_after_lookup`].
//!
//! Bulk callers (export pipelines that loop over many rows) should
//! switch to [`super::batch::merge_payload_with_shadow_indexed`] instead
//! to avoid those two point-SELECTs per row.

use super::helpers::{
    cross_type_redirect_tombstone_present, merge_payload_with_shadow_after_lookup,
};
use crate::error::PayloadError;
use rusqlite::Connection;
use serde_json::Value;

pub fn merge_payload_with_shadow(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    known_payload: &Value,
) -> Result<Value, PayloadError> {
    let Some(shadow) = super::super::crud::get_shadow(conn, entity_type, entity_id)? else {
        return Ok(known_payload.clone());
    };
    // detect a cross-type redirect tombstone at the
    // same `(entity_type, entity_id)` key as this shadow. When a
    // tombstone redirects (T1, id) → (T2, id) where T1 != T2, the
    // primitive `tombstone::create_tombstone` calls
    // `merge_shadow_into_redirect` which drops the loser-type shadow
    // (its forward-compat unknown keys can't safely cross schemas;
    // see `payload_shadow.rs:322-365`). But a race window exists: a
    // remote apply at (T1, id) authored by a peer that hadn't
    // observed the cross-type merge can re-create the shadow at the
    // loser-type key AFTER the local cross-type tombstone landed.
    // (The apply pipeline today routes cross-type-redirected envelopes
    // through `apply_envelope`'s redirect-chase branch which
    // re-targets at the redirect terminus, but
    // `finalize_payload_shadow` for non-redirected envelopes lands at
    // the original key.) If this stale shadow then meets a local
    // re-emit of (T1, id) — say, a `restore_from_tombstone` flow that
    // re-creates the loser-type entity — its forward-compat unknown
    // keys are written under the loser schema and merging them into
    // the live `known_payload` is correct (same entity, same shape).
    //
    // The pathological case is when the local re-emit is at the
    // WINNER type after the cross-type redirect: caller passes
    // (T2, id), `get_shadow` looks up at (T2, id) and might find
    // either a winner-type shadow (correct) or, in the cross-type
    // race, no shadow at all (also correct). The cross-type loser
    // shadow lives at (T1, id), so a (T2, id) caller never sees it
    // here.
    //
    // The remaining hazard: a legitimate-looking shadow at the same
    // `(entity_type, entity_id)` key as a cross-type-redirect
    // tombstone where the tombstone says "this id was redirected
    // FROM here to a different type". That shadow is stale forward-
    // compat data from before the cross-type merge; merging it into
    // a fresh local re-emit at the same loser type is logically
    // correct (the local write is reviving the loser-type entity at
    // the same id, schemas match) — but only if the tombstone has
    // since been removed by a real upsert at the loser id.
    // `enqueue_payload_internal` in
    // `lorvex-sync/src/outbox_enqueue/payload.rs` already removes the
    // tombstone before this site for an Upsert. So when we observe
    // both a shadow AND a cross-type redirect tombstone here, the
    // tombstone-remove ordering invariant has been violated — a
    // sibling caller (peer apply) raced with us and re-created the
    // tombstone after the local writer cleared it. Drop the shadow
    // rather than risk schema-incompatible field bleed-through.
    let cross_type_tombstone_present =
        cross_type_redirect_tombstone_present(conn, entity_type, entity_id)?;
    merge_payload_with_shadow_after_lookup(
        conn,
        entity_type,
        entity_id,
        known_payload,
        &shadow,
        cross_type_tombstone_present,
    )
}
