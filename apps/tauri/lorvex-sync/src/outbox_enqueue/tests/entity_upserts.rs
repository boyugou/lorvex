use super::support::{
    canonicalize_json, enqueue_entity_upsert, entity_type_to_table, insert_calendar_event,
    insert_calendar_subscription, insert_list, insert_preference, insert_tag, insert_task, naming,
    outbox, parse_outbox_payload, setup_hlc, test_db, EnqueueError, SyncOperation, Value,
    PAYLOAD_SCHEMA_VERSION,
};

/// The snapshot enqueue path must NOT leak `priority_effective`, the
/// VIRTUAL generated column, into the re-emitted envelope —
/// `pragma_table_info` excludes VIRTUAL columns, so the snapshot reader
/// never sees it.
#[test]
fn enqueue_upsert_omits_virtual_priority_effective_column() {
    let conn = test_db();
    let mut hlc = setup_hlc();

    let task = "01966a3f-7c8b-7d4e-8f3a-0000000021a1";
    insert_task(&conn, task, "Task with priority");

    enqueue_entity_upsert(&conn, naming::ENTITY_TASK, task, &mut hlc, "dev-001").unwrap();

    let payload = parse_outbox_payload(&conn, naming::ENTITY_TASK, task);
    assert!(
        payload.get("priority_effective").is_none(),
        "virtual generated column priority_effective must never leak into the envelope"
    );
}

#[test]
fn enqueue_upsert_reads_snapshot_and_writes_to_outbox() {
    let conn = test_db();
    let mut hlc = setup_hlc();

    insert_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000002163", "Buy milk");

    enqueue_entity_upsert(
        &conn,
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        &mut hlc,
        "dev-001",
    )
    .unwrap();

    let pending = outbox::get_pending(&conn).unwrap();
    assert_eq!(pending.len(), 1);
    assert_eq!(
        pending[0].envelope.entity_type,
        lorvex_domain::naming::EntityKind::Task
    );
    assert_eq!(
        pending[0].envelope.entity_id,
        "01966a3f-7c8b-7d4e-8f3a-000000002163"
    );
    assert_eq!(pending[0].envelope.operation, SyncOperation::Upsert);
    assert_eq!(pending[0].envelope.device_id, "dev-001");
    assert_eq!(
        pending[0].envelope.payload_schema_version,
        PAYLOAD_SCHEMA_VERSION
    );

    // Payload should be valid canonical JSON containing the task title.
    let payload: Value = serde_json::from_str(&pending[0].envelope.payload).unwrap();
    assert_eq!(
        payload.get("title").and_then(|v| v.as_str()),
        Some("Buy milk")
    );
    assert_eq!(payload.get("status").and_then(|v| v.as_str()), Some("open"));
}

#[test]
fn enqueue_upsert_serializes_sqlite_bool_columns_as_json_bool() {
    let conn = test_db();
    let mut hlc = setup_hlc();

    insert_calendar_event(&conn, "01966a3f-7c8b-7d4e-8f3a-000000002114", 1);

    enqueue_entity_upsert(
        &conn,
        naming::ENTITY_CALENDAR_EVENT,
        "01966a3f-7c8b-7d4e-8f3a-000000002114",
        &mut hlc,
        "dev-001",
    )
    .unwrap();

    let pending = outbox::get_pending(&conn).unwrap();
    assert_eq!(pending.len(), 1);
    let payload: Value = serde_json::from_str(&pending[0].envelope.payload).unwrap();
    assert_eq!(payload.get("all_day"), Some(&Value::Bool(true)));
}

