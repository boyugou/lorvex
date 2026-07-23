use super::*;

#[test]
fn typed_envelope_round_trips_through_serde() {
    // the wire format must stay byte-identical to
    // the pre-typed shape. Build a typed envelope, serialize it,
    // and confirm the JSON contains the same lowercase entity-type
    // tag the old `String` shape emitted.
    let envelope = SyncEnvelope {
        entity_type: EntityKind::Task,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000000001".to_string(),
        operation: SyncOperation::Upsert,
        version: Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4").unwrap(),
        payload_schema_version: 1,
        payload: r#"{"title":"test"}"#.to_string(),
        device_id: "device-001".to_string(),
    };
    let json = serde_json::to_string(&envelope).unwrap();
    assert!(
        json.contains(r#""entity_type":"task""#),
        "entity_type must serialize as canonical lowercase string: {json}"
    );
    let parsed: SyncEnvelope = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed.entity_type, EntityKind::Task);
    assert_eq!(parsed.operation, SyncOperation::Upsert);
}

#[test]
fn deserialize_rejects_unknown_entity_type() {
    // the typed `entity_type: EntityKind` field
    // turns "unknown entity kind" into a serde-level rejection at
    // the wire boundary. Unknown operation kinds now use the same
    // fail-closed boundary so transport checkpoints cannot advance
    // past semantics the local build does not understand.
    let json = r#"{
        "entity_type": "future_unknown_kind",
        "entity_id": "01966a3f-7c8b-7d4e-8f3a-000000000001",
        "operation": "upsert",
        "version": "1711234567890_0000_a1b2c3d4a1b2c3d4",
        "payload_schema_version": 1,
        "payload": "{}",
        "device_id": "device-001"
    }"#;
    serde_json::from_str::<SyncEnvelope>(json)
        .expect_err("unknown entity kind must fail to deserialize");
}

