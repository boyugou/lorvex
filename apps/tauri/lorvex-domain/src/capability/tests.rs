use super::*;

// -----------------------------------------------------------------------
// Helper to build a SyncHandshake for tests
// -----------------------------------------------------------------------

fn base_handshake() -> SyncHandshake {
    SyncHandshake {
        sync_protocol_version: 1,
        payload_schema_version: 1,
        required_capabilities: BTreeSet::new(),
        optional_capabilities: BTreeSet::new(),
        app_version: "1.0.0".to_string(),
        device_id: "test-device".to_string(),
    }
}

fn handshake_with(
    sync_ver: u32,
    payload_ver: u32,
    required: &[&str],
    optional: &[&str],
) -> SyncHandshake {
    SyncHandshake {
        sync_protocol_version: sync_ver,
        payload_schema_version: payload_ver,
        required_capabilities: required
            .iter()
            .map(std::string::ToString::to_string)
            .collect(),
        optional_capabilities: optional
            .iter()
            .map(std::string::ToString::to_string)
            .collect(),
        app_version: "1.0.0".to_string(),
        device_id: "test-device".to_string(),
    }
}

// -----------------------------------------------------------------------
// check_handshake: Compatible
// -----------------------------------------------------------------------

#[test]
fn compatible_identical_handshakes() {
    let local = base_handshake();
    let remote = base_handshake();
    assert_eq!(
        check_handshake(&local, &remote),
        SyncCompatibility::Compatible
    );
}

#[test]
fn compatible_same_major_version_different_minor() {
    let local = handshake_with(1, 1, &[], &[]);
    let remote = handshake_with(999, 1, &[], &[]);
    // Both major_version = 0 (1/1000 == 0, 999/1000 == 0)
    assert_eq!(
        check_handshake(&local, &remote),
        SyncCompatibility::Compatible
    );
}

#[test]
fn compatible_remote_has_known_required_capabilities() {
    let local = base_handshake();
    let remote = handshake_with(1, 1, &["hlc_versioning", "tombstone_redirect"], &[]);
    assert_eq!(
        check_handshake(&local, &remote),
        SyncCompatibility::Compatible
    );
}

#[test]
fn compatible_remote_has_known_optional_capabilities() {
    let local = base_handshake();
    let remote = handshake_with(1, 1, &[], &["content_addressed_blobs", "tag_lookup_keys"]);
    assert_eq!(
        check_handshake(&local, &remote),
        SyncCompatibility::Compatible
    );
}

#[test]
fn compatible_remote_older_payload_version() {
    let local = handshake_with(1, 5, &[], &[]);
    let remote = handshake_with(1, 3, &[], &[]);
    assert_eq!(
        check_handshake(&local, &remote),
        SyncCompatibility::Compatible
    );
}

#[test]
fn compatible_same_payload_version() {
    let local = handshake_with(1, 3, &[], &[]);
    let remote = handshake_with(1, 3, &[], &[]);
    assert_eq!(
        check_handshake(&local, &remote),
        SyncCompatibility::Compatible
    );
}

// -----------------------------------------------------------------------
// check_handshake: Degraded
// -----------------------------------------------------------------------

#[test]
fn degraded_unknown_optional_capabilities() {
    let local = base_handshake();
    let remote = handshake_with(1, 1, &[], &["future_feature_xyz"]);
    match check_handshake(&local, &remote) {
        SyncCompatibility::Degraded(reasons) => {
            assert_eq!(reasons.len(), 1);
            match &reasons[0] {
                DegradedReason::UnknownOptionalCapabilities { capabilities } => {
                    assert_eq!(capabilities, &vec!["future_feature_xyz".to_string()]);
                }
                other => panic!("expected UnknownOptionalCapabilities, got {other:?}"),
            }
        }
        other => panic!("expected Degraded, got {other:?}"),
    }
}

