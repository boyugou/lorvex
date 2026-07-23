//! `upsert_shadow` strip semantics: known keys (the
//! `owned_keys_for_entity` allowlist) are stripped before persist;
//! unknown keys are preserved verbatim, and a payload with zero
//! owned-key matches round-trips byte-equal.

use super::support::*;

/// after `upsert_shadow` lands, the persisted
/// `raw_payload_json` row contains ONLY the unknown-key diff —
/// every key in `owned_keys_for_entity(entity_type)` is stripped
/// before write. The merge path overwrites known keys from the
/// live payload anyway, so storing them in the shadow doubles
/// disk usage without ever being read.
#[test]
fn upsert_shadow_strips_known_keys_before_persisting() {
    let conn = open_db_in_memory().unwrap();
    // Ship a full envelope shape: every owned task field plus
    // a forward-compat unknown key.
    upsert_shadow(
        &conn,
        ENTITY_TASK,
        "task-strip",
        "1711234567000_0000_a1b2c3d4a1b2c3d4",
        2,
        r#"{"id":"task-strip","title":"Original","status":"open","priority":1,"version":"1711234567000_0000_a1b2c3d4a1b2c3d4","unknown_field":"keep me"}"#,
        "device-test",
    )
    .unwrap();

    let stored = get_shadow(&conn, ENTITY_TASK, "task-strip")
        .unwrap()
        .expect("shadow row present");
    let stored_obj: Value = serde_json::from_str(&stored.raw_payload_json).unwrap();
    let stored_map = stored_obj
        .as_object()
        .expect("stored payload is JSON object");

    // The unknown key MUST survive the strip — that's the whole
    // purpose of the shadow.
    assert_eq!(
        stored_map.get("unknown_field").and_then(Value::as_str),
        Some("keep me"),
        "forward-compat unknown_field must survive the strip"
    );

    // Every owned task key MUST be absent after the strip.
    for owned_key in owned_keys_for_entity(ENTITY_TASK) {
        assert!(
            !stored_map.contains_key(*owned_key),
            "owned key {owned_key} should have been stripped from shadow but is still present"
        );
    }

    // And the round-trip merge must still produce a payload with
    // the known fields from the live envelope plus the preserved
    // unknown_field.
    let merged = merge_payload_with_shadow(
        &conn,
        ENTITY_TASK,
        "task-strip",
        &serde_json::json!({
            "id": "task-strip",
            "title": "Updated",
            "status": "completed",
        }),
    )
    .unwrap();
    assert_eq!(
        merged.get("title").and_then(Value::as_str),
        Some("Updated"),
        "merged payload uses live title, not stored shadow"
    );
    assert_eq!(
        merged.get("unknown_field").and_then(Value::as_str),
        Some("keep me"),
        "merged payload preserves the shadow's unknown_field"
    );
}

/// a shadow whose payload contains ONLY unknown
/// keys (zero owned keys to strip) must round-trip verbatim —
/// the helper short-circuits to avoid pointlessly re-serializing
/// (and therefore mutating canonical spacing).
#[test]
fn upsert_shadow_preserves_payload_when_no_owned_keys_match() {
    let conn = open_db_in_memory().unwrap();
    let raw = r#"{"unknown_a":1,"unknown_b":"xyz"}"#;
    upsert_shadow(
        &conn,
        ENTITY_TASK,
        "task-only-unknown",
        "1711234567000_0000_a1b2c3d4a1b2c3d4",
        2,
        raw,
        "device-test",
    )
    .unwrap();
    let stored = get_shadow(&conn, ENTITY_TASK, "task-only-unknown")
        .unwrap()
        .expect("shadow row present");
    assert_eq!(
        stored.raw_payload_json, raw,
        "no-op strip must persist the raw form verbatim"
    );
}
