//! The MCP boundary delegates attendee sub-table writes to
//! `lorvex_workflow::calendar_event::materialize_attendees`. The
//! tests here pin two layers:
//!
//! - the JSON deserializer that gates PARTSTAT spellings on the way
//!   into the MCP contract (the typed `AttendeeStatusArg` enum), and
//! - the shared materializer's reject paths (over-cap name, over-cap
//!   email, empty-list-clears) — exercised through the workflow
//!   `materialize_attendees` entry point that the surface adopts.

use super::*;
use crate::contract::{AttendeeStatusArg, MAX_SHORT_TEXT_LENGTH};
use crate::db::open_database_for_path;
use lorvex_domain::AttendeeStatus;
use lorvex_workflow::calendar_event::{
    materialize_attendees, AttendeeShadowInput, CalendarEventOpError,
};
use tempfile::tempdir;

fn open_temp_db() -> Connection {
    let dir = tempdir().expect("create tempdir");
    let db_path = dir.path().join("db.sqlite");
    let conn = open_database_for_path(&db_path).expect("open temp db");
    let _leaked = Box::leak(Box::new(dir));
    conn
}

fn seed_event(conn: &Connection, id: &str) {
    conn.execute(
        "INSERT INTO calendar_events (id, title, event_type, start_date, all_day, version, created_at, updated_at) \
         VALUES (?1, 'Standup', 'event', '2026-04-01', 0, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z', '2026-04-01T08:00:00Z')",
        [id],
    )
    .expect("seed event");
}

fn shadow(
    email: &str,
    name: Option<&str>,
    status: Option<AttendeeStatusArg>,
) -> AttendeeShadowInput {
    AttendeeShadowInput {
        email: email.to_string(),
        name: name.map(str::to_string),
        status: status.map(AttendeeStatus::from),
    }
}

/// Run `materialize_attendees` inside the active-transaction envelope
/// the production callers always provide. The materializer
/// `debug_assert!`s `!conn.is_autocommit()` (#4530) so calling it
/// directly against a freshly-opened connection trips in test builds.
fn materialize_in_tx(
    conn: &Connection,
    event_id: &lorvex_domain::EventId,
    attendees: &[AttendeeShadowInput],
) -> Result<(), CalendarEventOpError> {
    conn.execute_batch("BEGIN IMMEDIATE").expect("begin tx");
    let result = materialize_attendees(conn, event_id, attendees);
    conn.execute_batch(if result.is_ok() { "COMMIT" } else { "ROLLBACK" })
        .expect("close tx");
    result
}

#[test]
#[serial_test::serial(hlc)]
fn deserializer_rejects_unknown_partstat_at_json_boundary() {
    let raw = r#"{"email":"a@example.com","status":"maybe"}"#;
    let err = serde_json::from_str::<AttendeeInput>(raw).expect_err("unknown PARTSTAT must fail");
    let msg = err.to_string();
    assert!(
        msg.contains("maybe") || msg.contains("variant"),
        "deserializer error must name the offending value, got: {msg}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn deserializer_rejects_legacy_underscore_form_of_needs_action() {
    let raw = r#"{"email":"a@example.com","status":"needs_action"}"#;
    serde_json::from_str::<AttendeeInput>(raw)
        .expect_err("underscore form must be rejected by the typed enum");
}

#[test]
#[serial_test::serial(hlc)]
fn deserializer_accepts_every_canonical_status() {
    for status in ["accepted", "declined", "tentative", "needs-action"] {
        let raw = format!(r#"{{"email":"a@example.com","status":"{status}"}}"#);
        let parsed: AttendeeInput = serde_json::from_str(&raw)
            .unwrap_or_else(|e| panic!("status {status:?} should parse, got: {e:?}"));
        assert!(parsed.status.is_some(), "status {status:?} must round-trip");
    }
}

#[test]
#[serial_test::serial(hlc)]
fn accepts_every_canonical_status() {
    let conn = open_temp_db();
    seed_event(&conn, "evt-1");
    for status in [
        AttendeeStatusArg::Accepted,
        AttendeeStatusArg::Declined,
        AttendeeStatusArg::Tentative,
        AttendeeStatusArg::NeedsAction,
    ] {
        let attendees = vec![shadow("a@example.com", None, Some(status))];
        materialize_in_tx(
            &conn,
            &lorvex_domain::EventId::from_trusted("evt-1".to_string()),
            &attendees,
        )
        .unwrap_or_else(|e| panic!("status {status:?} should be accepted, got: {e:?}"));
    }
}

#[test]
#[serial_test::serial(hlc)]
fn rejects_attendee_name_over_max_length() {
    let conn = open_temp_db();
    seed_event(&conn, "evt-1");
    let huge = "a".repeat(MAX_SHORT_TEXT_LENGTH + 1);
    let attendees = vec![shadow("a@example.com", Some(&huge), None)];
    let err = materialize_in_tx(
        &conn,
        &lorvex_domain::EventId::from_trusted("evt-1".to_string()),
        &attendees,
    )
    .expect_err("over-cap name must be rejected");
    match err {
        CalendarEventOpError::Validation(msg) => assert!(msg.contains("attendee name")),
        other => panic!("expected Validation, got: {other:?}"),
    }
}

#[test]
#[serial_test::serial(hlc)]
fn rejects_attendee_email_over_max_length() {
    let conn = open_temp_db();
    seed_event(&conn, "evt-1");
    let huge = format!("{}@example.com", "a".repeat(MAX_SHORT_TEXT_LENGTH));
    let attendees = vec![shadow(&huge, None, None)];
    let err = materialize_in_tx(
        &conn,
        &lorvex_domain::EventId::from_trusted("evt-1".to_string()),
        &attendees,
    )
    .expect_err("over-cap email must be rejected");
    match err {
        CalendarEventOpError::Validation(msg) => assert!(msg.contains("attendee email")),
        other => panic!("expected Validation, got: {other:?}"),
    }
}

#[test]
#[serial_test::serial(hlc)]
fn accepts_name_and_email_at_length_boundary() {
    let conn = open_temp_db();
    seed_event(&conn, "evt-1");
    let name_at_limit = "a".repeat(MAX_SHORT_TEXT_LENGTH);
    let email_at_limit: String = "a".repeat(MAX_SHORT_TEXT_LENGTH - "@x.co".len()) + "@x.co";
    assert_eq!(email_at_limit.chars().count(), MAX_SHORT_TEXT_LENGTH);
    let attendees = vec![shadow(
        &email_at_limit,
        Some(&name_at_limit),
        Some(AttendeeStatusArg::Accepted),
    )];
    materialize_in_tx(
        &conn,
        &lorvex_domain::EventId::from_trusted("evt-1".to_string()),
        &attendees,
    )
    .expect("inputs at the cap boundary must be accepted");
}

#[test]
#[serial_test::serial(hlc)]
fn empty_attendees_list_clears_existing_rows() {
    let conn = open_temp_db();
    seed_event(&conn, "evt-1");
    materialize_in_tx(
        &conn,
        &lorvex_domain::EventId::from_trusted("evt-1".to_string()),
        &[shadow(
            "a@example.com",
            Some("Alice"),
            Some(AttendeeStatusArg::Accepted),
        )],
    )
    .expect("seed attendee");

    materialize_in_tx(
        &conn,
        &lorvex_domain::EventId::from_trusted("evt-1".to_string()),
        &[],
    )
    .expect("empty list should clear");
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM calendar_event_attendees WHERE event_id = 'evt-1'",
            [],
            |row| row.get(0),
        )
        .expect("count");
    assert_eq!(count, 0);
}