#[test]
fn test_operation_serializes_snake_case() {
    let json = serde_json::to_string(&SyncOperation::Upsert).unwrap();
    assert_eq!(json, r#""upsert""#);
    let json = serde_json::to_string(&SyncOperation::Delete).unwrap();
    assert_eq!(json, r#""delete""#);
}

#[test]
fn deserialize_rejects_unknown_operation() {
    // A future peer's envelope with `"operation": "merge"` must fail
    // at the wire boundary. Skipping it would let pull checkpoints
    // advance past a mutation whose semantics this build cannot
    // interpret.
    serde_json::from_str::<SyncOperation>(r#""merge""#)
        .expect_err("unknown operation kind must fail to deserialize");

    let json = r#"{
        "entity_type": "task",
        "entity_id": "01966a3f-7c8b-7d4e-8f3a-000000000001",
        "operation": "future_rekey",
        "version": "1711234567890_0000_a1b2c3d4a1b2c3d4",
        "payload_schema_version": 1,
        "payload": "{}",
        "device_id": "device-001"
    }"#;
    serde_json::from_str::<SyncEnvelope>(json)
        .expect_err("envelopes with unknown operation kind must fail to deserialize");
}

#[test]
fn envelope_accepts_unknown_top_level_fields() {
    // future envelope-level additive fields (signature,
    // compression, etc.) must not cause deserialization to fail on
    // an older peer. The forward-compat machinery in `apply_envelope`
    // never runs if serde rejects the envelope first.
    let json = r#"{
        "entity_type": "task",
        "entity_id": "01966a3f-7c8b-7d4e-8f3a-000000000001",
        "operation": "upsert",
        "version": "1711234567890_0000_a1b2c3d4a1b2c3d4",
        "payload_schema_version": 1,
        "payload": "{\"title\":\"test\"}",
        "device_id": "device-001",
        "future_signature": "abc123",
        "future_compression": "zstd"
    }"#;
    let parsed: SyncEnvelope =
        serde_json::from_str(json).expect("envelope must accept unknown fields");
    assert_eq!(parsed.entity_type, EntityKind::Task);
    assert_eq!(parsed.operation, SyncOperation::Upsert);
}

fn well_formed_envelope() -> SyncEnvelope {
    SyncEnvelope {
        entity_type: EntityKind::Task,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000000001".to_string(),
        operation: SyncOperation::Upsert,
        version: Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4").unwrap(),
        payload_schema_version: 1,
        payload: r#"{"title":"test"}"#.to_string(),
        device_id: "device-001".to_string(),
    }
}

#[test]
fn validate_accepts_well_formed_envelope() {
    well_formed_envelope()
        .validate()
        .expect("canonical envelope should validate");
}

// the previous `validate_rejects_empty_entity_type`
// test asserted that an empty `entity_type` string was rejected by
// `validate()`. With `entity_type: EntityKind`, an empty value is
// structurally unrepresentable — serde rejects unknown / empty
// entity_type at deserialization, and the only way to construct a
// `SyncEnvelope` programmatically is by supplying a valid variant.
// The corresponding wire-boundary check now lives in
// `deserialize_rejects_unknown_entity_type` above.

#[test]
fn validate_rejects_oversized_payload() {
    let mut env = well_formed_envelope();
    env.payload = "x".repeat(MAX_ENVELOPE_PAYLOAD_BYTES + 1);
    match env.validate() {
        Err(EnvelopeValidationError::FieldTooLong { field, len, max }) => {
            assert_eq!(field, "payload");
            assert_eq!(len, MAX_ENVELOPE_PAYLOAD_BYTES + 1);
            assert_eq!(max, MAX_ENVELOPE_PAYLOAD_BYTES);
        }
        other => panic!("expected FieldTooLong, got {other:?}"),
    }
}

#[test]
fn validate_rejects_oversized_device_id() {
    let mut env = well_formed_envelope();
    env.device_id = "x".repeat(MAX_ENVELOPE_DEVICE_ID_LEN + 1);
    match env.validate() {
        Err(EnvelopeValidationError::FieldTooLong { field, .. }) => {
            assert_eq!(field, "device_id");
        }
        other => panic!("expected FieldTooLong, got {other:?}"),
    }
}

#[test]
fn validate_rejects_path_traversal_entity_id() {
    // a crafted record_name like `task_../../../etc/passwd`
    // decodes into `entity_id = "../../../etc/passwd"` after the
    // provider sanitizer (which only strips colons). Reject at the
    // envelope boundary.
    let mut env = well_formed_envelope();
    env.entity_id = "../../../etc/passwd".to_string();
    match env.validate() {
        Err(EnvelopeValidationError::UnsafeEntityId { reason, .. }) => {
            assert!(
                reason.contains("path-traversal"),
                "unexpected reason: {reason}"
            );
        }
        other => panic!("expected UnsafeEntityId, got {other:?}"),
    }
}

#[test]
fn validate_rejects_path_separator_entity_id() {
    let mut env = well_formed_envelope();
    env.entity_id = "task/secrets".to_string();
    match env.validate() {
        Err(EnvelopeValidationError::UnsafeEntityId { reason, .. }) => {
            assert!(reason.contains("path separator"));
        }
        other => panic!("expected UnsafeEntityId, got {other:?}"),
    }
}

#[test]
fn validate_rejects_control_char_entity_id() {
    let mut env = well_formed_envelope();
    env.entity_id = "task-\u{001B}inject".to_string();
    match env.validate() {
        Err(EnvelopeValidationError::UnsafeEntityId { reason, .. }) => {
            assert!(reason.contains("control character"));
        }
        other => panic!("expected UnsafeEntityId, got {other:?}"),
    }
}

#[test]
fn validate_accepts_canonical_uuid_and_composite_edge_entity_id() {
    // Canonical shapes must still pass.
    let mut env = well_formed_envelope();
    env.entity_id = "01966a3f-7c8b-7d4e-8f3a-000000000001".to_string();
    env.validate().expect("UUID must pass");
    env.entity_type = EntityKind::TaskTag;
    env.entity_id =
        "01966a3f-7c8b-7d4e-8f3a-000000000001:01966a3f-7c8b-7d4e-8f3a-000000000002".to_string();
    env.validate().expect("composite edge id must pass");
}

#[test]
fn validate_rejects_non_canonical_uuid_for_uuid_backed_kind() {
    let mut env = well_formed_envelope();
    env.entity_id = "not-a-uuid".to_string();

    match env.validate() {
        Err(EnvelopeValidationError::UnsafeEntityId { reason, .. }) => {
            assert!(
                reason.contains("canonical hyphenated lowercase UUID"),
                "unexpected reason: {reason}",
            );
        }
        other => panic!("expected UnsafeEntityId, got {other:?}"),
    }
}

#[test]
fn validate_rejects_non_canonical_composite_edge_members() {
    let mut env = well_formed_envelope();
    env.entity_type = EntityKind::TaskTag;
    env.entity_id = "not-a-uuid:01966a3f-7c8b-7d4e-8f3a-000000000002".to_string();

    match env.validate() {
        Err(EnvelopeValidationError::UnsafeEntityId { reason, .. }) => {
            assert!(reason.contains("canonical"), "unexpected reason: {reason}");
        }
        other => panic!("expected UnsafeEntityId, got {other:?}"),
    }
}

#[test]
fn validate_rejects_payload_schema_version_too_far_ahead() {
    // a peer sending u32::MAX must be rejected at
    // the envelope boundary — otherwise the apply pipeline parks
    // the envelope in `sync_pending_inbox` where it churns retries
    // forever.
    let mut env = well_formed_envelope();
    env.payload_schema_version = u32::MAX;
    match env.validate() {
        Err(EnvelopeValidationError::PayloadSchemaVersionTooFarAhead { version, local_max }) => {
            assert_eq!(version, u32::MAX);
            assert_eq!(
                local_max,
                PAYLOAD_SCHEMA_VERSION.saturating_add(MAX_PAYLOAD_SCHEMA_VERSION_AHEAD)
            );
        }
        other => panic!("expected PayloadSchemaVersionTooFarAhead, got {other:?}"),
    }
}

#[test]
fn validate_accepts_payload_schema_version_within_headroom() {
    // The apply pipeline must still receive forward-compat envelopes
    // a few versions ahead so the pending-inbox replay path
    // (`apply/changelog.rs`) can rescue them after a build update.
    let mut env = well_formed_envelope();
    env.payload_schema_version = PAYLOAD_SCHEMA_VERSION + 1;
    env.validate().expect("schema +1 must validate");
    env.payload_schema_version =
        PAYLOAD_SCHEMA_VERSION.saturating_add(MAX_PAYLOAD_SCHEMA_VERSION_AHEAD);
    env.validate()
        .expect("schema at the cap must still validate (boundary is inclusive)");
}

#[test]
fn unknown_envelope_fields_are_silently_accepted() {
    // replaced #[serde(deny_unknown_fields)] — the old
    // test that asserted rejection was encoding the wrong invariant.
    // Forward-compat means a new peer can add an envelope-level
    // field ("signature", "compression", etc.) and older peers must
    // still parse + process the known fields, ignoring the rest.
    let json = r#"{
        "entity_type":"task",
        "entity_id":"01966a3f-7c8b-7d4e-8f3a-000000000001",
        "operation":"upsert",
        "version":"1711234567890_0000_a1b2c3d4a1b2c3d4",
        "payload_schema_version":1,
        "payload":"{}",
        "device_id":"device-001",
        "future_additive_field":"value-from-new-peer"
    }"#;
    let parsed: SyncEnvelope = serde_json::from_str(json)
        .expect("envelope must accept unknown top-level fields for forward compat");
    assert_eq!(parsed.entity_type, EntityKind::Task);
    assert_eq!(parsed.operation, SyncOperation::Upsert);
}
