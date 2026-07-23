use super::*;

fn insert_calendar_subscription(conn: &Connection, id: &str, enabled: bool) {
    conn.execute(
        "INSERT INTO calendar_subscriptions (
            id, name, url, color, enabled, version, created_at, updated_at
         ) VALUES (?1, ?2, ?3, NULL, ?4, ?5, ?6, ?6)",
        params![
            id,
            format!("Subscription {id}"),
            format!("https://example.com/{id}.ics"),
            enabled as i64,
            format!("0000000000000_0000_{id}"),
            "2026-03-01T08:00:00Z",
        ],
    )
    .expect("insert calendar subscription");
}

fn insert_subscription_runtime_state(
    conn: &Connection,
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
        params![
            scope,
            availability_state,
            last_refresh_result,
            last_refresh_success_at
        ],
    )
    .expect("insert ical runtime state");
}

#[test]
fn load_sync_status_from_conn_surfaces_ical_subscription_health() {
    let conn = setup_sync_test_conn();
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

    let status = load_sync_status_from_conn(&conn).expect("load sync status");
    assert_eq!(status.ical_subscription_total_count, 7);
    assert_eq!(status.ical_subscription_failing_count, 2);
    assert_eq!(status.ical_subscription_never_refreshed_count, 2);
    assert_eq!(status.ical_subscription_stale_count, 1);
}

#[test]
fn load_sync_status_from_conn_treats_missing_ical_runtime_rows_as_non_failing() {
    let conn = setup_sync_test_conn();
    insert_calendar_subscription(&conn, "sub-new", true);

    let status = load_sync_status_from_conn(&conn).expect("load sync status");
    assert_eq!(status.ical_subscription_total_count, 1);
    assert_eq!(status.ical_subscription_failing_count, 0);
    assert_eq!(status.ical_subscription_never_refreshed_count, 1);
    assert_eq!(status.ical_subscription_stale_count, 0);
}
