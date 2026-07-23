use super::support::*;

// ===========================================================================
// 16. ai_changelog dedup: same entry twice -> only one row
// ===========================================================================

#[test]
fn ai_changelog_dedup_same_entry_twice() {
    let conn = test_db();

    let payload = r#"{
        "timestamp": "2026-03-24T10:00:00.000Z",
        "operation": "create",
        "entity_type": "task",
        "entity_id": "01966a3f-7c8b-7d4e-8f3a-00000000312c",
        "summary": "Created task: Buy groceries",
        "initiated_by": "ai",
        "mcp_tool": "create_task",
        "source_device_id": "device-001",
        "undo_token": null,
        "is_preview": false
    }"#;
    let env = upsert_envelope(
        naming::ENTITY_AI_CHANGELOG,
        "01966a3f-7c8b-7d4e-8f3a-000000003101",
        V2,
        payload,
    );

    // Apply once.
    let r1 = apply_envelope(&conn, &env).unwrap();
    assert_eq!(r1, ApplyResult::Applied);

    // Apply again.
    let r2 = apply_envelope(&conn, &env).unwrap();
    assert_eq!(r2, ApplyResult::Applied); // changelog bypasses LWW

    // Should be exactly one row.
    assert_eq!(
        count_rows(
            &conn,
            "ai_changelog",
            "id = '01966a3f-7c8b-7d4e-8f3a-000000003101'"
        ),
        1
    );
}

// ===========================================================================
// 17. ai_changelog: same ID from different source_device_id
// ===========================================================================

#[test]
fn ai_changelog_same_id_different_device_only_first_wins() {
    let conn = test_db();

    // The ai_changelog PK is just `id`. If two devices generate the same id,
    // the first INSERT wins (INSERT OR IGNORE). The dedup logic checks id first.
    let payload_device1 = r#"{
        "timestamp": "2026-03-24T10:00:00.000Z",
        "operation": "create",
        "entity_type": "task",
        "entity_id": "01966a3f-7c8b-7d4e-8f3a-00000000312d",
        "summary": "Created from device 1",
        "initiated_by": "ai",
        "source_device_id": "device-001",
        "undo_token": null,
        "is_preview": false
    }"#;
    let env1 = upsert_envelope(
        naming::ENTITY_AI_CHANGELOG,
        "01966a3f-7c8b-7d4e-8f3a-000000003102",
        V2,
        payload_device1,
    );

    let payload_device2 = r#"{
        "timestamp": "2026-03-24T10:00:00.000Z",
        "operation": "create",
        "entity_type": "task",
        "entity_id": "01966a3f-7c8b-7d4e-8f3a-00000000312d",
        "summary": "Created from device 2",
        "initiated_by": "ai",
        "source_device_id": "device-002",
        "undo_token": null,
        "is_preview": false
    }"#;
    let env2 = upsert_envelope(
        naming::ENTITY_AI_CHANGELOG,
        "01966a3f-7c8b-7d4e-8f3a-000000003102",
        V2,
        payload_device2,
    );

    // Apply from device-001.
    let r1 = apply_envelope(&conn, &env1).unwrap();
    assert_eq!(r1, ApplyResult::Applied);

    // Apply from device-002 with same changelog id.
    let r2 = apply_envelope(&conn, &env2).unwrap();
    assert_eq!(r2, ApplyResult::Applied); // changelog bypasses LWW

    // The id is PK, so the second insert is deduped. Only one row exists.
    assert_eq!(
        count_rows(
            &conn,
            "ai_changelog",
            "id = '01966a3f-7c8b-7d4e-8f3a-000000003102'"
        ),
        1
    );

    // The row should contain device-001's data (first writer wins).
    let summary: String = conn
        .query_row(
            "SELECT summary FROM ai_changelog WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000003102'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(summary, "Created from device 1");
}

#[test]
fn ai_changelog_rejects_non_string_source_device_id() {
    let conn = test_db();

    let payload = r#"{
        "timestamp": "2026-03-24T10:00:00.000Z",
        "operation": "create",
        "entity_type": "task",
        "entity_id": "01966a3f-7c8b-7d4e-8f3a-00000000312e",
        "summary": "Created task: bad source device type",
        "initiated_by": "ai",
        "source_device_id": 7,
        "undo_token": null,
        "is_preview": false
    }"#;
    let env = upsert_envelope(
        naming::ENTITY_AI_CHANGELOG,
        "01966a3f-7c8b-7d4e-8f3a-000000003103",
        V2,
        payload,
    );

    let error = apply_envelope(&conn, &env).expect_err("non-string source_device_id should fail");
    assert!(
        error.to_string().contains("source_device_id"),
        "unexpected error: {error}"
    );
    assert_eq!(
        count_rows(
            &conn,
            "ai_changelog",
            "id = '01966a3f-7c8b-7d4e-8f3a-000000003103'"
        ),
        0
    );
}

#[test]
fn ai_changelog_rejects_non_string_entity_id() {
    let conn = test_db();

    let payload = r#"{
        "timestamp": "2026-03-24T10:00:00.000Z",
        "operation": "create",
        "entity_type": "task",
        "entity_id": 7,
        "summary": "Created task: bad entity_id type",
        "initiated_by": "ai",
        "source_device_id": "device-001",
        "undo_token": null,
        "is_preview": false
    }"#;
    let env = upsert_envelope(
        naming::ENTITY_AI_CHANGELOG,
        "01966a3f-7c8b-7d4e-8f3a-000000003104",
        V2,
        payload,
    );

    let error = apply_envelope(&conn, &env).expect_err("non-string entity_id should fail");
    assert!(
        error.to_string().contains("entity_id"),
        "unexpected error: {error}"
    );
    assert_eq!(
        count_rows(
            &conn,
            "ai_changelog",
            "id = '01966a3f-7c8b-7d4e-8f3a-000000003104'"
        ),
        0
    );
}
