use super::*;
use chrono::{TimeZone, Utc};

fn setup_test_conn() -> Connection {
    let conn = Connection::open_in_memory().expect("open in-memory db");
    lorvex_store::migration::apply_migrations(&conn, &lorvex_store::schema::all_migrations())
        .expect("apply migrations");
    conn
}

#[test]
fn active_timezone_name_reads_json_string_preference() {
    let conn = setup_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES ('timezone', '\"America/Los_Angeles\"', '0000000000000_0000_0000000000000000', '2026-03-08T01:00:00Z')",
        [],
    )
    .expect("insert timezone preference");

    assert_eq!(
        active_timezone_name(&conn).expect("read timezone preference"),
        Some("America/Los_Angeles".to_string())
    );
}

#[test]
fn active_timezone_name_returns_none_when_no_preference() {
    let conn = setup_test_conn();
    assert_eq!(
        active_timezone_name(&conn).expect("no preference set"),
        None
    );
}

#[test]
fn active_timezone_name_rejects_non_json_raw_value() {
    let conn = setup_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES ('timezone', 'America/Los_Angeles', '0000000000000_0000_0000000000000000', '2026-03-08T01:00:00Z')",
        [],
    )
    .expect("insert malformed timezone preference");

    let error = active_timezone_name(&conn)
        .expect_err("malformed timezone preference should fail")
        .to_string();
    assert!(error.contains("timezone"), "unexpected error: {error}");
}

#[test]
fn active_timezone_name_rejects_invalid_json_timezone_string() {
    let conn = setup_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES ('timezone', '\"Not/AZone\"', '0000000000000_0000_0000000000000000', '2026-03-08T01:00:00Z')",
        [],
    )
    .expect("insert invalid timezone preference");

    let error = active_timezone_name(&conn)
        .expect_err("invalid timezone preference should fail")
        .to_string();
    assert!(error.contains("timezone"), "unexpected error: {error}");
}

#[test]
fn today_ymd_for_conn_uses_timezone_preference_calendar_day() {
    let conn = setup_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES ('timezone', '\"America/Los_Angeles\"', '0000000000000_0000_0000000000000000', '2026-03-08T01:00:00Z')",
        [],
    )
    .expect("insert timezone preference");
    let now = Utc
        .with_ymd_and_hms(2026, 3, 8, 1, 0, 0)
        .single()
        .expect("construct UTC instant");

    assert_eq!(
        today_ymd_for_conn_at(&conn, now).expect("compute today"),
        "2026-03-07"
    );
}

#[test]
fn first_valid_utc_falls_back_across_skipped_apia_day() {
    let tz = lorvex_domain::parse_timezone_name("Pacific/Apia")
        .expect("chrono-tz resolves Pacific/Apia");
    let skipped = NaiveDate::from_ymd_opt(2011, 12, 30).unwrap();
    let resolved = first_valid_utc_for_local_day(skipped, &tz).expect("fallback returns Some");
    let expected = DateTime::parse_from_rfc3339("2011-12-30T10:00:00Z")
        .unwrap()
        .with_timezone(&Utc);
    assert_eq!(resolved, expected);
}

#[test]
fn first_valid_utc_non_skipped_day_returns_local_midnight() {
    let tz = lorvex_domain::parse_timezone_name("America/Los_Angeles").unwrap();
    let day = NaiveDate::from_ymd_opt(2026, 3, 15).unwrap();
    let resolved = first_valid_utc_for_local_day(day, &tz).unwrap();
    let expected = DateTime::parse_from_rfc3339("2026-03-15T07:00:00Z")
        .unwrap()
        .with_timezone(&Utc);
    assert_eq!(resolved, expected);
}

#[test]
fn trailing_day_window_utc_bounds_for_conn_uses_timezone_midnight_boundaries() {
    let conn = setup_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES ('timezone', '\"America/Los_Angeles\"', '0000000000000_0000_0000000000000000', '2026-03-08T01:00:00Z')",
        [],
    )
    .expect("insert timezone preference");
    let now = Utc
        .with_ymd_and_hms(2026, 3, 15, 12, 0, 0)
        .single()
        .expect("construct UTC instant");

    let bounds = trailing_day_window_utc_bounds_for_conn_at(&conn, now, 7).expect("resolve window");

    assert_eq!(bounds.from_day, "2026-03-09");
    assert_eq!(bounds.to_day, "2026-03-15");
    assert_eq!(bounds.start_utc, "2026-03-09T07:00:00.000Z");
    assert_eq!(bounds.end_utc, "2026-03-16T07:00:00.000Z");
}
