use super::support::{
    enqueue_payload_upsert, insert_tag, insert_task, naming, outbox, params, test_db,
    OutboxWriteContext, SyncEnvelope, SyncOperation, PAYLOAD_SCHEMA_VERSION,
};

/// a child envelope that was deferred to the
/// pending inbox waiting on a missing local FK target must drain
/// in the SAME local-write transaction the user-authored parent
/// landed in — pre-fix the drain only ran after each remote
/// apply batch, so a user creating the parent locally had to
/// wait for the next remote pull before the child applied.
#[test]
fn local_fk_target_write_drains_pending_inbox_for_matching_child() {
    let conn = test_db();

    // A child envelope arrives from a peer naming the not-yet-
    // local parent task. The apply pipeline defers it to the
    // pending inbox with `missing_entity_*` set to the parent.
    // We model this by enqueuing directly into the inbox — the
    // production deferral path has been exercised elsewhere and
    // is not the surface this test pins.
    let parent_task_id = "01966a3f-7c8b-7d4e-8f3a-00000000218f";
    let child_envelope = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::TaskTag,
        entity_id: format!("{parent_task_id}:01966a3f-7c8b-7d4e-8f3a-000000002159"),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567000_0000_a1b2c3d4a1b2c3d4")
            .expect("canonical fixture HLC must parse"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: serde_json::json!({
            "task_id": parent_task_id,
            "tag_id": "01966a3f-7c8b-7d4e-8f3a-000000002159",
            "created_at": "2026-04-25T00:00:00.000Z",
        })
        .to_string(),
        device_id: "remote-peer".to_string(),
    };
    // Pre-create the tag so only the task FK is missing.
    insert_tag(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000002159",
        "01966a3f-7c8b-7d4e-8f3a-000000002159",
    );
    // The pending-inbox enqueue helper validates the payload
    // depth + parses canonical JSON; it accepts the deferred
    // envelope shape.
    crate::pending_inbox::enqueue_pending(
        &conn,
        &child_envelope,
        "fk_unresolved",
        Some(naming::ENTITY_TASK),
        Some(parent_task_id),
    )
    .unwrap();
    // Pre-condition: pending inbox holds the deferred child.
    let pending_count_before = crate::pending_inbox::count_pending(&conn).unwrap();
    assert_eq!(pending_count_before, 1);

    // The user (or a local writer) creates the missing parent.
    // The outbox enqueue path is what the UI / MCP / CLI all
    // route through; this is the hot path the M4 hook lives on.
    insert_task(&conn, parent_task_id, "Locally-authored parent");
    let parent_version = "1711234568000_0000_b2c3d4e5b2c3d4e5";
    enqueue_payload_upsert(
        &conn,
        naming::ENTITY_TASK,
        parent_task_id,
        &serde_json::json!({
            "id": parent_task_id,
            "title": "Locally-authored parent",
            "status": "open",
            "defer_count": 0,
            "created_at": "2026-04-25T00:00:00.000Z",
            "updated_at": "2026-04-25T00:00:00.000Z",
        }),
        OutboxWriteContext {
            version: parent_version,
            device_id: "dev-local",
        },
    )
    .unwrap();

    // Post-condition: the M4 drain hook fired during the parent
    // enqueue, the child found its FK target in the same
    // transaction, and the pending inbox is now empty.
    let pending_count_after = crate::pending_inbox::count_pending(&conn).unwrap();
    assert_eq!(
        pending_count_after, 0,
        "local parent write should have drained the deferred child \
         from the pending inbox in the same transaction"
    );

    // And the child landed against the live edge table.
    let task_tag_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_tags WHERE task_id = ?1 AND tag_id = ?2",
            params![parent_task_id, "01966a3f-7c8b-7d4e-8f3a-000000002159"],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        task_tag_count, 1,
        "child edge should have applied via the M4 drain"
    );
}

