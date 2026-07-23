use super::*;
use lorvex_store::test_support::fixtures::TaskBuilder;
use rusqlite::{params, Connection};

const UUID_A: &str = "01966a3f-7c8b-7d4e-8f3a-000000000201";
const UUID_B: &str = "01966a3f-7c8b-7d4e-8f3a-000000000202";

fn apply_invalid_id(entity_type: &str, entity_id: &str) -> Connection {
    let conn = test_db();
    let env = make_envelope(entity_type, entity_id, LWW_V_NEW);

    let result = apply_envelope(&conn, &env);

    let Err(ApplyError::InvalidPayload(message)) = result else {
        panic!("expected InvalidPayload, got {result:?}");
    };
    assert!(
        message.contains("canonical"),
        "unexpected message: {message}",
    );

    for (table, column) in [
        ("sync_tombstones", "entity_id"),
        ("sync_outbox", "entity_id"),
        ("sync_payload_shadow", "entity_id"),
    ] {
        assert_no_table_value(&conn, table, column, entity_id);
    }

    conn
}

fn assert_no_table_value(conn: &Connection, table: &str, column: &str, value: &str) {
    let count: i64 = conn
        .query_row(
            &format!("SELECT COUNT(*) FROM {table} WHERE {column} = ?1"),
            [value],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count, 0, "{table} must not receive the invalid id");
}

#[test]
fn apply_rejects_non_canonical_task_id_before_writing_any_sync_state() {
    let conn = apply_invalid_id(naming::ENTITY_TASK, "not-a-uuid");
    assert_no_table_value(&conn, "tasks", "id", "not-a-uuid");
}

#[test]
fn apply_rejects_non_canonical_root_child_and_edge_ids_before_writes() {
    let conn = apply_invalid_id(naming::ENTITY_LIST, "not-a-list");
    assert_no_table_value(&conn, "lists", "id", "not-a-list");

    let conn = apply_invalid_id(naming::ENTITY_HABIT, "not-a-habit");
    assert_no_table_value(&conn, "habits", "id", "not-a-habit");

    let conn = apply_invalid_id(naming::ENTITY_TASK_REMINDER, "reminder-1");
    assert_no_table_value(&conn, "task_reminders", "id", "reminder-1");

    let invalid_edge_id = format!("not-a-uuid:{UUID_B}");
    let conn = apply_invalid_id(naming::EDGE_TASK_TAG, &invalid_edge_id);
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_tags WHERE task_id = ?1 OR tag_id = ?2",
            params!["not-a-uuid", UUID_B],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count, 0, "task_tags must not receive the invalid edge id");
}

#[test]
fn apply_new_entity_succeeds() {
    let conn = test_db();
    let env = make_envelope(
        naming::ENTITY_TASK,
        UUID_A,
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);
}

#[test]
fn apply_new_list_succeeds() {
    let conn = test_db();
    let env = make_envelope(
        naming::ENTITY_LIST,
        UUID_B,
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);
}

#[test]
fn apply_all_known_entity_types() {
    let conn = test_db();
    // Pre-create dummy parent rows for FK-dependent entity types.
    TaskBuilder::new(DUMMY_UUID_A).title("Dummy").insert(&conn);
    conn.execute(
        "INSERT INTO habits (id, name, version, created_at, updated_at) VALUES (?1, 'Dummy', '0000000000000_0000_0000000000000000', '', '')",
        [DUMMY_UUID_A],
    ).unwrap();

    for entity_type in naming::ALL_ENTITY_TYPES {
        let payload = make_payload_for_entity_type(entity_type);
        let env = SyncEnvelope {
            entity_type: lorvex_domain::naming::EntityKind::parse(entity_type)
                .expect("ALL_ENTITY_TYPES must be parseable as EntityKind"),
            entity_id: suitable_entity_id(entity_type),
            operation: SyncOperation::Upsert,
            version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
                .expect("test fixture version must be a canonical HLC"),
            payload_schema_version: PAYLOAD_SCHEMA_VERSION,
            payload,
            device_id: "remote-device".to_string(),
        };
        let result = apply_envelope(&conn, &env).unwrap();
        assert_eq!(
            result,
            ApplyResult::Applied,
            "should apply for entity type {entity_type}"
        );
    }
}

#[test]
fn apply_unknown_entity_type_is_rejected_at_wire_boundary() {
    // forward-compat for unknown
    // `entity_type` values now lives at the wire-boundary parse seam.
    // The typed `SyncEnvelope.entity_type: EntityKind` field cannot
    // hold an unknown string, so an envelope with `"entity_type":
    // "future_unknown_kind"` fails to deserialize at the transport
    // layer. The apply pipeline downstream of that seam never sees
    // unknown kinds — replacing the previous "skip with reason" path,
    // which only ran after the runtime had already paid the cost of
    // routing the malformed envelope through dispatch.
    //
    // This test pins the wire-boundary contract instead of the
    // post-dispatch skip behavior. The apply-pipeline forward-compat
    // skip for unknown `payload_schema_version` still applies (see
    // `apply::changelog::apply_envelope_too_far_ahead_routes_to_pending_inbox`).
    let json = r#"{
        "entity_type": "future_unknown_kind",
        "entity_id": "01966a3f-7c8b-7d4e-8f3a-000000000001",
        "operation": "upsert",
        "version": "1711234567890_0000_a1b2c3d4a1b2c3d4",
        "payload_schema_version": 1,
        "payload": "{}",
        "device_id": "device-001"
    }"#;
    serde_json::from_str::<crate::envelope::SyncEnvelope>(json)
        .expect_err("unknown entity_type must fail to deserialize at the wire boundary");
}

#[test]
fn all_entity_types_are_syncable_kinds() {
    for t in naming::ALL_ENTITY_TYPES {
        let kind =
            naming::EntityKind::parse(t).expect("ALL_ENTITY_TYPES must be parseable EntityKind");
        assert!(kind.is_syncable_kind(), "{t} should be syncable");
    }
}

#[test]
fn all_edge_types_are_syncable_kinds() {
    for t in naming::ALL_EDGE_TYPES {
        let kind =
            naming::EntityKind::parse(t).expect("ALL_EDGE_TYPES must be parseable EntityKind");
        assert!(kind.is_syncable_kind(), "{t} should be syncable");
    }
}

#[test]
fn local_only_kinds_are_not_syncable() {
    // post #3004-H1 the wire boundary catches "unknown" strings via
    // `serde_json::from_str` failure. The apply-pipeline gate is now
    // purely about filtering local-only kinds, so this test pins the
    // remaining classification: `device_state`, `feedback`,
    // `task_provider_event_link`, `saved_query`, `import_session`
    // must all return false.
    for kind in [
        naming::EntityKind::TaskProviderEventLink,
        naming::EntityKind::DeviceState,
        naming::EntityKind::SavedQuery,
        naming::EntityKind::ImportSession,
    ] {
        assert!(
            !kind.is_syncable_kind(),
            "{kind:?} must not be marked syncable"
        );
    }
}
