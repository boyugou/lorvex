use super::*;

#[test]
fn load_sync_status_from_conn_flags_malformed_last_sync_timestamps() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        params!["last_success_at", "nope-success"],
    )
    .expect("insert malformed last_success_at");
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        params!["last_pull_at", "nope-pull"],
    )
    .expect("insert malformed last_pull_at");

    let status = load_sync_status_from_conn(&conn).expect("load sync status");
    assert_eq!(status.last_success_at, None);
    assert_eq!(status.last_pull_at, None);
    assert!(!status.last_synced_at_malformed);
    assert!(status.last_success_at_malformed);
    assert!(status.last_pull_at_malformed);
    assert_eq!(
        status.last_success_at_malformed_reason,
        Some("invalid_rfc3339".to_string())
    );
    assert_eq!(
        status.last_pull_at_malformed_reason,
        Some("invalid_rfc3339".to_string())
    );
}

#[test]
fn load_sync_status_from_conn_flags_malformed_last_synced_at() {
    let conn = setup_sync_test_conn();
    insert_sync_event_row(
        &conn,
        "event-synced-malformed",
        "task",
        "task-synced-malformed",
        "upsert",
        json!({
            "id": "task-synced-malformed",
            "title": "Synced malformed timestamp task",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T12:00:00Z",
        "device-a",
        Some("not-a-synced-timestamp"),
    );

    let status = load_sync_status_from_conn(&conn).expect("load sync status");
    assert_eq!(status.last_synced_at, None);
    assert!(status.last_synced_at_malformed);
    assert_eq!(
        status.last_synced_at_malformed_reason,
        Some("invalid_rfc3339".to_string())
    );
    assert!(!status.last_success_at_malformed);
    assert!(!status.last_pull_at_malformed);
}

#[test]
fn load_sync_status_from_conn_trims_valid_timestamp_state() {
    let conn = setup_sync_test_conn();
    insert_sync_event_row(
        &conn,
        "event-synced-trimmed",
        "task",
        "task-synced-trimmed",
        "upsert",
        json!({
            "id": "task-synced-trimmed",
            "title": "Synced trimmed timestamp task",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T12:00:00Z",
        "device-a",
        Some(" 2026-03-02T11:00:00Z "),
    );
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        params!["last_success_at", " 2026-03-02T10:00:00Z "],
    )
    .expect("insert spaced last_success_at");
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        params!["last_pull_at", " 2026-03-02T09:00:00Z "],
    )
    .expect("insert spaced last_pull_at");
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        params![
            "filesystem_bridge_lookback_known_id_skipped_last_run_at",
            " 2026-03-05T02:20:00Z "
        ],
    )
    .expect("insert spaced lookback timestamp");

    let status = load_sync_status_from_conn(&conn).expect("load sync status");

    assert_eq!(
        status.last_synced_at,
        Some("2026-03-02T11:00:00Z".to_string())
    );
    assert_eq!(
        status.last_success_at,
        Some("2026-03-02T10:00:00Z".to_string())
    );
    assert_eq!(
        status.last_pull_at,
        Some("2026-03-02T09:00:00Z".to_string())
    );
    assert_eq!(
        status.filesystem_bridge_lookback_known_id_skipped_last_run_at,
        Some("2026-03-05T02:20:00Z".to_string())
    );
    assert!(!status.last_synced_at_malformed);
    assert!(!status.last_success_at_malformed);
    assert!(!status.last_pull_at_malformed);
    assert!(!status.filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed);
    assert_eq!(status.last_synced_at_malformed_reason, None);
    assert_eq!(status.last_success_at_malformed_reason, None);
    assert_eq!(status.last_pull_at_malformed_reason, None);
    assert_eq!(
        status.filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed_reason,
        None
    );
}
