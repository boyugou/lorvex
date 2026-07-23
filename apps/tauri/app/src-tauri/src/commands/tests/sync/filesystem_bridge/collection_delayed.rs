use super::*;

#[test]
fn delayed_event_at_or_behind_cursor_is_accounted_as_stale_when_newer_entity_exists() {
    let conn = setup_sync_test_conn();
    let newer_event = make_sync_event(
        "event-newer",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f401",
        "upsert",
        json!({
            "id": "01966a3f-7c8b-7d4e-8f3a-00000000f401",
            "title": "Newest title",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T10:01:00Z",
        "device-z",
    );
    apply_remote_sync_envelopes_internal(&conn, vec![newer_event], "2026-03-02T10:02:00Z")
        .expect("seed newer entity version");

    let dir = unique_test_dir("sync-filesystem-bridge-delayed-stale-accounting");
    fs::create_dir_all(&dir).expect("create sync test dir");

    write_sync_envelope_file(
        &dir,
        "event-delayed",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f401",
        "upsert",
        json!({
            "id": "01966a3f-7c8b-7d4e-8f3a-00000000f401",
            "title": "Delayed title",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T10:00:00Z",
        "device-a",
    );

    let cursor = FilesystemBridgePullCursor {
        updated_at: "2026-03-02T10:05:00Z".to_string(),
        device_id: "device-z".to_string(),
        event_id: "event-z".to_string(),
    };
    let collected =
        collect_remote_filesystem_bridge_envelopes(&dir, "device-local", 10, Some(&cursor), None)
            .expect("collect delayed events");
    assert_eq!(collected.remote_events.len(), 1);

    let apply = apply_remote_sync_envelopes_internal(
        &conn,
        collected.remote_events,
        "2026-03-02T10:06:00Z",
    )
    .expect("apply delayed events");

    assert_eq!(apply.received, 1);
    assert_eq!(apply.processed, 1);
    assert_eq!(apply.applied, 0);
    assert_eq!(apply.skipped_stale, 1);

    fs::remove_dir_all(&dir).ok();
}
