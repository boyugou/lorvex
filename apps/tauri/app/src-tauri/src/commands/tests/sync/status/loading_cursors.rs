use super::*;

#[test]
fn load_sync_status_from_conn_surfaces_filesystem_bridge_cursor_state() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        params![
            SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LAST_PULL_CURSOR_KEY,
            r#"{"updated_at":"0001743573600000_0001_6465766963656131","device_id":"device-a","event_id":"evt-a"}"#
        ],
    )
    .expect("insert filesystem bridge cursor state");
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?4, ?3)",
        params![
            lorvex_domain::preference_keys::PREF_SYNC_BACKEND_KIND,
            r#""filesystem_bridge""#,
            "0001743573600000_0001_6465766963656131",
            TEST_VERSION,
        ],
    )
    .expect("insert sync backend kind preference");

    let status = load_sync_status_from_conn(&conn).expect("load sync status");
    assert_eq!(
        status.filesystem_bridge_last_pull_cursor,
        Some(
            r#"{"updated_at":"0001743573600000_0001_6465766963656131","device_id":"device-a","event_id":"evt-a"}"#
                .to_string()
        )
    );
    assert_eq!(
        status.filesystem_bridge_last_pull_updated_at,
        Some("0001743573600000_0001_6465766963656131".to_string())
    );
    assert_eq!(
        status.filesystem_bridge_last_pull_device_id,
        Some("device-a".to_string())
    );
    assert_eq!(
        status.filesystem_bridge_last_pull_event_id,
        Some("evt-a".to_string())
    );
    assert!(!status.filesystem_bridge_last_pull_cursor_malformed);
    assert!(!status.last_synced_at_malformed);
    assert!(!status.last_success_at_malformed);
    assert!(!status.last_pull_at_malformed);
    assert_eq!(
        status.filesystem_bridge_lookback_known_id_skipped_last_run,
        0
    );
    assert!(!status.filesystem_bridge_lookback_known_id_skipped_last_run_malformed);
    assert_eq!(
        status.filesystem_bridge_lookback_known_id_skipped_last_run_at,
        None
    );
    assert!(!status.filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed);
    assert_eq!(
        status.sync_backend_kind,
        Some("filesystem_bridge".to_string())
    );
    assert_eq!(
        status.sync_backend_kind_effective,
        "filesystem_bridge".to_string()
    );
    assert_eq!(
        status.filesystem_bridge_last_pull_cursor_malformed_reason,
        None
    );
}

#[test]
fn load_sync_status_from_conn_tolerates_malformed_filesystem_bridge_cursor_state() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        params![
            SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LAST_PULL_CURSOR_KEY,
            r#"{"oops":1}"#
        ],
    )
    .expect("insert malformed filesystem bridge cursor");

    let status = load_sync_status_from_conn(&conn).expect("load sync status");
    assert_eq!(
        status.filesystem_bridge_last_pull_cursor,
        Some(r#"{"oops":1}"#.to_string())
    );
    assert!(status.filesystem_bridge_last_pull_cursor_malformed);
    assert_eq!(status.filesystem_bridge_last_pull_updated_at, None);
    assert_eq!(status.filesystem_bridge_last_pull_device_id, None);
    assert_eq!(status.filesystem_bridge_last_pull_event_id, None);
    assert_eq!(
        status.filesystem_bridge_last_pull_cursor_malformed_reason,
        Some("missing_or_invalid_updated_at".to_string())
    );
    assert!(!status.last_synced_at_malformed);
    assert!(!status.last_success_at_malformed);
    assert!(!status.last_pull_at_malformed);
    assert_eq!(
        status.filesystem_bridge_lookback_known_id_skipped_last_run,
        0
    );
    assert!(!status.filesystem_bridge_lookback_known_id_skipped_last_run_malformed);
    assert_eq!(
        status.filesystem_bridge_lookback_known_id_skipped_last_run_at,
        None
    );
    assert!(!status.filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed);
}

#[test]
fn load_sync_status_from_conn_separates_raw_parsed_and_effective_sync_backend_kind() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?4, ?3)",
        params![
            lorvex_domain::preference_keys::PREF_SYNC_BACKEND_KIND,
            "filesystem_bridge",
            "0001743573600000_0001_6465766963656131",
            TEST_VERSION,
        ],
    )
    .expect("insert malformed sync backend kind preference");

    let status = load_sync_status_from_conn(&conn).expect("load sync status");
    assert_eq!(status.sync_backend_kind, None);
    assert_eq!(
        status.sync_backend_kind_effective,
        default_sync_backend_kind().to_string()
    );
    assert_eq!(
        status.sync_backend_kind_raw,
        Some("filesystem_bridge".to_string())
    );
    assert!(status.sync_backend_kind_malformed);
    assert_eq!(
        status.sync_backend_kind_malformed_reason,
        Some("invalid_json".to_string())
    );
}

