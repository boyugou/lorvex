use super::*;

#[test]
fn load_sync_status_from_conn_surfaces_lookback_known_id_skip_metric() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        params!["filesystem_bridge_lookback_known_id_skipped_last_run", "7"],
    )
    .expect("insert lookback known-id skipped metric");
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        params![
            "filesystem_bridge_lookback_known_id_skipped_last_run_at",
            "2026-03-05T02:20:00Z"
        ],
    )
    .expect("insert lookback known-id skipped timestamp");

    let status = load_sync_status_from_conn(&conn).expect("load sync status");
    assert_eq!(
        status.filesystem_bridge_lookback_known_id_skipped_last_run,
        7
    );
    assert!(!status.filesystem_bridge_lookback_known_id_skipped_last_run_malformed);
    assert_eq!(
        status.filesystem_bridge_lookback_known_id_skipped_last_run_at,
        Some("2026-03-05T02:20:00Z".to_string())
    );
    assert!(!status.filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed);
    assert_eq!(
        status.filesystem_bridge_lookback_known_id_skipped_last_run_malformed_reason,
        None
    );
    assert_eq!(
        status.filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed_reason,
        None
    );
    assert!(!status.last_synced_at_malformed);
    assert!(!status.last_success_at_malformed);
    assert!(!status.last_pull_at_malformed);
}

#[test]
fn load_sync_status_from_conn_flags_malformed_lookback_known_id_skip_metric() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        params![
            "filesystem_bridge_lookback_known_id_skipped_last_run",
            "oops"
        ],
    )
    .expect("insert malformed lookback known-id skipped metric");

    let status = load_sync_status_from_conn(&conn).expect("load sync status");
    assert_eq!(
        status.filesystem_bridge_lookback_known_id_skipped_last_run,
        0
    );
    assert!(status.filesystem_bridge_lookback_known_id_skipped_last_run_malformed);
    assert_eq!(
        status.filesystem_bridge_lookback_known_id_skipped_last_run_malformed_reason,
        Some("invalid_i64".to_string())
    );
    assert_eq!(
        status.filesystem_bridge_lookback_known_id_skipped_last_run_at,
        None
    );
    assert!(!status.filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed);
    assert!(!status.last_synced_at_malformed);
    assert!(!status.last_success_at_malformed);
    assert!(!status.last_pull_at_malformed);
}

#[test]
fn load_sync_status_from_conn_flags_malformed_lookback_known_id_skip_timestamp() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        params![
            "filesystem_bridge_lookback_known_id_skipped_last_run_at",
            "not-a-timestamp"
        ],
    )
    .expect("insert malformed lookback known-id skipped timestamp");

    let status = load_sync_status_from_conn(&conn).expect("load sync status");
    assert_eq!(
        status.filesystem_bridge_lookback_known_id_skipped_last_run_at,
        None
    );
    assert!(status.filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed);
    assert_eq!(
        status.filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed_reason,
        Some("invalid_rfc3339".to_string())
    );
    assert!(!status.last_synced_at_malformed);
    assert!(!status.last_success_at_malformed);
    assert!(!status.last_pull_at_malformed);
}
