use super::shared::setup_sync_status_test_conn;
use crate::system::sync::get_sync_status;
use serde_json::Value;

#[test]
#[serial_test::serial(hlc)]
fn get_sync_status_surfaces_filesystem_bridge_cursor_state() {
    let conn = setup_sync_status_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        rusqlite::params![
            "filesystem_bridge_last_pull_cursor",
            r#"{"updated_at":"0001743573600000_0001_f115b71d6efa11ed","device_id":"device-1","event_id":"event-1"}"#,
        ],
    )
    .expect("insert filesystem bridge cursor");

    let status = serde_json::from_str::<Value>(&get_sync_status(&conn).expect("get sync status"))
        .expect("parse sync status");

    assert_eq!(
        status
            .get("filesystem_bridge_last_pull_updated_at")
            .and_then(Value::as_str),
        Some("0001743573600000_0001_f115b71d6efa11ed")
    );
    assert_eq!(
        status
            .get("filesystem_bridge_last_pull_device_id")
            .and_then(Value::as_str),
        Some("device-1")
    );
    assert_eq!(
        status
            .get("filesystem_bridge_last_pull_event_id")
            .and_then(Value::as_str),
        Some("event-1")
    );
    assert_eq!(
        status
            .get("filesystem_bridge_last_pull_cursor_malformed")
            .and_then(Value::as_bool),
        Some(false)
    );
}

#[test]
#[serial_test::serial(hlc)]
fn get_sync_status_flags_invalid_filesystem_bridge_cursor_timestamp_as_malformed() {
    let conn = setup_sync_status_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        rusqlite::params![
            "filesystem_bridge_last_pull_cursor",
            r#"{"updated_at":"not-a-timestamp","device_id":"device-1","event_id":"event-1"}"#,
        ],
    )
    .expect("insert malformed filesystem bridge cursor");

    let status = serde_json::from_str::<Value>(&get_sync_status(&conn).expect("get sync status"))
        .expect("parse sync status");

    assert_eq!(
        status
            .get("filesystem_bridge_last_pull_updated_at")
            .and_then(Value::as_str),
        None
    );
    assert_eq!(
        status
            .get("filesystem_bridge_last_pull_device_id")
            .and_then(Value::as_str),
        None
    );
    assert_eq!(
        status
            .get("filesystem_bridge_last_pull_event_id")
            .and_then(Value::as_str),
        None
    );
    assert_eq!(
        status
            .get("filesystem_bridge_last_pull_cursor_malformed")
            .and_then(Value::as_bool),
        Some(true)
    );
    assert_eq!(
        status
            .get("filesystem_bridge_last_pull_cursor_malformed_reason")
            .and_then(Value::as_str),
        Some("invalid_updated_at_hlc")
    );
}

#[test]
#[serial_test::serial(hlc)]
fn get_sync_status_flags_non_hlc_filesystem_bridge_cursor_version_as_malformed() {
    let conn = setup_sync_status_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        rusqlite::params![
            "filesystem_bridge_last_pull_cursor",
            r#"{"updated_at":"2026-03-02T10:00:00Z","device_id":"device-1","event_id":"event-1"}"#,
        ],
    )
    .expect("insert non-hlc filesystem bridge cursor");

    let status = serde_json::from_str::<Value>(&get_sync_status(&conn).expect("get sync status"))
        .expect("parse sync status");

    assert_eq!(
        status
            .get("filesystem_bridge_last_pull_updated_at")
            .and_then(Value::as_str),
        None
    );
    assert_eq!(
        status
            .get("filesystem_bridge_last_pull_device_id")
            .and_then(Value::as_str),
        None
    );
    assert_eq!(
        status
            .get("filesystem_bridge_last_pull_event_id")
            .and_then(Value::as_str),
        None
    );
    assert_eq!(
        status
            .get("filesystem_bridge_last_pull_cursor_malformed")
            .and_then(Value::as_bool),
        Some(true)
    );
    assert_eq!(
        status
            .get("filesystem_bridge_last_pull_cursor_malformed_reason")
            .and_then(Value::as_str),
        Some("invalid_updated_at_hlc")
    );
}

#[test]
#[serial_test::serial(hlc)]
fn get_sync_status_flags_empty_filesystem_bridge_cursor_device_id_as_malformed() {
    let conn = setup_sync_status_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        rusqlite::params![
            "filesystem_bridge_last_pull_cursor",
            r#"{"updated_at":"0001743573600000_0001_f115b71d6efa11ed","device_id":"   ","event_id":"event-1"}"#,
        ],
    )
    .expect("insert empty device_id filesystem bridge cursor");

    let status = serde_json::from_str::<Value>(&get_sync_status(&conn).expect("get sync status"))
        .expect("parse sync status");

    assert_eq!(
        status
            .get("filesystem_bridge_last_pull_updated_at")
            .and_then(Value::as_str),
        None
    );
    assert_eq!(
        status
            .get("filesystem_bridge_last_pull_device_id")
            .and_then(Value::as_str),
        None
    );
    assert_eq!(
        status
            .get("filesystem_bridge_last_pull_event_id")
            .and_then(Value::as_str),
        None
    );
    assert_eq!(
        status
            .get("filesystem_bridge_last_pull_cursor_malformed")
            .and_then(Value::as_bool),
        Some(true)
    );
    assert_eq!(
        status
            .get("filesystem_bridge_last_pull_cursor_malformed_reason")
            .and_then(Value::as_str),
        Some("empty_device_id")
    );
}

#[test]
#[serial_test::serial(hlc)]
fn get_sync_status_flags_invalid_json_filesystem_bridge_cursor_with_reason() {
    let conn = setup_sync_status_test_conn();
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2)",
        rusqlite::params!["filesystem_bridge_last_pull_cursor", "{not-json}"],
    )
    .expect("insert invalid-json filesystem bridge cursor");

    let status = serde_json::from_str::<Value>(&get_sync_status(&conn).expect("get sync status"))
        .expect("parse sync status");

    assert_eq!(
        status
            .get("filesystem_bridge_last_pull_cursor_malformed")
            .and_then(Value::as_bool),
        Some(true)
    );
    assert_eq!(
        status
            .get("filesystem_bridge_last_pull_cursor_malformed_reason")
            .and_then(Value::as_str),
        Some("invalid_json")
    );
}