#[test]
fn load_sync_status_from_conn_keeps_missing_sync_backend_kind_unconfigured() {
    let conn = setup_sync_test_conn();

    let status = load_sync_status_from_conn(&conn).expect("load sync status");
    assert_eq!(status.sync_backend_kind_raw, None);
    assert_eq!(status.sync_backend_kind, None);
    assert_eq!(
        status.sync_backend_kind_effective,
        default_sync_backend_kind().to_string()
    );
    assert!(!status.sync_backend_kind_malformed);
    assert_eq!(status.sync_backend_kind_malformed_reason, None);
}

#[test]
fn load_sync_status_from_conn_flags_invalid_filesystem_bridge_cursor_timestamp_as_malformed() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        params![
            SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LAST_PULL_CURSOR_KEY,
            r#"{"updated_at":"not-a-timestamp","device_id":"device-b","event_id":"evt-b"}"#,
        ],
    )
    .expect("insert invalid timestamp filesystem bridge cursor");

    let status = load_sync_status_from_conn(&conn).expect("load sync status");
    assert_eq!(
        status.filesystem_bridge_last_pull_cursor,
        Some(
            r#"{"updated_at":"not-a-timestamp","device_id":"device-b","event_id":"evt-b"}"#
                .to_string()
        )
    );
    assert!(status.filesystem_bridge_last_pull_cursor_malformed);
    assert_eq!(status.filesystem_bridge_last_pull_updated_at, None);
    assert_eq!(status.filesystem_bridge_last_pull_device_id, None);
    assert_eq!(status.filesystem_bridge_last_pull_event_id, None);
    assert_eq!(
        status.filesystem_bridge_last_pull_cursor_malformed_reason,
        Some("invalid_updated_at_hlc".to_string())
    );
}

#[test]
fn load_sync_status_from_conn_flags_non_hlc_filesystem_bridge_cursor_as_malformed() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        params![
            SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LAST_PULL_CURSOR_KEY,
            r#"{"updated_at":"2026-03-02T10:00:00.000001Z","device_id":"device-b","event_id":"evt-b"}"#,
        ],
    )
    .expect("insert non-hlc filesystem bridge cursor");

    let status = load_sync_status_from_conn(&conn).expect("load sync status");
    assert_eq!(
        status.filesystem_bridge_last_pull_cursor,
        Some(
            r#"{"updated_at":"2026-03-02T10:00:00.000001Z","device_id":"device-b","event_id":"evt-b"}"#
                .to_string()
        )
    );
    assert!(status.filesystem_bridge_last_pull_cursor_malformed);
    assert_eq!(status.filesystem_bridge_last_pull_updated_at, None);
    assert_eq!(status.filesystem_bridge_last_pull_device_id, None);
    assert_eq!(status.filesystem_bridge_last_pull_event_id, None);
    assert_eq!(
        status.filesystem_bridge_last_pull_cursor_malformed_reason,
        Some("invalid_updated_at_hlc".to_string())
    );
}

#[test]
fn load_sync_status_from_conn_flags_empty_filesystem_bridge_cursor_device_id_as_malformed() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        params![
            SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LAST_PULL_CURSOR_KEY,
            r#"{"updated_at":"0001743573600000_0001_6465766963656131","device_id":"   ","event_id":"evt-b"}"#,
        ],
    )
    .expect("insert empty device_id filesystem bridge cursor");

    let status = load_sync_status_from_conn(&conn).expect("load sync status");
    assert_eq!(
        status.filesystem_bridge_last_pull_cursor,
        Some(
            r#"{"updated_at":"0001743573600000_0001_6465766963656131","device_id":"   ","event_id":"evt-b"}"#
                .to_string()
        )
    );
    assert!(status.filesystem_bridge_last_pull_cursor_malformed);
    assert_eq!(status.filesystem_bridge_last_pull_updated_at, None);
    assert_eq!(status.filesystem_bridge_last_pull_device_id, None);
    assert_eq!(status.filesystem_bridge_last_pull_event_id, None);
    assert_eq!(
        status.filesystem_bridge_last_pull_cursor_malformed_reason,
        Some("empty_device_id".to_string())
    );
}
