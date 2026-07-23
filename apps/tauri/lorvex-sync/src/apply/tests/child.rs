use super::*;
use lorvex_store::test_support::fixtures::TaskBuilder;

#[test]
fn habit_reminder_policy_upsert_accepts_json_bool_enabled_from_tauri_writer() {
    let conn = test_db();
    // Insert a habit so the FK constraint is satisfied.
    conn.execute(
        "INSERT INTO habits (id, name, frequency_type, target_count, archived, version, created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000002122', 'Test habit', 'daily', 1, 0, '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
        [],
    )
    .expect("insert habit fixture");

    // Enabled as JSON `true` — the exact shape Tauri emits.
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::HabitReminderPolicy,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002143".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{
            "habit_id": "01966a3f-7c8b-7d4e-8f3a-000000002122",
            "reminder_time": "09:00",
            "enabled": true,
            "created_at": "2026-04-11T00:00:00.000Z",
            "updated_at": "2026-04-11T00:00:00.000Z"
        }"#
        .to_string(),
        device_id: "remote-device".to_string(),
    };
    apply_envelope(&conn, &env).expect("bool true enabled must apply successfully");
    let stored: i64 = conn
        .query_row(
            "SELECT enabled FROM habit_reminder_policies WHERE id = ?1",
            ["01966a3f-7c8b-7d4e-8f3a-000000002143"],
            |row| row.get(0),
        )
        .expect("row must exist");
    assert_eq!(stored, 1);

    // Enabled as JSON `false`. Different reminder_time to avoid
    // the UNIQUE(habit_id, reminder_time) constraint.
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::HabitReminderPolicy,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002142".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567891_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{
            "habit_id": "01966a3f-7c8b-7d4e-8f3a-000000002122",
            "reminder_time": "10:00",
            "enabled": false,
            "created_at": "2026-04-11T00:00:00.000Z",
            "updated_at": "2026-04-11T00:00:00.000Z"
        }"#
        .to_string(),
        device_id: "remote-device".to_string(),
    };
    apply_envelope(&conn, &env).expect("bool false enabled must apply successfully");
    let stored: i64 = conn
        .query_row(
            "SELECT enabled FROM habit_reminder_policies WHERE id = ?1",
            ["01966a3f-7c8b-7d4e-8f3a-000000002142"],
            |row| row.get(0),
        )
        .expect("row must exist");
    assert_eq!(stored, 0);

    // Integers are no longer accepted on the sync wire. Use a third
    // distinct reminder_time to clear the unique constraint.
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::HabitReminderPolicy,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002144".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567892_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{
            "habit_id": "01966a3f-7c8b-7d4e-8f3a-000000002122",
            "reminder_time": "11:00",
            "enabled": 1,
            "created_at": "2026-04-11T00:00:00.000Z",
            "updated_at": "2026-04-11T00:00:00.000Z"
        }"#
        .to_string(),
        device_id: "remote-device".to_string(),
    };
    assert!(matches!(
        apply_envelope(&conn, &env),
        Err(ApplyError::InvalidPayload(_))
    ));
}

#[test]
fn memory_revision_upsert_rejects_non_string_source_revision_id_when_present() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::MemoryRevision,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-00000000213f".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{
            "memory_key":"memory-001",
            "content":"hello",
            "operation":"update",
            "source_revision_id":7,
            "actor":"ai",
            "version":"1711234567890_0000_a1b2c3d4a1b2c3d4",
            "created_at":""
        }"#
        .to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(matches!(result, Err(ApplyError::InvalidPayload(_))));
}

#[test]
fn habit_completion_upsert_rejects_non_integer_value() {
    let conn = test_db();
    conn.execute(
        "INSERT INTO habits (id, name, version, created_at, updated_at) VALUES ('01966a3f-7c8b-7d4e-8f3a-000000002120', 'H', '0000000000000_0000_0000000000000000', '', '')",
        [],
    ).unwrap();

    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::HabitCompletion,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002120:2026-03-29".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{"value":"one","created_at":"","updated_at":""}"#.to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(matches!(result, Err(ApplyError::InvalidPayload(_))));
}

#[test]
fn habit_completion_upsert_rejects_non_string_note_when_present() {
    let conn = test_db();
    conn.execute(
        "INSERT INTO habits (id, name, version, created_at, updated_at) VALUES ('01966a3f-7c8b-7d4e-8f3a-000000002121', 'H', '0000000000000_0000_0000000000000000', '', '')",
        [],
    )
    .unwrap();

    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::HabitCompletion,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002121:2026-03-30".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{"value":1,"note":7,"created_at":"","updated_at":""}"#.to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(matches!(result, Err(ApplyError::InvalidPayload(_))));
}

#[test]
fn task_reminder_upsert_rejects_missing_task_id() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::TaskReminder,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-00000000214a".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{"reminder_at":"2026-01-01T09:00:00Z","created_at":""}"#.to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(matches!(result, Err(ApplyError::InvalidPayload(_))));
}

#[test]
fn task_reminder_upsert_rejects_non_string_dismissed_at_when_present() {
    let conn = test_db();
    TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-000000002163")
        .title("T")
        .insert(&conn);
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::TaskReminder,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-00000000214b".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{
            "task_id":"01966a3f-7c8b-7d4e-8f3a-000000002163",
            "reminder_at":"2026-01-01T09:00:00Z",
            "dismissed_at":123,
            "created_at":""
        }"#
        .to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(matches!(result, Err(ApplyError::InvalidPayload(_))));
}
