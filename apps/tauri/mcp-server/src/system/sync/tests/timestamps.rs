use super::shared::setup_sync_status_test_conn;
use crate::system::sync::get_sync_status;
use serde_json::Value;

#[test]
#[serial_test::serial(hlc)]
fn get_sync_status_trims_valid_timestamp_state() {
    let conn = setup_sync_status_test_conn();
    conn.execute(
        "INSERT INTO sync_outbox (entity_type, entity_id, operation, version, payload_schema_version, payload, device_id, created_at, synced_at, retry_count)
         VALUES ('task', 'task-1', 'upsert', '0000000000000_0000_a0a0a0a0a0a0a0a0', 1, '{}', 'dev-1', '2026-03-02T12:00:00Z', ' 2026-03-02T11:00:00Z ', 0)",
        [],
    )
    .expect("insert synced outbox entry");
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        rusqlite::params!["last_success_at", " 2026-03-02T10:00:00Z "],
    )
    .expect("insert spaced last_success_at");
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        rusqlite::params!["last_pull_at", " 2026-03-02T09:00:00Z "],
    )
    .expect("insert spaced last_pull_at");
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        rusqlite::params![
            "filesystem_bridge_lookback_known_id_skipped_last_run_at",
            " 2026-03-05T02:20:00Z "
        ],
    )
    .expect("insert spaced lookback timestamp");

    let status = serde_json::from_str::<Value>(&get_sync_status(&conn).expect("get sync status"))
        .expect("parse sync status");

    assert_eq!(
        status.get("last_synced_at").and_then(Value::as_str),
        Some("2026-03-02T11:00:00Z")
    );
    assert_eq!(
        status.get("last_success_at").and_then(Value::as_str),
        Some("2026-03-02T10:00:00Z")
    );
    assert_eq!(
        status.get("last_pull_at").and_then(Value::as_str),
        Some("2026-03-02T09:00:00Z")
    );
    assert_eq!(
        status
            .get("filesystem_bridge_lookback_known_id_skipped_last_run_at")
            .and_then(Value::as_str),
        Some("2026-03-05T02:20:00Z")
    );
    assert_eq!(
        status
            .get("last_synced_at_malformed")
            .and_then(Value::as_bool),
        Some(false)
    );
    assert_eq!(
        status
            .get("last_synced_at_malformed_reason")
            .and_then(Value::as_str),
        None
    );
    assert_eq!(
        status
            .get("last_success_at_malformed")
            .and_then(Value::as_bool),
        Some(false)
    );
    assert_eq!(
        status
            .get("last_success_at_malformed_reason")
            .and_then(Value::as_str),
        None
    );
    assert_eq!(
        status
            .get("last_pull_at_malformed")
            .and_then(Value::as_bool),
        Some(false)
    );
    assert_eq!(
        status
            .get("last_pull_at_malformed_reason")
            .and_then(Value::as_str),
        None
    );
    assert_eq!(
        status
            .get("filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed")
            .and_then(Value::as_bool),
        Some(false)
    );
    assert_eq!(
        status
            .get("filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed_reason")
            .and_then(Value::as_str),
        None
    );
}

#[test]
#[serial_test::serial(hlc)]
fn get_sync_status_surfaces_malformed_timestamp_and_counter_reasons() {
    let conn = setup_sync_status_test_conn();
    conn.execute(
        "INSERT INTO sync_outbox (entity_type, entity_id, operation, version, payload_schema_version, payload, device_id, created_at, synced_at, retry_count)
         VALUES ('task', 'task-1', 'upsert', '0000000000000_0000_a0a0a0a0a0a0a0a0', 1, '{}', 'dev-1', '2026-03-02T12:00:00Z', 'not-a-timestamp', 0)",
        [],
    )
    .expect("insert malformed synced outbox entry");
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        rusqlite::params!["last_success_at", "   "],
    )
    .expect("insert empty last_success_at");
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        rusqlite::params!["last_pull_at", "not-rfc3339"],
    )
    .expect("insert malformed last_pull_at");
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        rusqlite::params![
            "filesystem_bridge_lookback_known_id_skipped_last_run_at",
            "   "
        ],
    )
    .expect("insert empty lookback timestamp");
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        rusqlite::params![
            "filesystem_bridge_lookback_known_id_skipped_last_run",
            "not-an-integer"
        ],
    )
    .expect("insert malformed lookback counter");

    let status = serde_json::from_str::<Value>(&get_sync_status(&conn).expect("get sync status"))
        .expect("parse sync status");

    assert_eq!(
        status
            .get("last_synced_at_malformed_reason")
            .and_then(Value::as_str),
        Some("invalid_rfc3339")
    );
    assert_eq!(
        status
            .get("last_success_at_malformed_reason")
            .and_then(Value::as_str),
        Some("empty_timestamp")
    );
    assert_eq!(
        status
            .get("last_pull_at_malformed_reason")
            .and_then(Value::as_str),
        Some("invalid_rfc3339")
    );
    assert_eq!(
        status
            .get("filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed_reason")
            .and_then(Value::as_str),
        Some("empty_timestamp")
    );
    assert_eq!(
        status
            .get("filesystem_bridge_lookback_known_id_skipped_last_run_malformed_reason")
            .and_then(Value::as_str),
        Some("invalid_i64")
    );
}
