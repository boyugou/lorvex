use super::*;

#[test]
fn apply_envelope_rejects_autocommit_connection() {
    let conn = lorvex_store::test_support::test_conn();
    assert!(
        conn.is_autocommit(),
        "test fixture should model an unwrapped production caller"
    );
    let env = make_envelope(
        naming::ENTITY_PREFERENCE,
        "autocommit-apply-guard",
        LWW_V_NEW,
    );

    let err = apply_envelope(&conn, &env)
        .expect_err("apply_envelope should reject callers outside a transaction");
    assert!(
        err.to_string()
            .contains("apply_envelope must run inside an outer transaction"),
        "unexpected error: {err}"
    );
}

#[test]
fn changelog_dedup_by_id() {
    let conn = test_db();
    let payload = r#"{
        "timestamp": "2026-03-23T12:00:00.000Z",
        "operation": "create",
        "entity_type": "task",
        "entity_id": "01966a3f-7c8b-7d4e-8f3a-000000002155",
        "summary": "Created task",
        "initiated_by": "ai",
        "source_device_id": "dev-A",
        "undo_token": null,
        "is_preview": false
    }"#;
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::AiChangelog,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-00000000210f".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: payload.to_string(),
        device_id: "remote-device".to_string(),
    };

    apply_envelope(&conn, &env).unwrap();
    apply_envelope(&conn, &env).unwrap(); // duplicate

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE id = ?1",
            ["01966a3f-7c8b-7d4e-8f3a-00000000210f"],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(count, 1);
}

#[test]
fn changelog_upsert_rejects_missing_summary() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::AiChangelog,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002111".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{
            "timestamp": "2026-03-23T12:00:00.000Z",
            "operation": "create",
            "entity_type": "task",
            "initiated_by": "ai"
        }"#
        .to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(matches!(result, Err(ApplyError::InvalidPayload(_))));
}

/// `ai_changelog` is append-only at the apply layer.
/// A peer authoring a Delete envelope against an existing changelog
/// row must be refused with `ApplyError::InvalidOperation`, not
/// silently honored — the table has no `version` column so the
/// upstream LWW gate never fires for it, leaving deletes otherwise
/// unguarded.
#[test]
fn changelog_delete_envelope_is_rejected() {
    let conn = test_db();
    // Seed an existing changelog row so we can prove the delete
    // attempt does not erase it.
    let upsert_payload = r#"{
        "timestamp": "2026-03-23T12:00:00.000Z",
        "operation": "create",
        "entity_type": "task",
        "entity_id": "01966a3f-7c8b-7d4e-8f3a-000000002155",
        "summary": "Created task",
        "initiated_by": "ai",
        "undo_token": null,
        "is_preview": false
    }"#;
    let upsert = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::AiChangelog,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002110".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: upsert_payload.to_string(),
        device_id: "remote-device".to_string(),
    };
    apply_envelope(&conn, &upsert).unwrap();

    let delete = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::AiChangelog,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002110".to_string(),
        operation: SyncOperation::Delete,
        version: lorvex_domain::hlc::Hlc::parse("1711234567891_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: "{}".to_string(),
        device_id: "remote-device".to_string(),
    };
    let result = apply_envelope(&conn, &delete);
    assert!(
        matches!(
            result,
            Err(ApplyError::InvalidOperation { ref entity_type, ref operation })
                if entity_type == naming::ENTITY_AI_CHANGELOG && operation == "delete"
        ),
        "expected InvalidOperation for ai_changelog delete, got {result:?}"
    );

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE id = ?1",
            ["01966a3f-7c8b-7d4e-8f3a-000000002110"],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(count, 1, "delete attempt must not erase the existing row");
}

#[test]
fn changelog_reset_delete_envelope_purges_row_and_tombstones_it() {
    let conn = test_db();
    let upsert_payload = r#"{
        "timestamp": "2026-03-23T12:00:00.000Z",
        "operation": "create",
        "entity_type": "task",
        "entity_id": "01966a3f-7c8b-7d4e-8f3a-000000002155",
        "summary": "Created task",
        "initiated_by": "ai",
        "undo_token": null,
        "is_preview": false
    }"#;
    let entity_id = "01966a3f-7c8b-7d4e-8f3a-000000002112";
    let upsert = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::AiChangelog,
        entity_id: entity_id.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: upsert_payload.to_string(),
        device_id: "remote-device".to_string(),
    };
    apply_envelope(&conn, &upsert).unwrap();

    let delete = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::AiChangelog,
        entity_id: entity_id.to_string(),
        operation: SyncOperation::Delete,
        version: lorvex_domain::hlc::Hlc::parse("1711234567891_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: format!(r#"{{"id":"{entity_id}","reset_all_data":true}}"#),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &delete).unwrap();
    assert!(matches!(result, ApplyResult::Applied));

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE id = ?1",
            [entity_id],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(count, 0, "reset delete must remove the audit row");

    assert!(
        crate::tombstone::is_tombstoned(&conn, naming::ENTITY_AI_CHANGELOG, entity_id).unwrap(),
        "reset delete must leave a tombstone so older audit upserts cannot resurrect"
    );
}
