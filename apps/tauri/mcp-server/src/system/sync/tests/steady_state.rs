use super::shared::setup_sync_status_test_conn;
use crate::system::sync::get_sync_status;
use serde_json::Value;

#[test]
#[serial_test::serial(hlc)]
fn get_sync_status_returns_default_apply_cycle_fields() {
    let conn = setup_sync_status_test_conn();

    let status = serde_json::from_str::<Value>(&get_sync_status(&conn).expect("get sync status"))
        .expect("status json");

    assert_eq!(
        status.get("apply_cycle_count").and_then(Value::as_i64),
        Some(0)
    );
    assert_eq!(
        status
            .get("apply_cycle_last_started_at")
            .and_then(Value::as_str),
        None
    );
    assert_eq!(
        status
            .get("apply_cycle_last_completed_at")
            .and_then(Value::as_str),
        None
    );
    assert_eq!(
        status
            .get("apply_cycle_last_duration_ms")
            .and_then(Value::as_i64),
        None
    );
    assert_eq!(
        status
            .get("apply_cycle_last_received")
            .and_then(Value::as_i64),
        Some(0)
    );
    assert_eq!(
        status
            .get("apply_cycle_last_skipped_deferred")
            .and_then(Value::as_i64),
        Some(0)
    );
    assert_eq!(
        status.get("apply_cycle_last_error").and_then(Value::as_str),
        None
    );
    assert_eq!(
        status
            .get("apply_cycles_retained_received")
            .and_then(Value::as_i64),
        Some(0)
    );
    assert_eq!(
        status
            .get("apply_cycles_retained_skipped_stale")
            .and_then(Value::as_i64),
        Some(0)
    );
}

#[test]
#[serial_test::serial(hlc)]
fn get_sync_status_surfaces_pending_inbox_depth_and_oldest_attempt() {
    let conn = setup_sync_status_test_conn();
    conn.execute(
        "INSERT INTO sync_pending_inbox (
            envelope, reason, missing_entity_type, missing_entity_id,
            first_attempted_at, last_attempted_at, attempt_count
         ) VALUES (?1, 'fk_unresolved', 'list', 'list-a', ?2, ?2, 1)",
        rusqlite::params![
            "{\"entity_type\":\"task\",\"entity_id\":\"task-a\",\"operation\":\"upsert\",\"version\":\"0000000000000_0000_a0a0a0a0a0a0a0a0\",\"payload_schema_version\":1,\"payload\":\"{}\",\"device_id\":\"device-a\"}",
            "2026-03-01T08:00:00Z",
        ],
    )
    .expect("insert oldest pending inbox row");
    conn.execute(
        "INSERT INTO sync_pending_inbox (
            envelope, reason, missing_entity_type, missing_entity_id,
            first_attempted_at, last_attempted_at, attempt_count
         ) VALUES (?1, 'fk_unresolved', 'list', 'list-b', ?2, ?2, 2)",
        rusqlite::params![
            "{\"entity_type\":\"task\",\"entity_id\":\"task-b\",\"operation\":\"upsert\",\"version\":\"0000000000000_0000_test0001\",\"payload_schema_version\":1,\"payload\":\"{}\",\"device_id\":\"device-b\"}",
            "2026-03-02T09:30:00Z",
        ],
    )
    .expect("insert newer pending inbox row");

    let status = serde_json::from_str::<Value>(&get_sync_status(&conn).expect("get sync status"))
        .expect("parse sync status");

    assert_eq!(
        status.get("pending_inbox_count").and_then(Value::as_i64),
        Some(2)
    );
    assert_eq!(
        status
            .get("pending_inbox_oldest_at")
            .and_then(Value::as_str),
        Some("2026-03-01T08:00:00Z")
    );
    assert_eq!(
        status
            .get("pending_inbox_oldest_at_malformed")
            .and_then(Value::as_bool),
        Some(false)
    );
    assert!(status
        .get("pending_inbox_oldest_at_malformed_reason")
        .unwrap()
        .is_null());
}

