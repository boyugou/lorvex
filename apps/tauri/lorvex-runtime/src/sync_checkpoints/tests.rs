use super::*;

fn setup_conn() -> Connection {
    let conn = Connection::open_in_memory().expect("open in-memory db");
    conn.execute(
        "CREATE TABLE sync_checkpoints (key TEXT PRIMARY KEY, value TEXT NOT NULL) STRICT",
        [],
    )
    .expect("create sync_checkpoints");
    conn
}

#[test]
fn get_after_set_returns_value() {
    let conn = setup_conn();
    set(&conn, KEY_LAST_ERROR, "boom").expect("set");
    assert_eq!(
        get(&conn, KEY_LAST_ERROR).expect("get"),
        Some("boom".to_string())
    );
}

#[test]
fn get_missing_key_returns_none() {
    let conn = setup_conn();
    assert!(get(&conn, "absent").expect("get").is_none());
}

#[test]
fn set_is_idempotent_for_same_value() {
    let conn = setup_conn();
    set(&conn, KEY_LAST_SUCCESS_AT, "2026-04-26T00:00:00Z").expect("first set");
    set(&conn, KEY_LAST_SUCCESS_AT, "2026-04-26T00:00:00Z").expect("second set");
    assert_eq!(
        get(&conn, KEY_LAST_SUCCESS_AT).expect("get"),
        Some("2026-04-26T00:00:00Z".to_string())
    );
}

#[test]
fn set_overwrites_previous_value() {
    let conn = setup_conn();
    set(&conn, KEY_LAST_ERROR, "first").expect("first set");
    set(&conn, KEY_LAST_ERROR, "second").expect("second set");
    assert_eq!(
        get(&conn, KEY_LAST_ERROR).expect("get"),
        Some("second".to_string())
    );
}

#[test]
fn clear_removes_row_and_reports_deletion() {
    let conn = setup_conn();
    set(&conn, KEY_LAST_ERROR, "boom").expect("set");
    assert!(clear(&conn, KEY_LAST_ERROR).expect("clear"));
    assert!(get(&conn, KEY_LAST_ERROR).expect("get").is_none());
    // Second clear is a no-op and reports `false`.
    assert!(!clear(&conn, KEY_LAST_ERROR).expect("re-clear"));
}

#[test]
fn set_if_absent_only_inserts_when_absent() {
    let conn = setup_conn();
    assert!(
        set_if_absent(&conn, KEY_DEVICE_ID, "first").expect("first set_if_absent"),
        "first call should insert"
    );
    assert_eq!(
        get(&conn, KEY_DEVICE_ID).expect("get"),
        Some("first".to_string())
    );
    assert!(
        !set_if_absent(&conn, KEY_DEVICE_ID, "second").expect("second set_if_absent"),
        "second call should NOT overwrite"
    );
    assert_eq!(
        get(&conn, KEY_DEVICE_ID).expect("get"),
        Some("first".to_string()),
        "value must still be the originally-claimed one"
    );
}
