use super::*;

#[test]
fn collect_remote_filesystem_bridge_envelopes_includes_delayed_event_within_cursor_lookback() {
    let dir = unique_test_dir("sync-filesystem-bridge-cursor-lookback");
    fs::create_dir_all(&dir).expect("create sync test dir");

    write_sync_envelope_file(
        &dir,
        "event-delayed",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f301",
        "upsert",
        json!({
            "id": "01966a3f-7c8b-7d4e-8f3a-00000000f301",
            "title": "Delayed event",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T10:00:00Z",
        "device-a",
    );

    let cursor = FilesystemBridgePullCursor {
        updated_at: "2026-03-02T10:00:00Z".to_string(),
        device_id: "device-z".to_string(),
        event_id: "event-z".to_string(),
    };
    let collected =
        collect_remote_filesystem_bridge_envelopes(&dir, "device-local", 10, Some(&cursor), None)
            .expect("collect events");

    assert_eq!(collected.remote_events.len(), 1);
    assert_eq!(collected.remote_events[0].id, "event-delayed");
    assert_eq!(collected.lookback_known_id_skipped, 0);

    fs::remove_dir_all(&dir).ok();
}

#[test]
fn collect_remote_filesystem_bridge_envelopes_lookback_skips_known_event_ids() {
    let dir = unique_test_dir("sync-filesystem-bridge-lookback-known-id-skip");
    fs::create_dir_all(&dir).expect("create sync test dir");

    write_sync_envelope_file(
        &dir,
        "event-delayed",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f301",
        "upsert",
        json!({
            "id": "01966a3f-7c8b-7d4e-8f3a-00000000f301",
            "title": "Delayed event",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T10:00:00Z",
        "device-a",
    );

    let cursor = FilesystemBridgePullCursor {
        updated_at: "2026-03-02T10:00:00Z".to_string(),
        device_id: "device-z".to_string(),
        event_id: "event-z".to_string(),
    };
    let mut known_event_ids = HashSet::new();
    known_event_ids.insert("event-delayed".to_string());
    let collected = collect_remote_filesystem_bridge_envelopes(
        &dir,
        "device-local",
        10,
        Some(&cursor),
        Some(&known_event_ids),
    )
    .expect("collect events");

    assert!(collected.remote_events.is_empty());
    assert_eq!(collected.lookback_known_id_skipped, 1);

    fs::remove_dir_all(&dir).ok();
}
