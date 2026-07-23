use super::*;

#[test]
fn collect_remote_filesystem_bridge_envelopes_is_deterministic_under_pull_cap() {
    let dir = unique_test_dir("sync-filesystem-bridge-order");
    fs::create_dir_all(&dir).expect("create sync test dir");

    write_sync_envelope_file(
        &dir,
        "event-a",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f201",
        "upsert",
        json!({}),
        "2026-03-02T10:00:00Z",
        "device-remote-a",
    );
    write_sync_envelope_file(
        &dir,
        "event-b",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f202",
        "upsert",
        json!({}),
        "2026-03-02T10:00:01Z",
        "device-remote-b",
    );

    fs::write(dir.join("ignore.txt"), "noop").expect("write non-json file");
    fs::create_dir_all(dir.join("nested")).expect("create nested dir");

    let collected = collect_remote_filesystem_bridge_envelopes(&dir, "device-local", 1, None, None)
        .expect("collect events");

    assert_eq!(collected.pulled_files, 2);
    assert_eq!(collected.pull_parse_errors, 0);
    assert_eq!(collected.remote_events.len(), 1);
    assert_eq!(collected.remote_events[0].id, "event-a");

    fs::remove_dir_all(&dir).ok();
}

#[test]
fn collect_remote_filesystem_bridge_envelopes_prioritizes_sync_version_over_filename_order() {
    let dir = unique_test_dir("sync-filesystem-bridge-priority");
    fs::create_dir_all(&dir).expect("create sync test dir");

    write_sync_envelope_file(
        &dir,
        "event-newer",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f203",
        "upsert",
        json!({}),
        "2026-03-02T12:00:00Z",
        "device-remote-z",
    );
    write_sync_envelope_file(
        &dir,
        "event-older",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f204",
        "upsert",
        json!({}),
        "2026-03-02T11:00:00Z",
        "device-remote-a",
    );

    let collected = collect_remote_filesystem_bridge_envelopes(&dir, "device-local", 1, None, None)
        .expect("collect events");

    assert_eq!(collected.remote_events.len(), 1);
    assert_eq!(collected.remote_events[0].id, "event-older");

    fs::remove_dir_all(&dir).ok();
}

#[test]
fn collect_remote_filesystem_bridge_envelopes_sets_pull_limit_hit_when_candidates_exceed_cap() {
    let dir = unique_test_dir("sync-filesystem-bridge-pull-limit-hit");
    fs::create_dir_all(&dir).expect("create sync test dir");

    write_sync_envelope_file(
        &dir,
        "event-oldest",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f205",
        "upsert",
        json!({}),
        "2026-03-02T10:00:00Z",
        "device-remote-a",
    );
    write_sync_envelope_file(
        &dir,
        "event-middle",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f206",
        "upsert",
        json!({}),
        "2026-03-02T11:00:00Z",
        "device-remote-b",
    );
    write_sync_envelope_file(
        &dir,
        "event-newest",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f207",
        "upsert",
        json!({}),
        "2026-03-02T12:00:00Z",
        "device-remote-c",
    );

    let collected = collect_remote_filesystem_bridge_envelopes(&dir, "device-local", 2, None, None)
        .expect("collect events");

    assert!(collected.pull_limit_hit);
    assert_eq!(collected.remote_events.len(), 2);
    assert_eq!(collected.remote_events[0].id, "event-oldest");
    assert_eq!(collected.remote_events[1].id, "event-middle");

    fs::remove_dir_all(&dir).ok();
}

#[test]
fn collect_remote_filesystem_bridge_envelopes_under_pull_cap_progresses_without_skipping_backlog() {
    let dir = unique_test_dir("sync-filesystem-bridge-pull-cap-progress");
    fs::create_dir_all(&dir).expect("create sync test dir");

    write_sync_envelope_file(
        &dir,
        "event-oldest",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f205",
        "upsert",
        json!({}),
        "2026-03-02T10:00:00Z",
        "device-remote-a",
    );
    write_sync_envelope_file(
        &dir,
        "event-middle",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f206",
        "upsert",
        json!({}),
        "2026-03-02T11:00:00Z",
        "device-remote-b",
    );
    write_sync_envelope_file(
        &dir,
        "event-newest",
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000f207",
        "upsert",
        json!({}),
        "2026-03-02T12:00:00Z",
        "device-remote-c",
    );

    let first_batch =
        collect_remote_filesystem_bridge_envelopes(&dir, "device-local", 2, None, None)
            .expect("collect first batch");
    assert_eq!(first_batch.remote_events.len(), 2);
    assert_eq!(first_batch.remote_events[0].id, "event-oldest");
    assert_eq!(first_batch.remote_events[1].id, "event-middle");
    let first_cursor =
        newest_filesystem_bridge_pull_cursor(&first_batch.remote_events).expect("first cursor");

    let second_batch = collect_remote_filesystem_bridge_envelopes(
        &dir,
        "device-local",
        2,
        Some(&first_cursor),
        None,
    )
    .expect("collect second batch");
    assert_eq!(second_batch.remote_events.len(), 1);
    assert_eq!(second_batch.remote_events[0].id, "event-newest");

    fs::remove_dir_all(&dir).ok();
}
