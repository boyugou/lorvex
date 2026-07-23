use super::support::{
    apply_envelope, enqueue_entity_upsert, enqueue_payload_delete, enqueue_payload_upsert,
    insert_tag, insert_task, insert_task_tag, naming, outbox, params, setup_hlc, test_db,
    EnqueueError, OutboxWriteContext, SyncEnvelope, SyncOperation, Value, PAYLOAD_SCHEMA_VERSION,
};

#[test]
fn enqueue_payload_upsert_stamps_version() {
    let conn = test_db();
    insert_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "Stamped task",
    );

    let version = "1743280000000_0001_deadbeefdeadbeef";
    enqueue_payload_upsert(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        &serde_json::json!({
            "id": "01966a3f-7c8b-7d4e-8f3a-000000002163",
            "title": "Stamped task",
            "status": "open",
        }),
        OutboxWriteContext {
            version,
            device_id: "dev-001",
        },
    )
    .unwrap();

    // The stamp lands on both the entity row and the outbox envelope,
    // and the canonicalized payload carries the same version.
    let stamped_version: String = conn
        .query_row(
            "SELECT version FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000002163'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(stamped_version, version);

    let (outbox_version, payload): (String, String) = conn
        .query_row(
            "SELECT version, payload FROM sync_outbox
             WHERE entity_type = 'task' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000002163'",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    assert_eq!(outbox_version, version);

    let payload: Value = serde_json::from_str(&payload).unwrap();
    assert_eq!(payload["version"], version);
}

#[test]
fn enqueue_payload_delete_preserves_pre_delete_payload_version() {
    let conn = test_db();

    let delete_version = "1743280000000_0001_deadbeefdeadbeef";
    let row_version = "1743279999999_0000_feedfacefeedface";
    enqueue_payload_delete(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        &serde_json::json!({
            "id": "01966a3f-7c8b-7d4e-8f3a-000000002163",
            "title": "Deleted task",
            "version": row_version,
        }),
        OutboxWriteContext {
            version: delete_version,
            device_id: "dev-001",
        },
    )
    .unwrap();

    let (outbox_version, payload): (String, String) = conn
        .query_row(
            "SELECT version, payload FROM sync_outbox
             WHERE entity_type = 'task' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000002163'",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    assert_eq!(outbox_version, delete_version);

    let payload: Value = serde_json::from_str(&payload).unwrap();
    assert_eq!(payload["version"], row_version);
}

#[test]
fn enqueue_payload_upsert_surfaces_entity_version_stamp_failures() {
    let conn = test_db();
    conn.execute_batch("DROP TABLE tasks")
        .expect("drop task table to force version stamp failure");

    let error = enqueue_payload_upsert(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        &serde_json::json!({
            "id": "01966a3f-7c8b-7d4e-8f3a-000000002163",
            "title": "Stamped task",
            "status": "open",
        }),
        OutboxWriteContext {
            version: "1743280000000_0001_deadbeefdeadbeef",
            device_id: "dev-001",
        },
    )
    .expect_err("version stamp failures should abort enqueue");

    match error {
        EnqueueError::VersionStamp(crate::version_stamp::VersionStampError::Sqlite(error)) => {
            assert!(
                error.to_string().contains("no such table") || error.to_string().contains("tasks"),
                "unexpected error: {error}"
            );
        }
        other => panic!("expected sqlite error, got: {other}"),
    }

    let outbox_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM sync_outbox", [], |row| row.get(0))
        .unwrap();
    assert_eq!(outbox_count, 0, "enqueue should not persist an outbox row");
}

#[test]
fn enqueue_payload_delete_creates_tombstone_for_composite_edge() {
    let conn = test_db();
    insert_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000002165", "Task");
    insert_tag(&conn, "01966a3f-7c8b-7d4e-8f3a-000000002159", "Tag");
    insert_task_tag(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000002165",
        "01966a3f-7c8b-7d4e-8f3a-000000002159",
    );

    let version = "1743280000000_0001_deadbeefdeadbeef";
    enqueue_payload_delete(
        &conn,
        naming::EDGE_TASK_TAG,
        "01966a3f-7c8b-7d4e-8f3a-000000002165:01966a3f-7c8b-7d4e-8f3a-000000002159",
        &serde_json::json!({
            "task_id": "01966a3f-7c8b-7d4e-8f3a-000000002165",
            "tag_id": "01966a3f-7c8b-7d4e-8f3a-000000002159",
        }),
        OutboxWriteContext {
            version,
            device_id: "dev-001",
        },
    )
    .expect("delete enqueue should succeed");

    let tombstone_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_tombstones
             WHERE entity_type = ?1 AND entity_id = ?2 AND version = ?3",
            params![
                naming::EDGE_TASK_TAG,
                "01966a3f-7c8b-7d4e-8f3a-000000002165:01966a3f-7c8b-7d4e-8f3a-000000002159",
                version
            ],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(tombstone_count, 1, "delete enqueue must record a tombstone");
}

#[test]
fn enqueue_entity_upsert_preserves_forward_compat_shadow_fields_on_local_rewrite() {
    let conn = test_db();

    // Reproduce issue #2229's downgrade-echo shape on a single device:
    // first receive a future-schema envelope (unknown field preserved in a
    // payload shadow), then mutate a known local column and re-enqueue the
    // entity. The re-emitted payload must still carry the unknown field.
    let future_envelope = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Task,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-00000000219d".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567000_0000_a1b2c3d4a1b2c3d4")
            .expect("canonical fixture HLC must parse"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION + 1,
        payload: serde_json::json!({
            "id": "01966a3f-7c8b-7d4e-8f3a-00000000219d",
            "title": "Shadow title",
            "status": "open",
            "defer_count": 0,
            "created_at": "2026-04-19T10:00:00.000Z",
            "updated_at": "2026-04-19T10:00:00.000Z",
            "future_field": "preserve-me",
        })
        .to_string(),
        device_id: "future-peer".to_string(),
    };
    apply_envelope(&conn, &future_envelope)
        .expect("future-schema envelope should parse forward-compat");

    let shadow_before = lorvex_sync_payload::payload_shadow::get_shadow(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-00000000219d",
    )
    .expect("query payload shadow")
    .expect("forward-compat apply should store a shadow");
    assert_eq!(
        shadow_before.base_version,
        future_envelope.version.to_string()
    );

    conn.execute(
        "UPDATE tasks
         SET title = 'Locally edited title',
             updated_at = '2026-04-19T10:05:00.000Z'
         WHERE id = '01966a3f-7c8b-7d4e-8f3a-00000000219d'",
        [],
    )
    .unwrap();

    let mut hlc = setup_hlc();
    enqueue_entity_upsert(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-00000000219d",
        &mut hlc,
        "dev-001",
    )
    .expect("local rewrite should enqueue cleanly");

    let pending = outbox::get_pending(&conn).expect("read pending outbox");
    assert_eq!(pending.len(), 1, "expected exactly one re-emitted envelope");
    let payload: Value =
        serde_json::from_str(&pending[0].envelope.payload).expect("parse outbox payload");
    assert_eq!(
        payload.get("title").and_then(Value::as_str),
        Some("Locally edited title")
    );
    assert_eq!(
        payload.get("future_field").and_then(Value::as_str),
        Some("preserve-me"),
        "re-enqueue must merge unknown fields back from payload shadow"
    );
}