#[test]
fn degraded_payload_schema_one_ahead() {
    let local = handshake_with(1, 1, &[], &[]);
    let remote = handshake_with(1, 2, &[], &[]);
    match check_handshake(&local, &remote) {
        SyncCompatibility::Degraded(reasons) => {
            assert_eq!(reasons.len(), 1);
            match &reasons[0] {
                DegradedReason::PayloadSchemaAhead {
                    local: l,
                    remote: r,
                } => {
                    assert_eq!(*l, 1);
                    assert_eq!(*r, 2);
                }
                other => panic!("expected PayloadSchemaAhead, got {other:?}"),
            }
        }
        other => panic!("expected Degraded, got {other:?}"),
    }
}

#[test]
fn degraded_both_payload_ahead_and_unknown_optional() {
    let local = handshake_with(1, 1, &[], &[]);
    let remote = handshake_with(1, 2, &[], &["exotic_feature"]);
    match check_handshake(&local, &remote) {
        SyncCompatibility::Degraded(reasons) => {
            assert_eq!(reasons.len(), 2);
            assert!(reasons
                .iter()
                .any(|r| matches!(r, DegradedReason::PayloadSchemaAhead { .. })));
            assert!(reasons
                .iter()
                .any(|r| matches!(r, DegradedReason::UnknownOptionalCapabilities { .. })));
        }
        other => panic!("expected Degraded with 2 reasons, got {other:?}"),
    }
}

// -----------------------------------------------------------------------
// check_handshake: Blocked
// -----------------------------------------------------------------------

#[test]
fn blocked_major_version_mismatch() {
    let local = handshake_with(1, 1, &[], &[]);
    let remote = handshake_with(1000, 1, &[], &[]);
    match check_handshake(&local, &remote) {
        SyncCompatibility::Blocked(BlockedReason::MajorVersionMismatch {
            local: l,
            remote: r,
        }) => {
            assert_eq!(l, 1);
            assert_eq!(r, 1000);
        }
        other => panic!("expected Blocked(MajorVersionMismatch), got {other:?}"),
    }
}

#[test]
fn blocked_unknown_required_capabilities() {
    let local = base_handshake();
    let remote = handshake_with(1, 1, &["quantum_sync"], &[]);
    match check_handshake(&local, &remote) {
        SyncCompatibility::Blocked(BlockedReason::UnknownRequiredCapabilities { capabilities }) => {
            assert_eq!(capabilities, vec!["quantum_sync".to_string()]);
        }
        other => panic!("expected Blocked(UnknownRequiredCapabilities), got {other:?}"),
    }
}

#[test]
fn blocked_multiple_unknown_required_capabilities() {
    let local = base_handshake();
    let remote = handshake_with(1, 1, &["future_a", "future_b", "hlc_versioning"], &[]);
    match check_handshake(&local, &remote) {
        SyncCompatibility::Blocked(BlockedReason::UnknownRequiredCapabilities { capabilities }) => {
            // Only the unknown ones should be listed.
            assert!(capabilities.contains(&"future_a".to_string()));
            assert!(capabilities.contains(&"future_b".to_string()));
            assert!(!capabilities.contains(&"hlc_versioning".to_string()));
        }
        other => panic!("expected Blocked(UnknownRequiredCapabilities), got {other:?}"),
    }
}

#[test]
fn blocked_payload_schema_too_far_ahead() {
    let local = handshake_with(1, 1, &[], &[]);
    let remote = handshake_with(1, 3, &[], &[]);
    match check_handshake(&local, &remote) {
        SyncCompatibility::Blocked(BlockedReason::PayloadSchemaTooFarAhead {
            local: l,
            remote: r,
        }) => {
            assert_eq!(l, 1);
            assert_eq!(r, 3);
        }
        other => panic!("expected Blocked(PayloadSchemaTooFarAhead), got {other:?}"),
    }
}

#[test]
fn blocked_payload_schema_way_ahead() {
    let local = handshake_with(1, 2, &[], &[]);
    let remote = handshake_with(1, 10, &[], &[]);
    match check_handshake(&local, &remote) {
        SyncCompatibility::Blocked(BlockedReason::PayloadSchemaTooFarAhead { .. }) => {}
        other => panic!("expected Blocked(PayloadSchemaTooFarAhead), got {other:?}"),
    }
}