#[test]
fn autocommit_enqueue_rolls_back_parent_when_pending_drain_bookkeeping_fails() {
    let conn = lorvex_store::test_support::test_conn();
    assert!(
        conn.is_autocommit(),
        "public enqueue callers may reach this path without an outer transaction"
    );

    let parent_task_id = "01966a3f-7c8b-7d4e-8f3a-00000000218e";
    let child_envelope = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::TaskTag,
        entity_id: format!("{parent_task_id}:01966a3f-7c8b-7d4e-8f3a-00000000215a"),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567000_0000_a1b2c3d4a1b2c3d4")
            .expect("canonical fixture HLC must parse"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: serde_json::json!({
            "task_id": parent_task_id,
            "tag_id": "01966a3f-7c8b-7d4e-8f3a-00000000215a",
            "created_at": "2026-04-25T00:00:00.000Z",
        })
        .to_string(),
        device_id: "remote-peer".to_string(),
    };
    insert_tag(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000215a",
        "01966a3f-7c8b-7d4e-8f3a-00000000215a",
    );
    crate::pending_inbox::enqueue_pending(
        &conn,
        &child_envelope,
        "fk_unresolved",
        Some(naming::ENTITY_TASK),
        Some(parent_task_id),
    )
    .expect("enqueue deferred child");
    conn.execute_batch(
        "CREATE TRIGGER sync_pending_inbox_delete_block
         BEFORE DELETE ON sync_pending_inbox
         BEGIN
           SELECT RAISE(ABORT, 'test pending bookkeeping failure');
         END;",
    )
    .expect("install failing pending delete trigger");

    insert_task(&conn, parent_task_id, "Locally-authored parent");
    let err = enqueue_payload_upsert(
        &conn,
        naming::ENTITY_TASK,
        parent_task_id,
        &serde_json::json!({
            "id": parent_task_id,
            "title": "Locally-authored parent",
            "status": "open",
            "defer_count": 0,
            "created_at": "2026-04-25T00:00:00.000Z",
            "updated_at": "2026-04-25T00:00:00.000Z",
        }),
        OutboxWriteContext {
            version: "1711234568000_0000_b2c3d4e5b2c3d4e5",
            device_id: "dev-local",
        },
    )
    .expect_err("pending bookkeeping failure should abort the full enqueue transaction");
    assert!(
        err.to_string().contains("test pending bookkeeping failure"),
        "unexpected error: {err}"
    );

    assert_eq!(
        outbox::get_pending(&conn).unwrap().len(),
        0,
        "parent outbox row must roll back with the failed pending drain"
    );
    assert_eq!(
        crate::pending_inbox::count_pending(&conn).unwrap(),
        1,
        "deferred child must remain queued after the atomic rollback"
    );
    let task_tag_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_tags WHERE task_id = ?1 AND tag_id = ?2",
            params![parent_task_id, "01966a3f-7c8b-7d4e-8f3a-00000000215a"],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        task_tag_count, 0,
        "child edge apply must roll back with pending-row bookkeeping"
    );
}

/// when no pending entry references the just-
/// created `(entity_type, entity_id)` target, the drain hook
/// must NOT run — the cheap `has_pending_for_target` lookup is
/// the gate that keeps the per-write overhead negligible on the
/// (overwhelmingly common) hot path where no child is waiting.
#[test]
fn local_write_with_no_matching_pending_does_not_trigger_drain() {
    let conn = test_db();

    // Inbox is empty. Author a local parent.
    insert_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000218a", "Solo task");
    enqueue_payload_upsert(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-00000000218a",
        &serde_json::json!({
            "id": "01966a3f-7c8b-7d4e-8f3a-00000000218a",
            "title": "Solo task",
            "status": "open",
            "defer_count": 0,
            "created_at": "2026-04-25T00:00:00.000Z",
            "updated_at": "2026-04-25T00:00:00.000Z",
        }),
        OutboxWriteContext {
            version: "1711234568000_0000_b2c3d4e5b2c3d4e5",
            device_id: "dev-local",
        },
    )
    .unwrap();
    // The outbox row is the only side effect we care about
    // here — the test passes by virtue of not panicking on the
    // skipped drain path. Sanity-check the outbox row exists.
    assert_eq!(outbox::get_pending(&conn).unwrap().len(), 1);
}
