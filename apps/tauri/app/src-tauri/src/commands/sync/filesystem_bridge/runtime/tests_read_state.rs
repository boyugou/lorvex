use super::tests_support::*;
use super::*;

#[test]
fn phase_read_outbox_auto_seeds_when_full_sync_seed_checkpoint_is_missing() {
    let conn = setup_runtime_test_conn();
    crate::commands::sync::runtime::seed_full_sync_internal(&conn).expect("initial seed succeeds");
    conn.execute("DELETE FROM sync_outbox", [])
        .expect("clear staged outbox");
    lorvex_runtime::sync_checkpoint_clear(&conn, lorvex_runtime::KEY_FULL_SYNC_SEEDED)
        .expect("simulate snapshot import clearing the seed checkpoint");

    let sync_dir =
        std::env::temp_dir().join(format!("lorvex-fs-sync-test-{}", uuid::Uuid::now_v7()));
    let sync_dir_display = sync_dir.to_string_lossy().to_string();

    let read_state = phase_read_outbox_and_pull_state(&conn, &sync_dir, &sync_dir_display, 200)
        .expect("phase_read_outbox_and_pull_state should succeed")
        .expect("missing seed checkpoint should auto-seed, not pause");

    assert!(
        !read_state.pending.is_empty(),
        "filesystem bridge must rebuild pending outbox rows when the seed checkpoint is missing"
    );
    assert_eq!(
        lorvex_runtime::sync_checkpoint_get(&conn, lorvex_runtime::KEY_FULL_SYNC_SEEDED)
            .expect("read full-sync seeded checkpoint")
            .as_deref(),
        Some("1")
    );
}

#[test]
fn phase_read_outbox_defers_missing_full_sync_seed_when_remote_envelopes_exist() {
    let conn = setup_runtime_test_conn();
    crate::commands::sync::runtime::seed_full_sync_internal(&conn).expect("initial seed succeeds");
    conn.execute("DELETE FROM sync_outbox", [])
        .expect("clear staged outbox");
    lorvex_runtime::sync_checkpoint_clear(&conn, lorvex_runtime::KEY_FULL_SYNC_SEEDED)
        .expect("simulate snapshot import clearing the seed checkpoint");

    let sync_dir =
        std::env::temp_dir().join(format!("lorvex-fs-sync-test-{}", uuid::Uuid::now_v7()));
    fs::create_dir_all(&sync_dir).expect("create sync dir");
    fs::write(
        sync_dir.join("remote-device_00000000000000000001.json"),
        "{}",
    )
    .expect("write remote envelope sentinel");
    let sync_dir_display = sync_dir.to_string_lossy().to_string();

    let read_state = phase_read_outbox_and_pull_state(&conn, &sync_dir, &sync_dir_display, 200)
        .expect("phase_read_outbox_and_pull_state should succeed")
        .expect("remote envelopes should defer auto-seed until after pull");

    assert!(
        read_state.pending.is_empty(),
        "fresh joiners must not push local seed rows before pulling existing remote state"
    );
    assert_eq!(
        lorvex_runtime::sync_checkpoint_get(&conn, lorvex_runtime::KEY_FULL_SYNC_SEEDED)
            .expect("read full-sync seeded checkpoint"),
        None
    );
}

#[test]
fn phase_read_outbox_returns_reseed_result_when_reseed_is_required() {
    let conn = setup_runtime_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES ('reseed_required', 'true')",
        [],
    )
    .expect("insert reseed checkpoint");
    let sync_dir =
        std::env::temp_dir().join(format!("lorvex-fs-sync-test-{}", uuid::Uuid::now_v7()));
    let sync_dir_display = sync_dir.to_string_lossy().to_string();

    // Test the reseed check directly (run_filesystem_bridge_sync_inner now
    // acquires its own connection via get_conn(), which isn't available in
    // unit tests).
    let result = phase_read_outbox_and_pull_state(&conn, &sync_dir, &sync_dir_display, 200)
        .expect("phase_read_outbox_and_pull_state should succeed");
    let reseed_result = result.expect_err("should return reseed early-exit result");

    assert!(reseed_result.reseed_paused);
    assert_eq!(reseed_result.attempted_push, 0);
    assert_eq!(reseed_result.pushed, 0);
    assert_eq!(reseed_result.pulled_remote_events, 0);
    assert_eq!(
        reseed_result.filesystem_bridge_root_path,
        sync_dir.to_string_lossy()
    );

    let row: (String, String, String, String) = conn
        .query_row(
            "SELECT source, level, message, details
             FROM error_logs
             WHERE source = 'sync.filesystem_bridge.runtime.reseed_required'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("read reseed-required diagnostic");

    assert_eq!(row.0, "sync.filesystem_bridge.runtime.reseed_required");
    assert_eq!(row.1, "warn");
    assert_eq!(
        row.2,
        "Filesystem bridge incremental sync paused because reseed is required"
    );
    assert!(row.3.contains(&sync_dir_display));
}
