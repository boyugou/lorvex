//! Shared utilities for the merge submodules.
//!
//! - [`cross_type_redirect_tombstone_present`] — same-key cross-type
//!   redirect probe consulted by both the unindexed
//!   `merge_payload_with_shadow` path and the indexed
//!   `merge_payload_with_shadow_indexed` path on the rare case where
//!   the [`super::ShadowIndex`] reports a redirect candidate.
//! - [`merge_payload_with_shadow_after_lookup`] — finalize step that
//!   overlays the known payload onto the shadow's forward-compat keys
//!   and gates the merged result against the
//!   `MAX_RAW_PAYLOAD_JSON_BYTES` cap. Shared between the unindexed
//!   and indexed entry points so both follow exactly the same merge
//!   semantics once the shadow + redirect lookups have resolved.
//! - [`parse_json_object`] — small `serde_json` helper that yields a
//!   typed `Map` and rejects non-object payloads with a typed
//!   `PayloadError::Serialization`.

use super::super::owned_keys::owned_keys_for_entity;
use super::super::{PayloadShadowRow, MAX_RAW_PAYLOAD_JSON_BYTES};
use crate::error::PayloadError;
use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{Map, Value};

/// Probe `sync_tombstones` for a same-key cross-type redirect: a row at
/// `(entity_type, entity_id)` whose `redirect_entity_type` points at a
/// *different* type. This is the legitimate-looking-but-stale shadow
/// case described in the merge body — see
/// [`super::single::merge_payload_with_shadow`] for the full hazard
/// analysis. Hot-path callers that already have a pre-built
/// [`super::ShadowIndex`] should skip this probe entirely when the
/// index proves no cross-type redirect exists.
pub(super) fn cross_type_redirect_tombstone_present(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
) -> Result<bool, PayloadError> {
    let present = conn
        .query_row(
            "SELECT redirect_entity_type FROM sync_tombstones \
             WHERE entity_type = ?1 AND entity_id = ?2 \
               AND redirect_entity_type IS NOT NULL \
               AND redirect_entity_type != ?1 \
             LIMIT 1",
            params![entity_type, entity_id],
            |row| row.get::<_, Option<String>>(0),
        )
        .optional()?
        .flatten()
        .is_some();
    Ok(present)
}

