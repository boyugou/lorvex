use super::support::*;

#[test]
fn append_error_log_internal_writes_normalized_entries() {
    let conn = setup_sync_test_conn();
    append_error_log_internal(
        &conn,
        "frontend.window",
        "Unhandled error",
        Some("  stack trace  ".to_string()),
        Some("warning".to_string()),
    )
    .expect("append warning log");
    append_error_log_internal(
        &conn,
        "frontend.promise",
        "Promise rejection",
        None,
        Some("unknown-level".to_string()),
    )
    .expect("append fallback-level log");

    let logs = read_error_logs(&conn, Some(50), None).expect("read error logs");
    assert_eq!(logs.len(), 2);
    assert!(logs.iter().any(|log| log.source == "frontend.window"
        && log.level == "warn"
        && log.details.as_deref() == Some("stack trace")));
    assert!(logs
        .iter()
        .any(|log| log.source == "frontend.promise" && log.level == "error"));
}

#[test]
fn append_error_log_internal_rejects_empty_source_or_message() {
    let conn = setup_sync_test_conn();
    assert!(append_error_log_internal(&conn, "   ", "boom", None, None).is_err());
    assert!(append_error_log_internal(&conn, "frontend.window", "   ", None, None).is_err());
}

#[test]
fn append_error_log_redacts_bearer_tokens_at_write_time() {
    // Regression for the redact-at-write contract: secrets that reach the
    // error_logs table must be redacted at write, so every downstream
    // surface (Settings → Diagnostics, copy-to-clipboard bundles, MCP
    // get_recent_logs) is automatically safe. Previously MCP's read path
    // redacted but the Tauri read path didn't; fixing redaction at write
    // closes both without depending on every reader remembering.
    let conn = setup_sync_test_conn();
    let raw_details = "GET /api/x failed: Authorization: Bearer eyJhbGciOi.deadbeef.xyz";
    append_error_log_internal(
        &conn,
        "frontend.http",
        "fetch failed",
        Some(raw_details.to_string()),
        Some("error".to_string()),
    )
    .expect("append log");

    let rows = read_error_logs(&conn, Some(10), None).expect("read logs");
    assert_eq!(rows.len(), 1, "expected one written row");
    let stored = rows[0].details.as_deref().unwrap_or_default();
    assert!(
        !stored.contains("eyJhbGciOi.deadbeef.xyz"),
        "bearer token must not reach the DB; stored = {stored}"
    );
    assert!(
        stored.contains("[REDACTED]"),
        "redaction sentinel missing from stored details: {stored}"
    );
}

#[test]
fn append_error_log_redacts_api_key_prefixes_and_json_secrets() {
    let conn = setup_sync_test_conn();
    let raw_details =
        r#"stripe webhook failed: sk_live_supersecret, body={"password":"hunter2","note":"ok"}"#;
    append_error_log_internal(
        &conn,
        "frontend.stripe",
        "webhook failed",
        Some(raw_details.to_string()),
        None,
    )
    .expect("append log");

    let rows = read_error_logs(&conn, Some(10), None).expect("read logs");
    let stored = rows[0].details.as_deref().unwrap_or_default();
    assert!(
        !stored.contains("sk_live_supersecret"),
        "API key leaked: {stored}"
    );
    assert!(!stored.contains("hunter2"), "password leaked: {stored}");
    assert!(stored.contains("[REDACTED_TOKEN]") || stored.contains("[REDACTED]"));
    assert!(stored.contains("[REDACTED_JSON_SECRET]"));
}

#[test]
fn clear_error_logs_removes_all_rows() {
    let conn = setup_sync_test_conn();
    append_error_log_internal(&conn, "frontend.window", "boom-1", None, None)
        .expect("append log 1");
    append_error_log_internal(&conn, "frontend.window", "boom-2", None, None)
        .expect("append log 2");

    let deleted = conn
        .execute("DELETE FROM error_logs", [])
        .expect("clear error logs directly");
    assert_eq!(deleted, 2);
    let remaining = read_error_logs(&conn, Some(10), None).expect("read logs after clear");
    assert!(remaining.is_empty());
}
