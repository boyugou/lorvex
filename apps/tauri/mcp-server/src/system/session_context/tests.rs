use super::*;

// ── parse_section unit tests ─────────────────────────

#[test]
#[serial_test::serial(hlc)]
fn parse_section_ok_json_returns_value() {
    let input: Result<String, String> = Ok(r#"{"tasks":[]}"#.to_string());
    let result = parse_section(input);
    assert!(result.is_object());
    assert!(result.get("tasks").unwrap().is_array());
}

#[test]
#[serial_test::serial(hlc)]
fn parse_section_ok_non_json_returns_error_object() {
    let input: Result<String, String> = Ok("plain text response".to_string());
    let result = parse_section(input);
    let error = result
        .get("error")
        .and_then(Value::as_str)
        .expect("expected error string");
    assert!(
        error.contains("section returned malformed JSON"),
        "unexpected error: {error}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn parse_section_err_returns_error_object() {
    let input: Result<String, String> = Err("db connection failed".to_string());
    let result = parse_section(input);
    assert!(result.is_object());
    assert_eq!(
        result.get("error").unwrap().as_str().unwrap(),
        "db connection failed"
    );
}

// ── get_session_context integration test ──────────────────────

#[test]
#[serial_test::serial(hlc)]
fn session_context_returns_all_expected_keys() {
    // Use the MCP test infrastructure to get a real connection.
    let dir = tempfile::tempdir().expect("create tempdir");
    let db_path = dir.path().join("db.sqlite");
    let pool = lorvex_store::ConnectionPool::new(&db_path, 2).expect("create pool");
    let conn = pool.read_lock_result().expect("read lock");

    let result = get_session_context(&conn);
    assert!(result.is_ok(), "get_session_context failed: {result:?}");

    let payload: Value = serde_json::from_str(&result.unwrap()).expect("parse payload");

    // Every expected top-level key must be present.
    let expected_keys = [
        "date",
        "memory",
        "overview",
        "current_focus",
        "today_events",
        "recent_changelog",
        "guide",
        "habits",
    ];
    for key in &expected_keys {
        assert!(payload.get(key).is_some(), "missing expected key: {key}");
    }
}