#[test]
fn enqueue_preference_upsert_uses_canonical_json_value_payload() {
    let conn = test_db();
    let mut hlc = setup_hlc();
    let cases = [
        (
            lorvex_domain::preference_keys::PREF_SETUP_COMPLETED,
            "true",
            serde_json::json!(true),
        ),
        (
            lorvex_domain::preference_keys::PREF_FONT_SCALE,
            "1.25",
            serde_json::json!(1.25),
        ),
        (
            lorvex_domain::preference_keys::PREF_THEME,
            r#""dark""#,
            serde_json::json!("dark"),
        ),
        (
            lorvex_domain::preference_keys::PREF_WORKING_HOURS,
            r#"{"start":"09:00","end":"17:00"}"#,
            serde_json::json!({"end": "17:00", "start": "09:00"}),
        ),
        (
            lorvex_domain::preference_keys::PREF_SIDEBAR_VISIBLE_MODULES,
            r#"["today","calendar"]"#,
            serde_json::json!(["today", "calendar"]),
        ),
        (
            lorvex_domain::preference_keys::PREF_SETUP_SUMMARY,
            "null",
            Value::Null,
        ),
    ];

    for (key, stored_json, expected_value) in cases {
        insert_preference(&conn, key, stored_json);
        enqueue_entity_upsert(&conn, naming::ENTITY_PREFERENCE, key, &mut hlc, "dev-001").unwrap();

        let payload = parse_outbox_payload(&conn, naming::ENTITY_PREFERENCE, key);
        assert_eq!(payload.get("key"), Some(&serde_json::json!(key)));
        assert_eq!(payload.get("value"), Some(&expected_value));
        assert_eq!(
            payload.get("updated_at"),
            Some(&serde_json::json!("2026-03-20T00:00:00.000Z"))
        );
    }
}

#[test]
fn enqueue_calendar_subscription_upsert_omits_device_local_retry_state() {
    let conn = test_db();
    let mut hlc = setup_hlc();
    let id = "01966a3f-7c8b-7d4e-8f3a-000000004320";
    insert_calendar_subscription(&conn, id);

    enqueue_entity_upsert(
        &conn,
        naming::ENTITY_CALENDAR_SUBSCRIPTION,
        id,
        &mut hlc,
        "dev-001",
    )
    .unwrap();

    let payload = parse_outbox_payload(&conn, naming::ENTITY_CALENDAR_SUBSCRIPTION, id);
    assert_eq!(payload["id"], id);
    assert_eq!(payload["name"], "Work ICS");
    assert_eq!(payload["url"], "https://example.com/work.ics");
    assert_eq!(payload["enabled"], true);
    assert!(payload.get("next_retry_at").is_none());
    assert!(payload.get("consecutive_failures").is_none());
    assert!(payload.get("last_retry_after_hint").is_none());
}

#[test]
fn enqueue_upsert_produces_canonical_json() {
    let conn = test_db();
    let mut hlc = setup_hlc();

    insert_list(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000212f", "Work");

    enqueue_entity_upsert(
        &conn,
        "list",
        "01966a3f-7c8b-7d4e-8f3a-00000000212f",
        &mut hlc,
        "dev-001",
    )
    .unwrap();

    let pending = outbox::get_pending(&conn).unwrap();
    let payload_str = &pending[0].envelope.payload;

    // Canonical JSON has sorted keys. Re-parse and re-canonicalize should
    // produce the same bytes (idempotent).
    let val: Value = serde_json::from_str(payload_str).unwrap();
    let re_canonicalized = canonicalize_json(&val).unwrap();
    assert_eq!(payload_str, &re_canonicalized);
}

#[test]
fn coalescing_replaces_first_upsert() {
    let conn = test_db();
    let mut hlc = setup_hlc();

    insert_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "Original title",
    );

    enqueue_entity_upsert(
        &conn,
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        &mut hlc,
        "dev-001",
    )
    .unwrap();

    // Update the task in-place.
    conn.execute(
        "UPDATE tasks SET title = 'Updated title', updated_at = '2026-03-21T00:00:00.000Z' WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000002163'",
        [],
    )
    .unwrap();

    // Enqueue again — should coalesce.
    enqueue_entity_upsert(
        &conn,
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        &mut hlc,
        "dev-001",
    )
    .unwrap();

    let pending = outbox::get_pending(&conn).unwrap();
    assert_eq!(pending.len(), 1, "second upsert should coalesce with first");

    let payload: Value = serde_json::from_str(&pending[0].envelope.payload).unwrap();
    assert_eq!(
        payload.get("title").and_then(|v| v.as_str()),
        Some("Updated title"),
        "coalesced entry should have the latest snapshot"
    );
}