#[test]
#[serial_test::serial(hlc)]
fn get_sync_status_keeps_valid_pending_inbox_oldest_attempt_when_bad_rows_exist() {
    let conn = setup_sync_status_test_conn();
    conn.execute(
        "INSERT INTO sync_pending_inbox (
            envelope, reason, missing_entity_type, missing_entity_id,
            first_attempted_at, last_attempted_at, attempt_count
         ) VALUES (?1, 'fk_unresolved', 'list', 'list-a', '000-bad', '000-bad', 1)",
        rusqlite::params![
            "{\"entity_type\":\"task\",\"entity_id\":\"task-a\",\"operation\":\"upsert\",\"version\":\"0000000000000_0000_a0a0a0a0a0a0a0a0\",\"payload_schema_version\":1,\"payload\":\"{}\",\"device_id\":\"device-a\"}",
        ],
    )
    .expect("insert malformed pending inbox row");
    conn.execute(
        "INSERT INTO sync_pending_inbox (
            envelope, reason, missing_entity_type, missing_entity_id,
            first_attempted_at, last_attempted_at, attempt_count
         ) VALUES (?1, 'fk_unresolved', 'list', 'list-b', ?2, ?2, 2)",
        rusqlite::params![
            "{\"entity_type\":\"task\",\"entity_id\":\"task-b\",\"operation\":\"upsert\",\"version\":\"0000000000000_0000_test0001\",\"payload_schema_version\":1,\"payload\":\"{}\",\"device_id\":\"device-b\"}",
            "2026-03-05T12:00:00Z",
        ],
    )
    .expect("insert valid pending inbox row");

    let status = serde_json::from_str::<Value>(&get_sync_status(&conn).expect("get sync status"))
        .expect("parse sync status");

    assert_eq!(
        status.get("pending_inbox_count").and_then(Value::as_i64),
        Some(2)
    );
    assert_eq!(
        status
            .get("pending_inbox_oldest_at")
            .and_then(Value::as_str),
        Some("2026-03-05T12:00:00Z")
    );
    assert_eq!(
        status
            .get("pending_inbox_oldest_at_malformed")
            .and_then(Value::as_bool),
        Some(true)
    );
    assert_eq!(
        status
            .get("pending_inbox_oldest_at_malformed_reason")
            .and_then(Value::as_str),
        Some("invalid_rfc3339")
    );
}

#[test]
#[serial_test::serial(hlc)]
fn get_sync_status_surfaces_tombstone_conflict_and_reseed_state() {
    let conn = setup_sync_status_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES ('reseed_required', 'true')",
        [],
    )
    .expect("insert reseed checkpoint");
    conn.execute(
        "INSERT INTO sync_tombstones (
            entity_type, entity_id, version, deleted_at, redirect_entity_id, redirect_entity_type
         ) VALUES ('task', 'task-a', '0000000000000_0000_a0a0a0a0a0a0a0a0', ?1, NULL, NULL)",
        rusqlite::params!["2026-03-01T08:00:00Z"],
    )
    .expect("insert oldest tombstone");
    conn.execute(
        "INSERT INTO sync_tombstones (
            entity_type, entity_id, version, deleted_at, redirect_entity_id, redirect_entity_type
         ) VALUES ('task', 'task-b', '0000000000000_0000_test0001', ?1, NULL, NULL)",
        rusqlite::params!["2026-03-02T09:30:00Z"],
    )
    .expect("insert newest tombstone");
    conn.execute(
        "INSERT INTO sync_conflict_log (
            entity_type, entity_id, winner_version, loser_version,
            loser_device_id, loser_payload, resolved_at, resolution_type
         ) VALUES ('task', 'task-a', '0000000000000_0000_test0002', '0000000000000_0000_test0001', 'device-a', NULL, ?1, 'lww')",
        rusqlite::params!["2026-03-03T10:15:00Z"],
    )
    .expect("insert older conflict");
    conn.execute(
        "INSERT INTO sync_conflict_log (
            entity_type, entity_id, winner_version, loser_version,
            loser_device_id, loser_payload, resolved_at, resolution_type
         ) VALUES ('task', 'task-b', '0000000000000_0000_test0004', '0000000000000_0000_test0003', 'device-b', NULL, ?1, 'fk_unresolved')",
        rusqlite::params!["2026-03-04T11:45:00Z"],
    )
    .expect("insert newer conflict");

    let status = serde_json::from_str::<Value>(&get_sync_status(&conn).expect("get sync status"))
        .expect("parse sync status");

    assert_eq!(
        status.get("tombstone_count").and_then(Value::as_i64),
        Some(2)
    );
    assert_eq!(
        status
            .get("tombstone_oldest_deleted_at")
            .and_then(Value::as_str),
        Some("2026-03-01T08:00:00Z")
    );
    assert_eq!(
        status
            .get("tombstone_newest_deleted_at")
            .and_then(Value::as_str),
        Some("2026-03-02T09:30:00Z")
    );
    assert_eq!(
        status.get("conflict_log_count").and_then(Value::as_i64),
        Some(2)
    );
    assert_eq!(
        status
            .get("conflict_log_last_resolved_at")
            .and_then(Value::as_str),
        Some("2026-03-04T11:45:00Z")
    );
    assert_eq!(
        status.get("reseed_required").and_then(Value::as_bool),
        Some(true)
    );
    assert_eq!(
        status
            .get("reseed_required_malformed")
            .and_then(Value::as_bool),
        Some(false)
    );
    assert!(status
        .get("reseed_required_malformed_reason")
        .unwrap()
        .is_null());
}

