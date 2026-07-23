use super::*;
use lorvex_store::test_support::fixtures::TaskBuilder;

#[test]
fn task_upsert_writes_real_data() {
    let conn = test_db();
    let payload = r#"{
        "title": "Buy groceries",
        "status": "open",
        "defer_count": 0,
        "priority": 2,
        "due_date": "2026-04-01",
        "estimated_minutes": 30,
        "created_at": "2026-03-23T12:00:00.000Z",
        "updated_at": "2026-03-23T12:00:00.000Z"
    }"#;
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Task,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002166".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: payload.to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);

    // Verify the row was written.
    let title: String = conn
        .query_row(
            "SELECT title FROM tasks WHERE id = ?1",
            ["01966a3f-7c8b-7d4e-8f3a-000000002166"],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(title, "Buy groceries");

    let priority: i64 = conn
        .query_row(
            "SELECT priority FROM tasks WHERE id = ?1",
            ["01966a3f-7c8b-7d4e-8f3a-000000002166"],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(priority, 2);

    let version: String = conn
        .query_row(
            "SELECT version FROM tasks WHERE id = ?1",
            ["01966a3f-7c8b-7d4e-8f3a-000000002166"],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(version, "1711234567890_0000_a1b2c3d4a1b2c3d4");
}

#[test]
fn task_delete_removes_row() {
    let conn = test_db();

    // Insert a task first.
    TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-000000002167")
        .title("To delete")
        .insert(&conn);

    let env = make_delete_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002167",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = ?1",
            ["01966a3f-7c8b-7d4e-8f3a-000000002167"],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(count, 0);
}

#[test]
fn preference_upsert_writes_real_data() {
    let conn = test_db();
    let payload = r#"{"value": "dark", "updated_at": "2026-03-23T12:00:00.000Z"}"#;
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Preference,
        entity_id: "theme".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: payload.to_string(),
        device_id: "remote-device".to_string(),
    };

    apply_envelope(&conn, &env).unwrap();

    let value: String = conn
        .query_row(
            "SELECT value FROM preferences WHERE key = ?1",
            ["theme"],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(value, "\"dark\"");
}

#[test]
fn preference_upsert_writes_non_string_json_value() {
    let conn = test_db();
    let payload =
        r#"{"value": {"start":"09:00","end":"17:00"}, "updated_at": "2026-03-23T12:00:00.000Z"}"#;
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Preference,
        entity_id: "working_hours".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: payload.to_string(),
        device_id: "remote-device".to_string(),
    };

    apply_envelope(&conn, &env).unwrap();

    let value: String = conn
        .query_row(
            "SELECT value FROM preferences WHERE key = ?1",
            ["working_hours"],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(value, "{\"end\":\"17:00\",\"start\":\"09:00\"}");
}
