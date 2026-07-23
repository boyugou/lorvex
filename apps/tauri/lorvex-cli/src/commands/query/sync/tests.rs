use super::*;

#[test]
fn sync_status_uses_shared_snapshot_without_dropping_malformed_diagnostics() {
    let conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES
         ('last_success_at', 'not-a-date'),
         ('last_pull_at', 'also-not-a-date'),
         ('filesystem_bridge_last_pull_cursor', '{')",
        [],
    )
    .expect("insert malformed checkpoint values");

    let status = get_sync_status_with_conn(&conn).expect("load sync status");

    assert!(status.last_success_at_malformed);
    assert_eq!(
        status.last_success_at_malformed_reason,
        Some("invalid_rfc3339".to_string())
    );
    assert!(status.last_pull_at_malformed);
    assert!(status.filesystem_bridge_last_pull_cursor_malformed);
    assert_eq!(
        status.filesystem_bridge_last_pull_cursor_malformed_reason,
        Some("invalid_json".to_string())
    );
}
