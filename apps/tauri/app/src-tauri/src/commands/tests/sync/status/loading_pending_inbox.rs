use super::*;

#[test]
fn load_sync_status_from_conn_surfaces_pending_inbox_depth_and_oldest_attempt() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_pending_inbox (
            envelope, reason, missing_entity_type, missing_entity_id,
            envelope_entity_type, envelope_entity_id, envelope_version,
            first_attempted_at, last_attempted_at, attempt_count
         ) VALUES (?1, 'fk_unresolved', 'list', 'list-a',
                  'task', 'task-a', '0000000000000_0000_a0a0a0a0a0a0a0a0',
                  ?2, ?2, 1)",
        params![
            "{\"entity_type\":\"task\",\"entity_id\":\"task-a\",\"operation\":\"upsert\",\"version\":\"0000000000000_0000_a0a0a0a0a0a0a0a0\",\"payload_schema_version\":1,\"payload\":\"{}\",\"device_id\":\"device-a\"}",
            "2026-03-01T08:00:00Z",
        ],
    )
    .expect("insert oldest pending inbox row");
    conn.execute(
        "INSERT INTO sync_pending_inbox (
            envelope, reason, missing_entity_type, missing_entity_id,
            envelope_entity_type, envelope_entity_id, envelope_version,
            first_attempted_at, last_attempted_at, attempt_count
         ) VALUES (?1, 'fk_unresolved', 'list', 'list-b',
                  'task', 'task-b', '0000000000000_0000_7465737430303031',
                  ?2, ?2, 2)",
        params![
            "{\"entity_type\":\"task\",\"entity_id\":\"task-b\",\"operation\":\"upsert\",\"version\":\"0000000000000_0000_7465737430303031\",\"payload_schema_version\":1,\"payload\":\"{}\",\"device_id\":\"device-b\"}",
            "2026-03-02T09:30:00Z",
        ],
    )
    .expect("insert newer pending inbox row");

    let status = load_sync_status_from_conn(&conn).expect("load sync status");
    assert_eq!(status.pending_inbox_count, 2);
    assert_eq!(
        status.pending_inbox_oldest_at,
        Some("2026-03-01T08:00:00Z".to_string())
    );
    assert!(!status.pending_inbox_oldest_at_malformed);
    assert_eq!(status.pending_inbox_oldest_at_malformed_reason, None);
}

#[test]
fn load_sync_status_from_conn_flags_malformed_pending_inbox_oldest_attempt() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_pending_inbox (
            envelope, reason, missing_entity_type, missing_entity_id,
            envelope_entity_type, envelope_entity_id, envelope_version,
            first_attempted_at, last_attempted_at, attempt_count
         ) VALUES (?1, 'fk_unresolved', 'list', 'list-a',
                  'task', 'task-a', '0000000000000_0000_a0a0a0a0a0a0a0a0',
                  'not-a-timestamp', 'not-a-timestamp', 1)",
        params![
            "{\"entity_type\":\"task\",\"entity_id\":\"task-a\",\"operation\":\"upsert\",\"version\":\"0000000000000_0000_a0a0a0a0a0a0a0a0\",\"payload_schema_version\":1,\"payload\":\"{}\",\"device_id\":\"device-a\"}",
        ],
    )
    .expect("insert malformed pending inbox row");

    let status = load_sync_status_from_conn(&conn).expect("load sync status");
    assert_eq!(status.pending_inbox_count, 1);
    assert_eq!(status.pending_inbox_oldest_at, None);
    assert!(status.pending_inbox_oldest_at_malformed);
    assert_eq!(
        status.pending_inbox_oldest_at_malformed_reason,
        Some("invalid_rfc3339".to_string())
    );
}

#[test]
fn load_sync_status_from_conn_keeps_valid_pending_inbox_oldest_attempt_when_bad_rows_exist() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_pending_inbox (
            envelope, reason, missing_entity_type, missing_entity_id,
            envelope_entity_type, envelope_entity_id, envelope_version,
            first_attempted_at, last_attempted_at, attempt_count
         ) VALUES (?1, 'fk_unresolved', 'list', 'list-a',
                  'task', 'task-a', '0000000000000_0000_a0a0a0a0a0a0a0a0',
                  '000-bad', '000-bad', 1)",
        params![
            "{\"entity_type\":\"task\",\"entity_id\":\"task-a\",\"operation\":\"upsert\",\"version\":\"0000000000000_0000_a0a0a0a0a0a0a0a0\",\"payload_schema_version\":1,\"payload\":\"{}\",\"device_id\":\"device-a\"}",
        ],
    )
    .expect("insert malformed pending inbox row");
    conn.execute(
        "INSERT INTO sync_pending_inbox (
            envelope, reason, missing_entity_type, missing_entity_id,
            envelope_entity_type, envelope_entity_id, envelope_version,
            first_attempted_at, last_attempted_at, attempt_count
         ) VALUES (?1, 'fk_unresolved', 'list', 'list-b',
                  'task', 'task-b', '0000000000000_0000_7465737430303031',
                  ?2, ?2, 2)",
        params![
            "{\"entity_type\":\"task\",\"entity_id\":\"task-b\",\"operation\":\"upsert\",\"version\":\"0000000000000_0000_7465737430303031\",\"payload_schema_version\":1,\"payload\":\"{}\",\"device_id\":\"device-b\"}",
            "2026-03-05T12:00:00Z",
        ],
    )
    .expect("insert valid pending inbox row");

    let status = load_sync_status_from_conn(&conn).expect("load sync status");
    assert_eq!(status.pending_inbox_count, 2);
    assert_eq!(
        status.pending_inbox_oldest_at,
        Some("2026-03-05T12:00:00Z".to_string())
    );
    assert!(status.pending_inbox_oldest_at_malformed);
    assert_eq!(
        status.pending_inbox_oldest_at_malformed_reason,
        Some("invalid_rfc3339".to_string())
    );
}
