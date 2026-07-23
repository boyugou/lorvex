use super::*;

#[test]
fn load_sync_status_from_conn_surfaces_tombstone_and_conflict_retention_state() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES ('reseed_required', 'true')",
        [],
    )
    .expect("insert reseed checkpoint");
    conn.execute(
        "INSERT INTO sync_tombstones (
            entity_type, entity_id, version, deleted_at, redirect_entity_id, redirect_entity_type
         ) VALUES ('task', 'task-a', '0000000000000_0000_a0a0a0a0a0a0a0a0', ?1, NULL, NULL)",
        params!["2026-03-01T08:00:00Z"],
    )
    .expect("insert oldest tombstone");
    conn.execute(
        "INSERT INTO sync_tombstones (
            entity_type, entity_id, version, deleted_at, redirect_entity_id, redirect_entity_type
         ) VALUES ('task', 'task-b', '0000000000000_0000_7465737430303031', ?1, NULL, NULL)",
        params!["2026-03-02T09:30:00Z"],
    )
    .expect("insert newest tombstone");
    conn.execute(
        "INSERT INTO sync_conflict_log (
            entity_type, entity_id, winner_version, loser_version,
            loser_device_id, loser_payload, resolved_at, resolution_type
         ) VALUES ('task', 'task-a', '0000000000000_0000_a0a0a0a0a0a0a0a0', '0000000000000_0000_a0a0a0a0a0a0a0a0', 'device-a', NULL, ?1, 'lww')",
        params!["2026-03-03T10:15:00Z"],
    )
    .expect("insert older conflict");
    conn.execute(
        "INSERT INTO sync_conflict_log (
            entity_type, entity_id, winner_version, loser_version,
            loser_device_id, loser_payload, resolved_at, resolution_type
         ) VALUES ('task', 'task-b', '0000000000000_0000_a0a0a0a0a0a0a0a0', '0000000000000_0000_a0a0a0a0a0a0a0a0', 'device-b', NULL, ?1, 'fk_unresolved')",
        params!["2026-03-04T11:45:00Z"],
    )
    .expect("insert newer conflict");

    let status = load_sync_status_from_conn(&conn).expect("load sync status");
    assert_eq!(status.tombstone_count, 2);
    assert_eq!(
        status.tombstone_oldest_deleted_at,
        Some("2026-03-01T08:00:00Z".to_string())
    );
    assert!(!status.tombstone_oldest_deleted_at_malformed);
    assert_eq!(status.tombstone_oldest_deleted_at_malformed_reason, None);
    assert_eq!(
        status.tombstone_newest_deleted_at,
        Some("2026-03-02T09:30:00Z".to_string())
    );
    assert!(!status.tombstone_newest_deleted_at_malformed);
    assert_eq!(status.tombstone_newest_deleted_at_malformed_reason, None);
    assert_eq!(status.conflict_log_count, 2);
    assert_eq!(
        status.conflict_log_last_resolved_at,
        Some("2026-03-04T11:45:00Z".to_string())
    );
    assert!(!status.conflict_log_last_resolved_at_malformed);
    assert_eq!(status.conflict_log_last_resolved_at_malformed_reason, None);
    assert!(status.reseed_required);
    assert!(!status.reseed_required_malformed);
    assert_eq!(status.reseed_required_malformed_reason, None);
}

#[test]
fn load_sync_status_from_conn_flags_malformed_tombstone_and_conflict_timestamps() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_tombstones (
            entity_type, entity_id, version, deleted_at, redirect_entity_id, redirect_entity_type
         ) VALUES ('task', 'task-a', '0000000000000_0000_a0a0a0a0a0a0a0a0', 'not-a-timestamp', NULL, NULL)",
        [],
    )
    .expect("insert malformed tombstone");
    conn.execute(
        "INSERT INTO sync_conflict_log (
            entity_type, entity_id, winner_version, loser_version,
            loser_device_id, loser_payload, resolved_at, resolution_type
         ) VALUES ('task', 'task-a', '0000000000000_0000_a0a0a0a0a0a0a0a0', '0000000000000_0000_a0a0a0a0a0a0a0a0', 'device-a', NULL, 'not-a-timestamp', 'lww')",
        [],
    )
    .expect("insert malformed conflict");

    let status = load_sync_status_from_conn(&conn).expect("load sync status");
    assert_eq!(status.tombstone_count, 1);
    assert_eq!(status.tombstone_oldest_deleted_at, None);
    assert!(status.tombstone_oldest_deleted_at_malformed);
    assert_eq!(
        status.tombstone_oldest_deleted_at_malformed_reason,
        Some("invalid_rfc3339".to_string())
    );
    assert_eq!(status.tombstone_newest_deleted_at, None);
    assert!(status.tombstone_newest_deleted_at_malformed);
    assert_eq!(
        status.tombstone_newest_deleted_at_malformed_reason,
        Some("invalid_rfc3339".to_string())
    );
    assert_eq!(status.conflict_log_count, 1);
    assert_eq!(status.conflict_log_last_resolved_at, None);
    assert!(status.conflict_log_last_resolved_at_malformed);
    assert_eq!(
        status.conflict_log_last_resolved_at_malformed_reason,
        Some("invalid_rfc3339".to_string())
    );
}

