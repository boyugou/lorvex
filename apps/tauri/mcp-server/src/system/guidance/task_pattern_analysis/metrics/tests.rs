use super::load_insight_thresholds;
use rusqlite::hooks::{AuthAction, AuthContext, Authorization};
use rusqlite::Connection;

fn test_db() -> Connection {
    lorvex_store::open_db_in_memory().expect("open in-memory db")
}

#[test]
#[serial_test::serial(hlc)]
fn load_insight_thresholds_rejects_json_string_thresholds() {
    let conn = test_db();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
        (
            "insight_defer_count_min",
            "\"9\"",
            "0000000000000_0000_0000000000000000",
            "2026-03-29T00:00:00Z",
        ),
    )
    .expect("insert threshold preference");

    let error =
        load_insight_thresholds(&conn).expect_err("string threshold preference should be rejected");
    assert!(
        error
            .to_string()
            .contains("invalid insight_defer_count_min preference"),
        "unexpected error: {error}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn load_insight_thresholds_accepts_json_numeric_thresholds() {
    let conn = test_db();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
        (
            "insight_stalled_window_days",
            "11",
            "0000000000000_0000_0000000000000000",
            "2026-03-29T00:00:00Z",
        ),
    )
    .expect("insert numeric threshold preference");

    let thresholds = load_insight_thresholds(&conn).expect("threshold load should succeed");
    assert_eq!(thresholds.stalled_window_days, 11);
}

#[test]
#[serial_test::serial(hlc)]
fn load_insight_thresholds_rejects_invalid_preferences() {
    let conn = test_db();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
        (
            "insight_stalled_window_days",
            "\"definitely_invalid\"",
            "0000000000000_0000_0000000000000000",
            "2026-03-29T00:00:00Z",
        ),
    )
    .expect("insert invalid threshold preference");

    let error = load_insight_thresholds(&conn)
        .expect_err("threshold load should fail")
        .to_string();
    assert!(
        error.contains("insight_stalled_window_days"),
        "unexpected error: {error}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn load_insight_thresholds_rejects_non_positive_preferences() {
    let conn = test_db();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
        (
            "insight_defer_count_min",
            "0",
            "0000000000000_0000_0000000000000000",
            "2026-03-29T00:00:00Z",
        ),
    )
    .expect("insert invalid non-positive threshold");
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
        (
            "insight_stalled_window_days",
            "-3",
            "0000000000000_0000_0000000000000000",
            "2026-03-29T00:00:00Z",
        ),
    )
    .expect("insert invalid negative threshold");

    let error = load_insight_thresholds(&conn)
        .expect_err("threshold load should fail")
        .to_string();
    assert!(
        error.contains("positive integer"),
        "unexpected error: {error}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn load_insight_thresholds_normalizes_reversed_severity_thresholds() {
    let conn = test_db();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
        (
            "insight_overdue_severity_high",
            "2",
            "0000000000000_0000_0000000000000000",
            "2026-03-29T00:00:00Z",
        ),
    )
    .expect("insert reversed high threshold");
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
        (
            "insight_overdue_severity_medium",
            "5",
            "0000000000000_0000_0000000000000000",
            "2026-03-29T00:00:00Z",
        ),
    )
    .expect("insert reversed medium threshold");

    let thresholds = load_insight_thresholds(&conn).expect("threshold load should succeed");
    assert_eq!(thresholds.overdue_severity_high, 5);
    assert_eq!(thresholds.overdue_severity_medium, 2);
}

#[test]
#[serial_test::serial(hlc)]
fn load_insight_thresholds_surfaces_preference_lookup_failures() {
    let conn = test_db();
    conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
        AuthAction::Read {
            table_name: "preferences",
            ..
        } => Authorization::Deny,
        _ => Authorization::Allow,
    }))
    .expect("install authorizer");

    let error = load_insight_thresholds(&conn)
        .expect_err("preferences read failure should surface")
        .to_string();
    assert!(
        error.contains("internal error")
            || error.contains("access to preferences")
            || error.contains("database error"),
        "unexpected error: {error}"
    );
}
