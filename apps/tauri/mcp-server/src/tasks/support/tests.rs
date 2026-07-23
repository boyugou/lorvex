// `normalize_task_status` was deleted alongside its
// last consumer; status validation now lives in serde via the typed
// `TaskStatusValue` enum. The companion test
// `normalize_task_status_rejects_invalid_values` is replaced by
// `update_task_args_rejects_status_outside_allowed_enum_at_parse` in
// `server::tests::tasks::read_and_mutation_validation`.
use super::{
    normalize_due_date_input, normalize_due_date_input_for_conn, recurrence_base_date_for_conn_at,
};
use crate::tasks::support::normalization::parse_flexible_due_date_for_timezone;
use chrono::{FixedOffset, TimeZone};
use rusqlite::Connection;

fn setup_test_conn() -> Connection {
    let conn = Connection::open_in_memory().expect("open in-memory db");
    lorvex_store::migration::apply_migrations(&conn, &lorvex_store::schema::all_migrations())
        .expect("apply migrations");
    conn
}

#[test]
#[serial_test::serial(hlc)]
fn normalize_due_date_input_resolves_aliases() {
    assert!(normalize_due_date_input("today".to_string()).is_ok());
    assert!(normalize_due_date_input("tomorrow".to_string()).is_ok());
    assert!(normalize_due_date_input("yesterday".to_string()).is_ok());
    assert_eq!(
        normalize_due_date_input("2026-04-03".to_string()).expect("canonical"),
        "2026-04-03"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn normalize_due_date_input_converts_rfc3339_to_target_local_calendar_day() {
    let pacific = FixedOffset::west_opt(8 * 60 * 60).expect("offset");
    assert_eq!(
        parse_flexible_due_date_for_timezone("2026-03-08T01:00:00Z", &pacific)
            .expect("normalize rfc3339"),
        "2026-03-07"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn normalize_due_date_input_for_conn_uses_timezone_preference_calendar_day() {
    let conn = setup_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES ('timezone', '\"America/Los_Angeles\"', '0000000000000_0000_0000000000000000', '2026-03-08T01:00:00Z')",
        [],
    )
    .expect("insert timezone preference");

    assert_eq!(
        normalize_due_date_input_for_conn(&conn, "2026-03-08T01:00:00Z".to_string())
            .expect("normalize due date"),
        "2026-03-07"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn recurrence_base_date_for_conn_uses_timezone_preference_for_undated_tasks() {
    let conn = setup_test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES ('timezone', '\"America/Los_Angeles\"', '0000000000000_0000_0000000000000000', '2026-03-08T01:00:00Z')",
        [],
    )
    .expect("insert timezone preference");
    let now = chrono::Utc
        .with_ymd_and_hms(2026, 3, 8, 1, 0, 0)
        .single()
        .expect("construct UTC instant");

    assert_eq!(
        recurrence_base_date_for_conn_at(&conn, None, now).expect("resolve recurrence base"),
        "2026-03-07"
    );
    assert_eq!(
        recurrence_base_date_for_conn_at(&conn, Some("2026-03-01"), now)
            .expect("preserve explicit due date"),
        "2026-03-01"
    );
}
