use super::*;

fn setup() -> Connection {
    let conn = Connection::open_in_memory().expect("open in-memory db");
    // Path is one `..` deeper than the original `device_state.rs` site
    // because tests now live under `device_state/tests.rs`.
    conn.execute_batch(include_str!(
        "../../../../../lorvex-store/src/schema/001_schema.sql"
    ))
    .expect("apply consolidated schema");
    conn
}

#[test]
#[serial_test::serial(hlc)]
fn read_calendar_ai_access_mode_defaults_when_missing() {
    let conn = setup();

    let mode = read_calendar_ai_access_mode(&conn).expect("read default access mode");

    assert_eq!(mode, CalendarAiAccessMode::default_mode());
}

#[test]
#[serial_test::serial(hlc)]
fn read_calendar_ai_access_mode_rejects_malformed_state() {
    let conn = setup();
    conn.execute(
        "INSERT INTO device_state (key, value) VALUES (?1, ?2)",
        (
            lorvex_domain::preference_keys::DEV_CALENDAR_AI_ACCESS_MODE,
            "\"definitely_not_a_mode\"",
        ),
    )
    .expect("insert malformed access mode");

    let error = read_calendar_ai_access_mode(&conn)
        .expect_err("malformed access mode should be rejected")
        .to_string();

    assert!(
        error.contains("calendar_ai_access_mode"),
        "unexpected error: {error}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn read_calendar_ai_access_mode_accepts_explicit_off() {
    let conn = setup();
    conn.execute(
        "INSERT INTO device_state (key, value) VALUES (?1, ?2)",
        (
            lorvex_domain::preference_keys::DEV_CALENDAR_AI_ACCESS_MODE,
            "\"off\"",
        ),
    )
    .expect("insert off access mode");

    let mode = read_calendar_ai_access_mode(&conn).expect("read access mode");

    assert_eq!(mode, CalendarAiAccessMode::Off);
}

#[test]
#[serial_test::serial(hlc)]
fn read_calendar_ai_access_mode_accepts_full_details() {
    let conn = setup();
    conn.execute(
        "INSERT INTO device_state (key, value) VALUES (?1, ?2)",
        (
            lorvex_domain::preference_keys::DEV_CALENDAR_AI_ACCESS_MODE,
            "\"full_details\"",
        ),
    )
    .expect("insert full-details access mode");

    let mode = read_calendar_ai_access_mode(&conn).expect("read access mode");

    assert_eq!(mode, CalendarAiAccessMode::FullDetails);
}

#[test]
#[serial_test::serial(hlc)]
fn read_calendar_ai_access_mode_rejects_legacy_allow_deny_values() {
    for value in ["allow", "deny"] {
        let conn = setup();
        conn.execute(
            "INSERT INTO device_state (key, value) VALUES (?1, ?2)",
            (
                lorvex_domain::preference_keys::DEV_CALENDAR_AI_ACCESS_MODE,
                serde_json::to_string(value).expect("serialize legacy value"),
            ),
        )
        .expect("insert legacy access mode");

        let error = read_calendar_ai_access_mode(&conn)
            .expect_err("legacy access mode should be rejected")
            .to_string();

        assert!(error.contains(value), "unexpected error: {error}");
    }
}

#[test]
#[serial_test::serial(hlc)]
fn read_calendar_ai_access_mode_rejects_non_string_json_state() {
    let conn = setup();
    conn.execute(
        "INSERT INTO device_state (key, value) VALUES (?1, ?2)",
        (
            lorvex_domain::preference_keys::DEV_CALENDAR_AI_ACCESS_MODE,
            "{\"unexpected\":true}",
        ),
    )
    .expect("insert malformed access mode");

    let error = read_calendar_ai_access_mode(&conn)
        .expect_err("non-string access mode should be rejected")
        .to_string();

    assert!(error.contains("JSON string"), "unexpected error: {error}");
}
