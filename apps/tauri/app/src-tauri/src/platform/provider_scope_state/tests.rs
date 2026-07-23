use super::*;

use crate::test_support::test_conn;

#[test]
fn record_refresh_success_persists_runtime_state() {
    let conn = test_conn();

    record_refresh_success(&conn, "ical_subscription", "sub-1", "2026-03-29T20:55:00Z")
        .expect("record refresh success");

    let row: (String, String, String, String) = conn
        .query_row(
            "SELECT provider_kind, provider_scope, availability_state, last_refresh_result
             FROM provider_scope_runtime_state
             WHERE provider_kind = ?1 AND provider_scope = ?2",
            ["ical_subscription", "sub-1"],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("load provider scope runtime state");

    assert_eq!(row.0, "ical_subscription");
    assert_eq!(row.1, "sub-1");
    assert_eq!(row.2, "enabled");
    assert_eq!(row.3, "success");
}

#[test]
fn record_refresh_error_propagates_state_write_failures() {
    let conn = test_conn();
    conn.execute("DROP TABLE provider_scope_runtime_state", [])
        .expect("drop provider scope runtime state");

    let error = record_refresh_error(
        &conn,
        "ical_subscription",
        "sub-1",
        "2026-03-29T20:56:00Z",
        "fetch failed",
        "fetch_error",
    )
    .expect_err("missing provider scope runtime state table should fail");

    assert!(
        error.to_string().contains("provider_scope_runtime_state"),
        "unexpected error: {error}"
    );
}