#[test]
#[serial_test::serial(hlc)]
fn get_sync_status_flags_malformed_pending_retention_and_reseed_state() {
    let conn = setup_sync_status_test_conn();
    conn.execute(
        "INSERT INTO sync_pending_inbox (
            envelope, reason, missing_entity_type, missing_entity_id,
            first_attempted_at, last_attempted_at, attempt_count
         ) VALUES (?1, 'fk_unresolved', 'list', 'list-a', 'not-a-timestamp', 'not-a-timestamp', 1)",
        rusqlite::params![
            "{\"entity_type\":\"task\",\"entity_id\":\"task-a\",\"operation\":\"upsert\",\"version\":\"0000000000000_0000_a0a0a0a0a0a0a0a0\",\"payload_schema_version\":1,\"payload\":\"{}\",\"device_id\":\"device-a\"}",
        ],
    )
    .expect("insert malformed pending inbox row");
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
         ) VALUES ('task', 'task-a', '0000000000000_0000_test0002', '0000000000000_0000_test0001', 'device-a', NULL, 'not-a-timestamp', 'lww')",
        [],
    )
    .expect("insert malformed conflict");
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES ('reseed_required', 'TRUE')",
        [],
    )
    .expect("insert malformed reseed checkpoint");

    let status = serde_json::from_str::<Value>(&get_sync_status(&conn).expect("get sync status"))
        .expect("parse sync status");

    assert_eq!(
        status
            .get("pending_inbox_oldest_at_malformed_reason")
            .and_then(Value::as_str),
        Some("invalid_rfc3339")
    );
    assert_eq!(
        status
            .get("tombstone_oldest_deleted_at_malformed_reason")
            .and_then(Value::as_str),
        Some("invalid_rfc3339")
    );
    assert_eq!(
        status
            .get("tombstone_newest_deleted_at_malformed_reason")
            .and_then(Value::as_str),
        Some("invalid_rfc3339")
    );
    assert_eq!(
        status
            .get("conflict_log_last_resolved_at_malformed_reason")
            .and_then(Value::as_str),
        Some("invalid_rfc3339")
    );
    assert_eq!(
        status.get("reseed_required").and_then(Value::as_bool),
        Some(false)
    );
    assert_eq!(
        status
            .get("reseed_required_malformed_reason")
            .and_then(Value::as_str),
        Some("invalid_bool")
    );
}

fn insert_calendar_subscription(conn: &rusqlite::Connection, id: &str, enabled: bool) {
    conn.execute(
        "INSERT INTO calendar_subscriptions (
            id, name, url, color, enabled, version, created_at, updated_at
         ) VALUES (?1, ?2, ?3, NULL, ?4, ?5, ?6, ?6)",
        rusqlite::params![
            id,
            format!("Subscription {id}"),
            format!("https://example.com/{id}.ics"),
            i64::from(enabled),
            format!("0000000000000_0000_{id}"),
            "2026-03-01T08:00:00Z",
        ],
    )
    .expect("insert calendar subscription");
}

fn insert_subscription_runtime_state(
    conn: &rusqlite::Connection,
    scope: &str,
    availability_state: &str,
    last_refresh_result: Option<&str>,
    last_refresh_success_at: Option<&str>,
) {
    conn.execute(
        "INSERT INTO provider_scope_runtime_state (
            provider_kind, provider_scope, enabled, availability_state,
            last_refresh_result, last_refresh_attempt_at, last_refresh_success_at
         ) VALUES ('ical_subscription', ?1, 1, ?2, ?3, '2026-03-01T09:00:00Z', ?4)",
        rusqlite::params![
            scope,
            availability_state,
            last_refresh_result,
            last_refresh_success_at
        ],
    )
    .expect("insert ical runtime state");
}

