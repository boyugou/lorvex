use lorvex_workflow::task_create::should_store_raw_input;
use rusqlite::hooks::{AuthAction, AuthContext, Authorization};
use rusqlite::Connection;

fn test_db() -> Connection {
    lorvex_store::open_db_in_memory().expect("open in-memory db")
}

#[test]
#[serial_test::serial(hlc)]
fn should_store_raw_input_defaults_true_when_preference_missing() {
    let conn = test_db();
    assert!(should_store_raw_input(&conn).expect("missing preference should default true"));
}

#[test]
#[serial_test::serial(hlc)]
fn should_store_raw_input_reads_json_boolean_preference() {
    let conn = test_db();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
        (
            lorvex_domain::preference_keys::PREF_RECORD_RAW_INPUT,
            "false",
            "0000000000000_0000_0000000000000000",
            "2026-03-29T00:00:00Z",
        ),
    )
    .expect("insert preference");

    assert!(!should_store_raw_input(&conn).expect("valid preference should parse"));
}

#[test]
#[serial_test::serial(hlc)]
fn should_store_raw_input_surfaces_preference_lookup_failures() {
    let conn = test_db();
    conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
        AuthAction::Read {
            table_name: "preferences",
            ..
        } => Authorization::Deny,
        _ => Authorization::Allow,
    }))
    .expect("install authorizer");

    let error = should_store_raw_input(&conn)
        .expect_err("preference lookup failures should surface")
        .to_string();
    assert!(
        error.contains("record_raw_input")
            || error.contains("preferences")
            || error.contains("not authorized"),
        "unexpected error: {error}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn should_store_raw_input_rejects_malformed_preference() {
    let conn = test_db();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES (?1, ?2, ?3, ?4)",
        (
            lorvex_domain::preference_keys::PREF_RECORD_RAW_INPUT,
            "\"not-a-bool\"",
            "0000000000000_0000_0000000000000000",
            "2026-03-29T00:00:00Z",
        ),
    )
    .expect("insert malformed preference");

    let error = should_store_raw_input(&conn)
        .expect_err("malformed record_raw_input preference should fail")
        .to_string();
    assert!(
        error.contains("record_raw_input"),
        "unexpected error: {error}"
    );
}
