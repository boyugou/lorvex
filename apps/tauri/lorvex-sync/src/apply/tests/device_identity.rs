use super::*;

/// Each test holds [`collision_test_mutex`] for its entire reset →
/// seed → invoke → observe window so parallel tests sharing the
/// process-global `DEVICE_IDENTITY_COLLISION_LOGGED` cannot
/// interleave each other's resets. See M2.
#[test]
fn device_identity_collision_emits_error_log_once() {
    let _guard = collision_test_mutex()
        .lock()
        .expect("collision test mutex poisoned");
    reset_device_identity_collision_guard_for_testing();
    let conn = test_db();
    let local_device_id = "01966a3f-7c8b-7d4e-8f3a-000000000001";
    conn.execute(
        &format!(
            "INSERT INTO sync_checkpoints (key, value) VALUES ('device_id', '{local_device_id}')"
        ),
        [],
    )
    .unwrap();
    // compute the App-surface suffix from the hash
    // so the test tracks the real derivation, not a stale literal.
    let local_suffix = device_id_to_hlc_suffix(local_device_id, HlcSurface::App);

    // Envelope from a "cloned" peer: same App suffix, different device_id.
    let envelope = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Task,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002174".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse(&format!("1711234567890_0000_{local_suffix}"))
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{"id":"01966a3f-7c8b-7d4e-8f3a-000000002174","title":"from clone"}"#
            .to_string(),
        device_id: "01966a3f-7c8b-7d4e-8f3a-000000000002".to_string(),
    };
    check_device_identity_collision(&conn, &envelope);

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.apply.device_collision'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count, 1, "one error_logs row expected on first collision");

    // Second envelope with same collision pattern should NOT
    // produce a duplicate — the static guard suppresses repeats.
    let envelope2 = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Task,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002175".to_string(),
        ..envelope
    };
    check_device_identity_collision(&conn, &envelope2);

    let count_after: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.apply.device_collision'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count_after, 1, "guard must suppress duplicate collisions");
}

#[test]
fn no_collision_log_when_suffix_differs() {
    let _guard = collision_test_mutex()
        .lock()
        .expect("collision test mutex poisoned");
    reset_device_identity_collision_guard_for_testing();
    let conn = test_db();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES ('device_id', \
         '01966a3f-7c8b-7d4e-8f3a-000000000001')",
        [],
    )
    .unwrap();
    let envelope = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Task,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002196".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_deadbeefdeadbeef")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{"id":"01966a3f-7c8b-7d4e-8f3a-000000002196","title":"from remote"}"#
            .to_string(),
        device_id: "01966a3f-7c8b-7d4e-8f3a-deadbeefdead".to_string(),
    };
    check_device_identity_collision(&conn, &envelope);

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.apply.device_collision'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count, 0, "no log when suffixes differ");
}

#[test]
fn no_collision_log_when_device_id_matches_self() {
    let _guard = collision_test_mutex()
        .lock()
        .expect("collision test mutex poisoned");
    reset_device_identity_collision_guard_for_testing();
    let conn = test_db();
    let local_device_id = "01966a3f-7c8b-7d4e-8f3a-000000000001";
    conn.execute(
        &format!(
            "INSERT INTO sync_checkpoints (key, value) VALUES ('device_id', '{local_device_id}')"
        ),
        [],
    )
    .unwrap();
    let self_suffix = device_id_to_hlc_suffix(local_device_id, HlcSurface::App);
    let envelope = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Task,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002199".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse(&format!("1711234567890_0000_{self_suffix}"))
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{"id":"01966a3f-7c8b-7d4e-8f3a-000000002199","title":"from self"}"#.to_string(),
        device_id: local_device_id.to_string(),
    };
    check_device_identity_collision(&conn, &envelope);

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.apply.device_collision'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count, 0, "self-envelopes must not trigger collision log");
}

/// the collision diagnostic
/// must use the softened "identify which install is the clone" wording
/// rather than the dangerously prescriptive "Fix: reset
/// sync_checkpoints.device_id on the cloned install" copy. The latter
/// would discard whichever device the user actually wanted to keep
/// (the original install is unknown to the apply pipeline). Pin the
/// substring contract so a regression can't silently re-introduce
/// the destructive phrasing.
#[test]
fn collision_diagnostic_carries_softened_advisory_wording() {
    let _guard = collision_test_mutex()
        .lock()
        .expect("collision test mutex poisoned");
    reset_device_identity_collision_guard_for_testing();
    let conn = test_db();
    let local_device_id = "01966a3f-7c8b-7d4e-8f3a-000000000003";
    conn.execute(
        &format!(
            "INSERT INTO sync_checkpoints (key, value) VALUES ('device_id', '{local_device_id}')"
        ),
        [],
    )
    .unwrap();
    let local_suffix = device_id_to_hlc_suffix(local_device_id, HlcSurface::App);
    let envelope = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Task,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-00000000219e".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse(&format!("1711234567890_0000_{local_suffix}"))
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{"id":"01966a3f-7c8b-7d4e-8f3a-00000000219e","title":"clone-write"}"#
            .to_string(),
        device_id: "01966a3f-7c8b-7d4e-8f3a-000000000004".to_string(),
    };
    check_device_identity_collision(&conn, &envelope);

    let details: String = conn
        .query_row(
            "SELECT details FROM error_logs WHERE source = 'sync.apply.device_collision'",
            [],
            |row| row.get(0),
        )
        .unwrap();

    assert!(
        details.contains("identify which install is the clone"),
        "softened advisory wording missing: {details}"
    );
    assert!(
        details.contains("Resetting the wrong side discards its writes"),
        "destructive-action warning missing: {details}"
    );
    assert!(
        details.contains("regenerate `sync_checkpoints.device_id`"),
        "remediation pointer missing: {details}"
    );
    // Negative assertion: the prescriptive pre-fix copy must never
    // re-appear (would silently nuke the wrong device's history).
    assert!(
        !details.contains("Fix: reset sync_checkpoints.device_id on the cloned install"),
        "destructive pre-fix copy resurfaced: {details}"
    );
}
