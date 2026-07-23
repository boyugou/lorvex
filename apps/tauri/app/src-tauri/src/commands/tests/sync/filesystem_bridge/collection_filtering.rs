use super::*;
#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

#[test]
fn collect_remote_filesystem_bridge_envelopes_accounts_parse_errors_and_local_filter() {
    let dir = unique_test_dir("sync-filesystem-bridge-errors");
    fs::create_dir_all(&dir).expect("create sync test dir");

    write_sync_envelope_file(
        &dir,
        "event-local",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f101",
        "upsert",
        json!({}),
        "2026-03-02T11:00:00Z",
        "device-local",
    );
    write_sync_envelope_file(
        &dir,
        "event-unsupported",
        "unsupported",
        "01966a3f-7c8b-7d4e-8f3a-00000000f102",
        "upsert",
        json!({}),
        "2026-03-02T11:00:01Z",
        "device-remote-a",
    );
    fs::write(dir.join("malformed.json"), "{not-valid-json").expect("write malformed file");
    write_sync_envelope_file(
        &dir,
        "event-invalid-version",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f103",
        "upsert",
        json!({}),
        "not-a-valid-hlc",
        "device-remote-bad",
    );
    write_sync_envelope_file(
        &dir,
        "event-remote",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f104",
        "upsert",
        json!({}),
        "2026-03-02T11:00:02Z",
        "device-remote-b",
    );

    let collected =
        collect_remote_filesystem_bridge_envelopes(&dir, "device-local", 10, None, None)
            .expect("collect events");

    assert_eq!(collected.pulled_files, 5);
    assert_eq!(collected.pull_parse_errors, 3);
    assert_eq!(collected.remote_events.len(), 1);
    assert_eq!(collected.remote_events[0].id, "event-remote");

    fs::remove_dir_all(&dir).ok();
}

#[test]
fn collect_remote_filesystem_bridge_envelopes_applies_filesystem_bridge_cursor_filtering() {
    let dir = unique_test_dir("sync-filesystem-bridge-cursor-filter");
    fs::create_dir_all(&dir).expect("create sync test dir");

    write_sync_envelope_file(
        &dir,
        "event-a",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f105",
        "upsert",
        json!({}),
        "2026-03-02T10:00:00Z",
        "device-a",
    );
    write_sync_envelope_file(
        &dir,
        "event-b",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f106",
        "upsert",
        json!({}),
        "2026-03-02T10:00:00Z",
        "device-a",
    );
    write_sync_envelope_file(
        &dir,
        "event-c",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f107",
        "upsert",
        json!({}),
        "2026-03-02T10:00:00Z",
        "device-c",
    );
    write_sync_envelope_file(
        &dir,
        "event-d",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f108",
        "upsert",
        json!({}),
        "2026-03-02T11:00:00Z",
        "device-a",
    );

    let cursor = FilesystemBridgePullCursor {
        updated_at: make_hlc_version("2026-03-02T10:00:00Z", "device-a").to_string(),
        device_id: "device-a".to_string(),
        event_id: "event-b".to_string(),
    };
    let collected =
        collect_remote_filesystem_bridge_envelopes(&dir, "device-local", 10, Some(&cursor), None)
            .expect("collect events");

    assert_eq!(collected.remote_events.len(), 2);
    assert_eq!(collected.remote_events[0].id, "event-c");
    assert_eq!(collected.remote_events[1].id, "event-d");

    fs::remove_dir_all(&dir).ok();
}

#[cfg(unix)]
#[test]
fn collect_remote_filesystem_bridge_envelopes_rejects_unreadable_files() {
    let dir = unique_test_dir("sync-filesystem-bridge-unreadable");
    fs::create_dir_all(&dir).expect("create sync test dir");

    let unreadable = dir.join("event-unreadable.json");
    fs::write(
        &unreadable,
        serde_json::to_vec(&json!({
            "entity_type": "task",
            "entity_id": "01966a3f-7c8b-7d4e-8f3a-00000000f109",
            "operation": "upsert",
            "payload": {},
            "version": make_hlc_version("2026-03-02T11:00:03Z", "device-remote-a"),
            "updated_at": "2026-03-02T11:00:03Z",
            "device_id": "device-remote-a",
        }))
        .expect("serialize unreadable envelope"),
    )
    .expect("write unreadable sync file");
    fs::set_permissions(&unreadable, std::fs::Permissions::from_mode(0o000))
        .expect("make unreadable sync file");

    let error = collect_remote_filesystem_bridge_envelopes(&dir, "device-local", 10, None, None)
        .expect_err("unreadable sync file should fail fast");
    let message = error.to_string();
    assert!(
        message.contains("Failed to open filesystem bridge sync file")
            || message.contains("Failed to read filesystem bridge sync file"),
        "unexpected error: {message}"
    );

    fs::set_permissions(&unreadable, std::fs::Permissions::from_mode(0o600))
        .expect("restore unreadable sync file permissions");
    fs::remove_dir_all(&dir).ok();
}