/// Shared finalize step for [`super::single::merge_payload_with_shadow`]
/// and the indexed variant: assumes the shadow row was already loaded
/// and the cross-type-redirect probe was already resolved (either via a
/// per-row SELECT or via a pre-built [`super::ShadowIndex`]).
pub(super) fn merge_payload_with_shadow_after_lookup(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    known_payload: &Value,
    shadow: &PayloadShadowRow,
    cross_type_tombstone_present: bool,
) -> Result<Value, PayloadError> {
    if cross_type_tombstone_present {
        crate::support::append_error_log_best_effort(
            conn,
            "store.payload_shadow.cross_type_redirect_shadow_drop",
            &format!(
                "merge_payload_with_shadow detected stale shadow at {entity_type}:{entity_id} \
                 alongside a cross-type redirect tombstone; dropping the shadow rather than \
                 cross-pollinating loser-schema unknown keys into the winner-type known payload"
            ),
            Some(&shadow.raw_payload_json),
            Some("warn"),
        );
        // Reap the stale shadow so a future merge call at the same
        // key cannot re-trigger the same drop. Best-effort: a
        // remove failure here must not eclipse the correctness of
        // the merge itself — but the previous `let _ =` swallowed
        // every failure silently, so a recurring SQLITE_BUSY (or
        // schema-drift) failure would loop forever invisibly. Funnel
        // through the diagnostic queue so a recurring error surfaces
        // in Settings → Diagnostics while the merge still returns
        // its correct value to the caller.
        if let Err(err) = super::super::crud::remove_shadow(conn, entity_type, entity_id) {
            crate::support::append_error_log_best_effort(
                conn,
                "store.payload_shadow.cross_type_redirect_cleanup",
                "stale cross-type shadow drop failed after merge",
                Some(&format!(
                    "entity_type={entity_type} entity_id={entity_id} error={err}"
                )),
                Some("warn"),
            );
        }
        return Ok(known_payload.clone());
    }

    let mut merged_obj = parse_json_object(
        &shadow.raw_payload_json,
        "sync payload shadow raw_payload_json",
    )?;
    let Some(known_obj) = known_payload.as_object() else {
        // Audit (payload_shadow F2): silently dropping shadow data
        // when the known payload is non-object hides a real handler
        // bug — the contract is "every entity carries a JSON object
        // payload." Return a typed error so the caller knows
        // forward-compat preservation could not run.
        //
        // The `Object` arm intentionally avoids `unreachable!()` —
        // although the let-else above proves `as_object()` returned
        // `None`, that macro is fragile against any future control-
        // flow refactor that lets a `serde_json::Value::Object` slip
        // past the let-else (e.g. an empty-object value matching
        // `as_object()` while a wrapping refactor reorders the
        // diagnostic). A `debug_assert!` plus a descriptive fallback
        // string keeps the contract enforced in test runs while
        // ensuring a release build can never abort the apply
        // pipeline on an adversarial payload that managed to thread
        // a non-object
        // shape into this branch. The diagnostic falls back to
        // "object" in release because that label is never wrong
        // about the case we actually mean to surface.
        let kind = match known_payload {
            Value::Null => "null",
            Value::Bool(_) => "bool",
            Value::Number(_) => "number",
            Value::String(_) => "string",
            Value::Array(_) => "array",
            Value::Object(_) => {
                debug_assert!(
                    false,
                    "merge_payload_with_shadow let-else proved known_payload is not an object \
                     yet the kind-discriminator hit Value::Object — sync apply contract violated"
                );
                "object"
            }
        };
        return Err(PayloadError::Validation(format!(
            "merge_payload_with_shadow expects an object payload for {entity_type}:{entity_id} (got {kind})"
        )));
    };

    for (key, value) in known_obj {
        merged_obj.insert(key.clone(), value.clone());
    }
    for key in owned_keys_for_entity(entity_type) {
        if !known_obj.contains_key(*key) {
            merged_obj.remove(*key);
        }
    }

    let merged = Value::Object(merged_obj);

    // bound the merged result before it propagates
    // upward into outbox enqueue / re-canonicalization. Inputs are
    // each individually capped — `validate_raw_payload_size` gates
    // every shadow row at `MAX_RAW_PAYLOAD_JSON_BYTES`, and the
    // canonical envelope is gated at the same byte budget upstream
    // — but the merge can still combine forward-compat unknown
    // keys (preserved across LWW conflicts) with a fresh known
    // payload such that the union exceeds either input. A 256 KiB
    // shadow holding forward-compat extras plus a 256 KiB known
    // payload would yield a ~500 KiB merged value that the next
    // canonicalize pass would reject deep inside outbox enqueue,
    // surfacing as a generic `Canonicalization(PayloadTooLarge)`
    // far from the actual cause. Bound at the boundary with a
    // typed `Validation` error so the caller sees exactly which
    // entity tripped the limit and which surface (the merge
    // boundary, not envelope canonicalization) detected it.
    //
    // The serialize-then-measure shape mirrors what
    // canonicalize/upsert_shadow do, and matches the behavior of
    // `validate_raw_payload_size` so the diagnostic is uniform
    // across the three writers that gate against this cap.
    let merged_serialized = serde_json::to_string(&merged)?;
    if merged_serialized.len() > MAX_RAW_PAYLOAD_JSON_BYTES {
        return Err(PayloadError::Validation(format!(
            "merge_payload_with_shadow merged payload for {entity_type}:{entity_id} \
             is {} bytes; exceeds maximum of {MAX_RAW_PAYLOAD_JSON_BYTES} bytes \
             (forward-compat unknown keys + known payload exceeded the cap)",
            merged_serialized.len()
        )));
    }

    Ok(merged)
}

pub(super) fn parse_json_object(
    raw: &str,
    context: &str,
) -> Result<Map<String, Value>, PayloadError> {
    match serde_json::from_str::<Value>(raw)? {
        Value::Object(object) => Ok(object),
        _ => Err(PayloadError::Serialization(format!(
            "{context} must be a JSON object"
        ))),
    }
}