#[test]
#[serial_test::serial(hlc)]
fn get_sync_status_surfaces_ical_subscription_health() {
    let conn = setup_sync_status_test_conn();
    insert_calendar_subscription(&conn, "sub-healthy", true);
    insert_calendar_subscription(&conn, "sub-disabled", false);
    insert_calendar_subscription(&conn, "sub-parse-error", true);
    insert_calendar_subscription(&conn, "sub-rate-limited", true);
    insert_calendar_subscription(&conn, "sub-never-refreshed", true);
    insert_calendar_subscription(&conn, "sub-never-refreshed-runtime", true);
    insert_calendar_subscription(&conn, "sub-stale", true);

    let fresh_success = lorvex_domain::sync_timestamp_now();
    insert_subscription_runtime_state(
        &conn,
        "sub-healthy",
        "enabled",
        Some("success"),
        Some(&fresh_success),
    );
    insert_subscription_runtime_state(
        &conn,
        "sub-disabled",
        "fetch_error",
        Some("fetch_error"),
        None,
    );
    insert_subscription_runtime_state(
        &conn,
        "sub-parse-error",
        "parse_error",
        Some("parse_error"),
        None,
    );
    insert_subscription_runtime_state(
        &conn,
        "sub-rate-limited",
        "enabled",
        Some("fetch_error"),
        Some(&fresh_success),
    );
    insert_subscription_runtime_state(&conn, "sub-never-refreshed-runtime", "enabled", None, None);
    insert_subscription_runtime_state(
        &conn,
        "sub-stale",
        "enabled",
        Some("success"),
        Some("2000-01-01T00:00:00.000Z"),
    );

    let status = serde_json::from_str::<Value>(&get_sync_status(&conn).expect("get sync status"))
        .expect("parse sync status");

    assert_eq!(
        status
            .get("ical_subscription_total_count")
            .and_then(Value::as_i64),
        Some(7)
    );
    assert_eq!(
        status
            .get("ical_subscription_failing_count")
            .and_then(Value::as_i64),
        Some(2)
    );
    assert_eq!(
        status
            .get("ical_subscription_never_refreshed_count")
            .and_then(Value::as_i64),
        Some(2)
    );
    assert_eq!(
        status
            .get("ical_subscription_stale_count")
            .and_then(Value::as_i64),
        Some(1)
    );
}

#[test]
#[serial_test::serial(hlc)]
fn get_sync_status_treats_missing_ical_runtime_rows_as_non_failing() {
    let conn = setup_sync_status_test_conn();
    insert_calendar_subscription(&conn, "sub-no-runtime", true);
    insert_calendar_subscription(&conn, "sub-failing", true);

    insert_subscription_runtime_state(
        &conn,
        "sub-failing",
        "fetch_error",
        Some("fetch_error"),
        None,
    );

    let status = serde_json::from_str::<Value>(&get_sync_status(&conn).expect("get sync status"))
        .expect("parse sync status");

    assert_eq!(
        status
            .get("ical_subscription_total_count")
            .and_then(Value::as_i64),
        Some(2)
    );
    assert_eq!(
        status
            .get("ical_subscription_failing_count")
            .and_then(Value::as_i64),
        Some(1)
    );
    assert_eq!(
        status
            .get("ical_subscription_never_refreshed_count")
            .and_then(Value::as_i64),
        Some(1)
    );
    assert_eq!(
        status
            .get("ical_subscription_stale_count")
            .and_then(Value::as_i64),
        Some(0)
    );
}

#[test]
#[serial_test::serial(hlc)]
fn get_sync_status_keeps_valid_retention_timestamps_when_some_rows_are_malformed() {
    let conn = setup_sync_status_test_conn();
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
         ) VALUES ('task', 'task-b', '0000000000000_0000_test0001', ?1, NULL, NULL)",
        rusqlite::params!["2026-03-05T12:00:00Z"],
    )
    .expect("insert valid tombstone");
    conn.execute(
        "INSERT INTO sync_conflict_log (
            entity_type, entity_id, winner_version, loser_version,
            loser_device_id, loser_payload, resolved_at, resolution_type
         ) VALUES ('task', 'task-a', '0000000000000_0000_test0002', '0000000000000_0000_test0001', 'device-a', NULL, 'not-a-timestamp', 'lww')",
        [],
    )
    .expect("insert malformed conflict");
    conn.execute(
        "INSERT INTO sync_conflict_log (
            entity_type, entity_id, winner_version, loser_version,
            loser_device_id, loser_payload, resolved_at, resolution_type
         ) VALUES ('task', 'task-b', '0000000000000_0000_test0004', '0000000000000_0000_test0003', 'device-b', NULL, ?1, 'fk_unresolved')",
        rusqlite::params!["2026-03-06T13:30:00Z"],
    )
    .expect("insert valid conflict");

    let status = serde_json::from_str::<Value>(&get_sync_status(&conn).expect("get sync status"))
        .expect("parse sync status");

    assert_eq!(
        status
            .get("tombstone_oldest_deleted_at")
            .and_then(Value::as_str),
        Some("2026-03-05T12:00:00Z")
    );
    assert_eq!(
        status
            .get("tombstone_newest_deleted_at")
            .and_then(Value::as_str),
        Some("2026-03-05T12:00:00Z")
    );
    assert_eq!(
        status
            .get("tombstone_oldest_deleted_at_malformed")
            .and_then(Value::as_bool),
        Some(true)
    );
    assert_eq!(
        status
            .get("tombstone_newest_deleted_at_malformed")
            .and_then(Value::as_bool),
        Some(true)
    );
    assert_eq!(
        status
            .get("conflict_log_last_resolved_at")
            .and_then(Value::as_str),
        Some("2026-03-06T13:30:00Z")
    );
    assert_eq!(
        status
            .get("conflict_log_last_resolved_at_malformed")
            .and_then(Value::as_bool),
        Some(true)
    );
}