#[test]
fn load_sync_status_from_conn_flags_malformed_reseed_checkpoint_state() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES ('reseed_required', 'bogus')",
        [],
    )
    .expect("insert malformed reseed checkpoint");

    let status = load_sync_status_from_conn(&conn).expect("load sync status");
    assert!(!status.reseed_required);
    assert!(status.reseed_required_malformed);
    assert_eq!(
        status.reseed_required_malformed_reason,
        Some("invalid_bool".to_string())
    );
}

#[test]
fn load_sync_status_from_conn_rejects_non_canonical_reseed_checkpoint_true_values() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES ('reseed_required', 'TRUE')",
        [],
    )
    .expect("insert uppercase reseed checkpoint");

    let status = load_sync_status_from_conn(&conn).expect("load sync status");
    assert!(!status.reseed_required);
    assert!(status.reseed_required_malformed);
    assert_eq!(
        status.reseed_required_malformed_reason,
        Some("invalid_bool".to_string())
    );
}

#[test]
fn load_sync_status_from_conn_uses_valid_retention_timestamps_even_when_bad_rows_exist() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_tombstones (
            entity_type, entity_id, version, deleted_at, redirect_entity_id, redirect_entity_type
         ) VALUES ('task', 'task-a', '0000000000000_0000_a0a0a0a0a0a0a0a0', 'not-a-timestamp', NULL, NULL)",
        [],
    )
    .expect("insert malformed tombstone");
    conn.execute(
        "INSERT INTO sync_tombstones (
            entity_type, entity_id, version, deleted_at, redirect_entity_id, redirect_entity_type
         ) VALUES ('task', 'task-b', '0000000000000_0000_7465737430303031', ?1, NULL, NULL)",
        params!["2026-03-05T12:00:00Z"],
    )
    .expect("insert valid tombstone");
    conn.execute(
        "INSERT INTO sync_conflict_log (
            entity_type, entity_id, winner_version, loser_version,
            loser_device_id, loser_payload, resolved_at, resolution_type
         ) VALUES ('task', 'task-a', '0000000000000_0000_a0a0a0a0a0a0a0a0', '0000000000000_0000_a0a0a0a0a0a0a0a0', 'device-a', NULL, 'not-a-timestamp', 'lww')",
        [],
    )
    .expect("insert malformed conflict");
    conn.execute(
        "INSERT INTO sync_conflict_log (
            entity_type, entity_id, winner_version, loser_version,
            loser_device_id, loser_payload, resolved_at, resolution_type
         ) VALUES ('task', 'task-b', '0000000000000_0000_a0a0a0a0a0a0a0a0', '0000000000000_0000_a0a0a0a0a0a0a0a0', 'device-b', NULL, ?1, 'fk_unresolved')",
        params!["2026-03-06T13:30:00Z"],
    )
    .expect("insert valid conflict");

    let status = load_sync_status_from_conn(&conn).expect("load sync status");
    assert_eq!(status.tombstone_count, 2);
    assert_eq!(
        status.tombstone_oldest_deleted_at,
        Some("2026-03-05T12:00:00Z".to_string())
    );
    assert_eq!(
        status.tombstone_newest_deleted_at,
        Some("2026-03-05T12:00:00Z".to_string())
    );
    assert!(status.tombstone_oldest_deleted_at_malformed);
    assert!(status.tombstone_newest_deleted_at_malformed);
    assert_eq!(status.conflict_log_count, 2);
    assert_eq!(
        status.conflict_log_last_resolved_at,
        Some("2026-03-06T13:30:00Z".to_string())
    );
    assert!(status.conflict_log_last_resolved_at_malformed);
}
