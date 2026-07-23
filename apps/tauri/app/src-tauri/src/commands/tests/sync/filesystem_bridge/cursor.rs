use super::*;

#[test]
fn load_filesystem_bridge_pull_cursor_rejects_malformed_state() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        params![
            SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LAST_PULL_CURSOR_KEY,
            r#"{"oops":1}"#
        ],
    )
    .expect("insert malformed cursor");

    let error =
        load_filesystem_bridge_pull_cursor(&conn).expect_err("malformed cursor state should fail");
    let message = error.to_string().to_lowercase();
    assert!(message.contains("filesystem bridge"));
    assert!(message.contains("cursor"));

    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![
            SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LAST_PULL_CURSOR_KEY,
            r#"{"updated_at":"0001743573600000_0001_6465766963656231","device_id":"device-b","event_id":"evt-b"}"#
        ],
    )
    .expect("insert valid filesystem bridge cursor");

    let cursor = load_filesystem_bridge_pull_cursor(&conn)
        .expect("load cursor")
        .expect("cursor should exist");
    assert_eq!(cursor.updated_at, "0001743573600000_0001_6465766963656231");
    assert_eq!(cursor.device_id, "device-b");
    assert_eq!(cursor.event_id, "evt-b");
}

#[test]
fn load_filesystem_bridge_pull_cursor_rejects_invalid_timestamp_state() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        params![
            SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LAST_PULL_CURSOR_KEY,
            r#"{"updated_at":"not-a-timestamp","device_id":"device-b","event_id":"evt-b"}"#,
        ],
    )
    .expect("insert invalid timestamp cursor");

    let error = load_filesystem_bridge_pull_cursor(&conn)
        .expect_err("invalid timestamp cursor should fail");
    let message = error.to_string().to_lowercase();
    assert!(message.contains("filesystem bridge"));
    assert!(message.contains("cursor"));
}

#[test]
fn load_filesystem_bridge_pull_cursor_rejects_empty_device_id_state() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        params![
            SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LAST_PULL_CURSOR_KEY,
            r#"{"updated_at":"0001743573600000_0001_6465766963656231","device_id":"   ","event_id":"evt-b"}"#,
        ],
    )
    .expect("insert empty device_id cursor");

    let error =
        load_filesystem_bridge_pull_cursor(&conn).expect_err("empty device_id cursor should fail");
    let message = error.to_string().to_lowercase();
    assert!(message.contains("filesystem bridge"));
    assert!(message.contains("cursor"));
}

#[test]
fn newest_filesystem_bridge_pull_cursor_uses_event_id_tie_break() {
    let events = vec![
        make_sync_event(
            "evt-a",
            "task",
            "task-1",
            "upsert",
            serde_json::json!({}),
            "2026-03-02T10:00:00.000001Z",
            "device-z",
        ),
        make_sync_event(
            "evt-z",
            "task",
            "task-2",
            "upsert",
            serde_json::json!({}),
            "2026-03-02T10:00:00.000001Z",
            "device-z",
        ),
    ];
    let cursor = newest_filesystem_bridge_pull_cursor(&events).expect("cursor should exist");
    // Both events have the same HLC version (same timestamp + same device).
    // The tie-break is by event_id: "evt-z" > "evt-a".
    assert_eq!(cursor.device_id, "device-z");
    assert_eq!(cursor.event_id, "evt-z");
}

#[test]
fn newest_filesystem_bridge_pull_cursor_ignores_empty_device_id_events() {
    let events = vec![
        make_sync_event(
            "evt-empty-device",
            "task",
            "task-empty-device",
            "upsert",
            serde_json::json!({}),
            "2026-03-02T10:00:00.000001Z",
            "   ",
        ),
        make_sync_event(
            "evt-valid",
            "task",
            "task-valid",
            "upsert",
            serde_json::json!({}),
            "2026-03-02T10:00:00.000001Z",
            "device-a",
        ),
    ];

    let cursor = newest_filesystem_bridge_pull_cursor(&events).expect("cursor should exist");
    assert_eq!(cursor.device_id, "device-a");
    assert_eq!(cursor.event_id, "evt-valid");

    let invalid_only = vec![make_sync_event(
        "evt-empty-device",
        "task",
        "task-empty-device",
        "upsert",
        serde_json::json!({}),
        "2026-03-02T10:00:00.000001Z",
        "   ",
    )];
    assert!(
        newest_filesystem_bridge_pull_cursor(&invalid_only).is_none(),
        "all-invalid device ids should not produce a persisted cursor"
    );
}

#[test]
fn store_filesystem_bridge_pull_cursor_is_monotonic() {
    let conn = setup_sync_test_conn();
    let newest = FilesystemBridgePullCursor {
        updated_at: "0001743573600002_0001_6465766963657a31".to_string(),
        device_id: "device-z".to_string(),
        event_id: "evt-z".to_string(),
    };
    let older = FilesystemBridgePullCursor {
        updated_at: "0001743573600001_0001_6465766963656131".to_string(),
        device_id: "device-a".to_string(),
        event_id: "evt-a".to_string(),
    };

    store_filesystem_bridge_pull_cursor(&conn, &newest).expect("store newest cursor");
    store_filesystem_bridge_pull_cursor(&conn, &older).expect("ignore older cursor");

    let persisted = load_filesystem_bridge_pull_cursor(&conn)
        .expect("load persisted cursor")
        .expect("cursor should exist");
    assert_eq!(persisted.updated_at, newest.updated_at);
    assert_eq!(persisted.device_id, newest.device_id);
    assert_eq!(persisted.event_id, newest.event_id);
}

#[test]
fn store_filesystem_bridge_pull_cursor_rejects_empty_fields() {
    let conn = setup_sync_test_conn();
    let invalid = FilesystemBridgePullCursor {
        updated_at: "0001743573600002_0001_6465766963657a31".to_string(),
        device_id: "   ".to_string(),
        event_id: "evt-z".to_string(),
    };

    let error = store_filesystem_bridge_pull_cursor(&conn, &invalid)
        .expect_err("empty device ids should fail validation");
    let message = error.to_string();
    assert!(message.contains("cannot be empty"));
}