// -----------------------------------------------------------------------
// check_handshake: priority ordering
// -----------------------------------------------------------------------

#[test]
fn major_version_mismatch_takes_priority_over_unknown_capabilities() {
    let local = handshake_with(1, 1, &[], &[]);
    let remote = handshake_with(1000, 1, &["future_required"], &["future_optional"]);
    // Major version check happens first.
    match check_handshake(&local, &remote) {
        SyncCompatibility::Blocked(BlockedReason::MajorVersionMismatch { .. }) => {}
        other => panic!("expected MajorVersionMismatch to take priority, got {other:?}"),
    }
}

#[test]
fn unknown_required_takes_priority_over_payload_too_far_ahead() {
    let local = handshake_with(1, 1, &[], &[]);
    let remote = handshake_with(1, 5, &["unknown_req"], &[]);
    // Required capability check happens before payload schema check.
    match check_handshake(&local, &remote) {
        SyncCompatibility::Blocked(BlockedReason::UnknownRequiredCapabilities { .. }) => {}
        other => panic!("expected UnknownRequiredCapabilities to take priority, got {other:?}"),
    }
}

// -----------------------------------------------------------------------
// check_envelope_version
// -----------------------------------------------------------------------

#[test]
fn envelope_known_version_parse_fully() {
    assert_eq!(check_envelope_version(1, 1), EnvelopeAcceptance::ParseFully,);
}

#[test]
fn envelope_older_version_parse_fully() {
    assert_eq!(check_envelope_version(1, 3), EnvelopeAcceptance::ParseFully,);
}

#[test]
fn envelope_one_ahead_parse_forward_compat() {
    assert_eq!(
        check_envelope_version(2, 1),
        EnvelopeAcceptance::ParseForwardCompat,
    );
}

#[test]
fn envelope_two_ahead_defer() {
    assert_eq!(
        check_envelope_version(3, 1),
        EnvelopeAcceptance::DeferToPendingInbox,
    );
}

#[test]
fn envelope_way_ahead_defer() {
    assert_eq!(
        check_envelope_version(100, 5),
        EnvelopeAcceptance::DeferToPendingInbox,
    );
}

#[test]
fn envelope_same_version_parse_fully() {
    assert_eq!(check_envelope_version(5, 5), EnvelopeAcceptance::ParseFully,);
}

#[test]
fn envelope_version_check_saturates_at_u32_max() {
    assert_eq!(
        check_envelope_version(u32::MAX, u32::MAX),
        EnvelopeAcceptance::ParseFully,
    );
}

// -----------------------------------------------------------------------
// known_capabilities
// -----------------------------------------------------------------------

#[test]
fn known_capabilities_contains_v1_set() {
    let caps = known_capabilities();
    assert!(caps.contains("hlc_versioning"));
    assert!(caps.contains("tombstone_redirect"));
    assert!(caps.contains("tag_lookup_keys"));
    assert!(caps.contains("content_addressed_blobs"));
    assert!(caps.contains("recurrence_instance_key"));
    assert!(caps.contains("capability_negotiation"));
    assert_eq!(caps.len(), 6);
}

#[test]
fn known_capabilities_does_not_contain_unknown() {
    let caps = known_capabilities();
    assert!(!caps.contains("nonexistent_capability"));
}

// -----------------------------------------------------------------------
// major_version helpers
// -----------------------------------------------------------------------

#[test]
fn major_version_extraction() {
    assert_eq!(major_version(0), 0);
    assert_eq!(major_version(1), 0);
    assert_eq!(major_version(999), 0);
    assert_eq!(major_version(1000), 1);
    assert_eq!(major_version(1001), 1);
    assert_eq!(major_version(1999), 1);
    assert_eq!(major_version(2000), 2);
}

#[test]
fn major_version_differs_same() {
    assert!(!major_version_differs(1, 999));
    assert!(!major_version_differs(1000, 1999));
}

#[test]
fn major_version_differs_different() {
    assert!(major_version_differs(1, 1000));
    assert!(major_version_differs(999, 1000));
    assert!(major_version_differs(1999, 2000));
}
