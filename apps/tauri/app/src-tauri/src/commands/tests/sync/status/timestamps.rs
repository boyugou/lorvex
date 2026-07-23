use super::*;

#[test]
fn sync_checkpoints_survives_offline_online_transition_without_timestamp_regression() {
    let conn = setup_sync_test_conn();
    // Insert outbox entries via the helper (which now inserts into sync_outbox).
    insert_sync_event_row(
        &conn,
        "event-online",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f501",
        "upsert",
        json!({
            "id": "01966a3f-7c8b-7d4e-8f3a-00000000f501",
            "title": "Online write",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T12:00:00Z",
        "device-online",
        None,
    );
    insert_sync_event_row(
        &conn,
        "event-offline",
        "task",
        "task-2",
        "upsert",
        json!({
            "id": "task-2",
            "title": "Offline write",
            "status": "open",
            "created_at": "2026-03-02T07:00:00Z"
        }),
        "2026-03-02T11:30:00Z",
        "device-offline",
        None,
    );

    // Get the auto-assigned integer IDs.
    let online_id: i64 = conn
        .query_row(
            "SELECT id FROM sync_outbox WHERE entity_id = '01966a3f-7c8b-7d4e-8f3a-00000000f501' LIMIT 1",
            [],
            |row| row.get(0),
        )
        .expect("get online event id");
    let offline_id: i64 = conn
        .query_row(
            "SELECT id FROM sync_outbox WHERE entity_id = 'task-2' LIMIT 1",
            [],
            |row| row.get(0),
        )
        .expect("get offline event id");

    let online_ts = "2026-03-02T12:00:00Z";
    mark_outbox_entries_synced_internal(&conn, &[online_id.to_string()], online_ts)
        .expect("mark online event synced");
    apply_remote_sync_envelopes_internal(&conn, Vec::new(), online_ts)
        .expect("record online pull watermark");

    mark_outbox_entries_synced_internal(&conn, &[offline_id.to_string()], "2026-03-02T11:30:00Z")
        .expect("mark delayed offline event synced");
    apply_remote_sync_envelopes_internal(&conn, Vec::new(), "2026-03-02T11:45:00Z")
        .expect("record delayed offline pull watermark");

    let last_success_at: String = conn
        .query_row(
            "SELECT value FROM sync_checkpoints WHERE key = 'last_success_at'",
            [],
            |row| row.get(0),
        )
        .expect("read last_success_at");
    let last_pull_at: String = conn
        .query_row(
            "SELECT value FROM sync_checkpoints WHERE key = 'last_pull_at'",
            [],
            |row| row.get(0),
        )
        .expect("read last_pull_at");

    assert_eq!(last_success_at, online_ts);
    assert_eq!(last_pull_at, online_ts);
}

#[test]
fn apply_remote_sync_envelopes_with_cursor_persists_checkpoint_on_success() {
    let conn = setup_sync_test_conn();
    let event = make_sync_event(
        "evt-cursor-ok",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f502",
        "upsert",
        json!({
            "id": "01966a3f-7c8b-7d4e-8f3a-00000000f502",
            "title": "Cursor Atomicity",
            "status": "open",
            "updated_at": "2026-03-02T10:00:00Z",
        }),
        "2026-03-02T10:00:00Z",
        "device-remote-a",
    );
    // Use HLC-format version for cursor (must contain '_' to pass validation).
    let hlc_version = make_hlc_version("2026-03-02T10:00:00Z", "device-remote-a").to_string();
    let cursor = FilesystemBridgePullCursor {
        updated_at: hlc_version,
        device_id: "device-remote-a".to_string(),
        event_id: "evt-cursor-ok".to_string(),
    };

    let result = apply_remote_sync_envelopes_with_filesystem_bridge_cursor(
        &conn,
        vec![event],
        "2026-03-02T10:01:00Z",
        Some(&cursor),
    )
    .expect("apply with cursor should succeed");

    assert_eq!(result.applied, 1);
    let persisted = load_filesystem_bridge_pull_cursor(&conn)
        .expect("load filesystem bridge cursor")
        .expect("cursor should persist");
    assert_eq!(persisted.updated_at, cursor.updated_at);
    assert_eq!(persisted.device_id, cursor.device_id);
    assert_eq!(persisted.event_id, cursor.event_id);
}

#[test]
fn apply_remote_sync_envelopes_with_cursor_rolls_back_cursor_on_failure() {
    let conn = setup_sync_test_conn();
    let valid_event = make_sync_event(
        "evt-valid",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f503",
        "upsert",
        json!({
            "id": "01966a3f-7c8b-7d4e-8f3a-00000000f503",
            "title": "Should Roll Back",
            "status": "open",
            "updated_at": "2026-03-02T10:00:00Z",
        }),
        "2026-03-02T10:00:00Z",
        "device-remote-a",
    );
    // Same rationale as remote checkpoint: post-#3004-H1 the typed
    // `EntityKind` wire boundary rejects unknown variants before
    // they reach apply, so the apply-time failure path uses a
    // malformed `task_dependency` edge id instead.
    let invalid_event = make_sync_event(
        "evt-invalid",
        "task_dependency",
        "invalid-no-colon",
        "upsert",
        serde_json::json!({}),
        "2026-03-02T10:00:01Z",
        "device-remote-b",
    );
    let cursor = FilesystemBridgePullCursor {
        updated_at: "2026-03-02T10:00:01Z".to_string(),
        device_id: "device-remote-b".to_string(),
        event_id: "evt-invalid".to_string(),
    };

    let result = apply_remote_sync_envelopes_with_filesystem_bridge_cursor(
        &conn,
        vec![valid_event, invalid_event],
        "2026-03-02T10:02:00Z",
        Some(&cursor),
    );
    assert!(result.is_err());

    let persisted =
        load_filesystem_bridge_pull_cursor(&conn).expect("load filesystem bridge cursor");
    assert!(persisted.is_none());
}

#[test]
fn upsert_sync_checkpoint_timestamp_if_newer_recovers_from_malformed_existing_value() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        params!["last_success_at", "zzzz-not-a-timestamp"],
    )
    .expect("seed malformed sync state");

    upsert_sync_checkpoint_timestamp_if_newer(&conn, "last_success_at", "2026-03-02T12:00:00Z")
        .expect("recover from malformed existing value");

    let value: String = conn
        .query_row(
            "SELECT value FROM sync_checkpoints WHERE key = 'last_success_at'",
            [],
            |row| row.get(0),
        )
        .expect("read last_success_at");
    assert_eq!(value, "2026-03-02T12:00:00Z");
}

#[test]
fn upsert_sync_checkpoint_timestamp_if_newer_ignores_invalid_candidate_when_existing_is_valid() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        params!["last_success_at", "2026-03-02T12:00:00Z"],
    )
    .expect("seed valid sync state");

    upsert_sync_checkpoint_timestamp_if_newer(&conn, "last_success_at", "zzzz-not-a-timestamp")
        .expect("ignore invalid candidate");

    let value: String = conn
        .query_row(
            "SELECT value FROM sync_checkpoints WHERE key = 'last_success_at'",
            [],
            |row| row.get(0),
        )
        .expect("read last_success_at");
    assert_eq!(value, "2026-03-02T12:00:00Z");
}