#[test]
fn entity_not_found_returns_error() {
    let conn = test_db();
    let mut hlc = setup_hlc();

    let result = enqueue_entity_upsert(&conn, "task", "nonexistent", &mut hlc, "dev-001");
    assert!(result.is_err());
    match result.unwrap_err() {
        EnqueueError::EntityNotFound {
            entity_type,
            entity_id,
        } => {
            assert_eq!(entity_type, "task");
            assert_eq!(entity_id, "nonexistent");
        }
        other => panic!("expected EntityNotFound, got: {other}"),
    }
}

#[test]
fn unknown_entity_type_returns_error() {
    let conn = test_db();
    let mut hlc = setup_hlc();

    let result = enqueue_entity_upsert(&conn, "nonexistent_type", "id-1", &mut hlc, "dev-001");
    assert!(result.is_err());
    assert!(matches!(
        result.unwrap_err(),
        EnqueueError::UnknownEntityType(_)
    ));
}

#[test]
fn enqueue_upsert_for_list() {
    let conn = test_db();
    let mut hlc = setup_hlc();

    insert_list(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000212f", "Personal");

    enqueue_entity_upsert(
        &conn,
        "list",
        "01966a3f-7c8b-7d4e-8f3a-00000000212f",
        &mut hlc,
        "dev-001",
    )
    .unwrap();

    let pending = outbox::get_pending(&conn).unwrap();
    assert_eq!(pending.len(), 1);
    let payload: Value = serde_json::from_str(&pending[0].envelope.payload).unwrap();
    assert_eq!(
        payload.get("name").and_then(|v| v.as_str()),
        Some("Personal")
    );
}

#[test]
fn enqueue_upsert_for_tag() {
    let conn = test_db();
    let mut hlc = setup_hlc();

    insert_tag(&conn, "01966a3f-7c8b-7d4e-8f3a-000000002157", "urgent");

    enqueue_entity_upsert(
        &conn,
        "tag",
        "01966a3f-7c8b-7d4e-8f3a-000000002157",
        &mut hlc,
        "dev-001",
    )
    .unwrap();

    let pending = outbox::get_pending(&conn).unwrap();
    assert_eq!(pending.len(), 1);
    let payload: Value = serde_json::from_str(&pending[0].envelope.payload).unwrap();
    assert_eq!(
        payload.get("display_name").and_then(|v| v.as_str()),
        Some("urgent")
    );
}

#[test]
fn entity_type_to_table_covers_all_single_pk_syncable_types() {
    // Every non-composite (non-edge) entity in ALL_SYNCABLE_TYPES and
    // ai_changelog (which is append-only) should have a mapping.
    // Edges have composite PKs and are not handled by entity_type_to_table.
    let edges = [
        naming::EDGE_TASK_TAG,
        naming::EDGE_TASK_DEPENDENCY,
        naming::EDGE_TASK_CALENDAR_EVENT_LINK,
        naming::EDGE_HABIT_COMPLETION,
    ];
    let audit_only = [naming::ENTITY_AI_CHANGELOG];

    for et in naming::ALL_SYNCABLE_TYPES {
        if edges.contains(et) || audit_only.contains(et) {
            continue;
        }
        assert!(
            entity_type_to_table(et).is_ok(),
            "entity_type_to_table missing mapping for syncable type: {et}"
        );
    }
}

#[test]
fn hlc_versions_are_monotonically_increasing() {
    let conn = test_db();
    let mut hlc = setup_hlc();

    insert_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000002163", "First");
    insert_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000002164", "Second");

    enqueue_entity_upsert(
        &conn,
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        &mut hlc,
        "dev-001",
    )
    .unwrap();
    enqueue_entity_upsert(
        &conn,
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002164",
        &mut hlc,
        "dev-001",
    )
    .unwrap();

    let pending = outbox::get_pending(&conn).unwrap();
    assert_eq!(pending.len(), 2);
    assert!(
        pending[1].envelope.version > pending[0].envelope.version,
        "HLC versions should be monotonically increasing"
    );
}
