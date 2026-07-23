use super::shared::setup_sync_status_test_conn;
use crate::system::sync::get_sync_status;
use serde_json::Value;

#[test]
#[serial_test::serial(hlc)]
fn get_sync_status_marks_malformed_sync_backend_kind_instead_of_normalizing_default() {
    let conn = setup_sync_status_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value) VALUES (?1, ?2)",
        rusqlite::params![
            lorvex_domain::preference_keys::PREF_SYNC_BACKEND_KIND,
            "{not-valid-json"
        ],
    )
    .expect("insert malformed sync_backend_kind");

    let status = serde_json::from_str::<Value>(&get_sync_status(&conn).expect("get sync status"))
        .expect("parse sync status");

    assert_eq!(
        status.get("sync_backend_kind_raw").and_then(Value::as_str),
        Some("{not-valid-json")
    );
    assert!(status.get("sync_backend_kind").is_some());
    assert!(status.get("sync_backend_kind").unwrap().is_null());
    assert_eq!(
        status
            .get("sync_backend_kind_malformed")
            .and_then(Value::as_bool),
        Some(true)
    );
    assert_eq!(
        status
            .get("sync_backend_kind_malformed_reason")
            .and_then(Value::as_str),
        Some("invalid_json")
    );
}

#[test]
#[serial_test::serial(hlc)]
fn get_sync_status_marks_unknown_sync_backend_kind_with_reason() {
    let conn = setup_sync_status_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value) VALUES (?1, ?2)",
        rusqlite::params![
            lorvex_domain::preference_keys::PREF_SYNC_BACKEND_KIND,
            r#""definitely_invalid""#
        ],
    )
    .expect("insert unknown sync_backend_kind");

    let status = serde_json::from_str::<Value>(&get_sync_status(&conn).expect("get sync status"))
        .expect("parse sync status");

    assert_eq!(
        status.get("sync_backend_kind_raw").and_then(Value::as_str),
        Some(r#""definitely_invalid""#)
    );
    assert_eq!(
        status
            .get("sync_backend_kind_malformed")
            .and_then(Value::as_bool),
        Some(true)
    );
    assert_eq!(
        status
            .get("sync_backend_kind_malformed_reason")
            .and_then(Value::as_str),
        Some("unknown_backend_kind")
    );
}

#[test]
#[serial_test::serial(hlc)]
fn get_sync_status_uses_explicit_valid_sync_backend_kind_as_effective_value() {
    let conn = setup_sync_status_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value) VALUES (?1, ?2)",
        rusqlite::params![
            lorvex_domain::preference_keys::PREF_SYNC_BACKEND_KIND,
            r#""filesystem_bridge""#
        ],
    )
    .expect("insert valid sync_backend_kind");

    let status = serde_json::from_str::<Value>(&get_sync_status(&conn).expect("get sync status"))
        .expect("parse sync status");

    assert_eq!(
        status.get("sync_backend_kind").and_then(Value::as_str),
        Some("filesystem_bridge")
    );
    assert_eq!(
        status
            .get("sync_backend_kind_effective")
            .and_then(Value::as_str),
        Some("filesystem_bridge")
    );
    assert_eq!(
        status
            .get("sync_backend_kind_malformed")
            .and_then(Value::as_bool),
        Some(false)
    );
}

#[test]
#[serial_test::serial(hlc)]
fn get_sync_status_keeps_missing_sync_backend_kind_unconfigured_but_resolves_effective_default() {
    let conn = setup_sync_status_test_conn();

    let status = serde_json::from_str::<Value>(&get_sync_status(&conn).expect("get sync status"))
        .expect("parse sync status");

    assert!(status.get("sync_backend_kind_raw").is_some());
    assert!(status.get("sync_backend_kind_raw").unwrap().is_null());
    assert!(status.get("sync_backend_kind").is_some());
    assert!(status.get("sync_backend_kind").unwrap().is_null());
    assert_eq!(
        status
            .get("sync_backend_kind_effective")
            .and_then(Value::as_str),
        Some("filesystem_bridge")
    );
    assert_eq!(
        status
            .get("sync_backend_kind_malformed")
            .and_then(Value::as_bool),
        Some(false)
    );
    assert!(status
        .get("sync_backend_kind_malformed_reason")
        .unwrap()
        .is_null());
}
