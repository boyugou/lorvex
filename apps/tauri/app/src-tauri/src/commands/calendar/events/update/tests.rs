use super::update_calendar_event_internal;
use crate::error::AppError;
use crate::test_support::test_conn;
use lorvex_domain::Patch;
use lorvex_workflow::calendar_event::{recurrence_skeleton_matches, CalendarEventUpdateInput};
use rusqlite::params;

fn seed_timed_event(conn: &rusqlite::Connection, id: &str) {
    conn.execute(
        "INSERT INTO calendar_events (
            id, title, event_type, timezone, start_date, start_time, end_time,
            all_day, version, created_at, updated_at
         ) VALUES (
            ?1, 'Team sync', 'event', 'America/New_York', '2026-03-07',
            '09:00', '10:00', 0, '0000000000000_0000_a0a0a0a0a0a0a0a0',
            '2026-03-01T08:00:00Z', '2026-03-01T08:00:00Z'
         )",
        params![id],
    )
    .expect("seed timed calendar event");
}

fn update_args(id: &str) -> CalendarEventUpdateInput {
    CalendarEventUpdateInput {
        id: id.to_string(),
        title: None,
        recurrence: Patch::Unset,
        timezone: Patch::Unset,
        start_date: Patch::Unset,
        start_time: Patch::Unset,
        end_date: Patch::Unset,
        end_time: Patch::Unset,
        all_day: None,
        description: Patch::Unset,
        location: Patch::Unset,
        url: Patch::Unset,
        color: Patch::Unset,
        event_type: Patch::Unset,
        person_name: Patch::Unset,
        attendees: Patch::Unset,
    }
}

#[test]
fn update_calendar_event_rejects_dst_skipped_local_time() {
    let conn = test_conn();
    let event_id = "01966a3f-7c8b-7d4e-8f3a-000000000413";
    seed_timed_event(&conn, event_id);
    let mut args = update_args(event_id);
    args.start_date = Patch::Set("2026-03-08".to_string());
    args.start_time = Patch::Set("02:30".to_string());
    args.end_time = Patch::Set("03:30".to_string());

    let error = update_calendar_event_internal(&conn, args, "2026-03-01T09:00:00Z")
        .expect_err("DST-skipped update must be rejected");

    match error {
        AppError::Validation(message) => {
            assert!(
                message.contains("does not exist") && message.contains("America/New_York"),
                "expected shared DST-gap message, got: {message}"
            );
        }
        other => panic!("expected Validation, got {other:?}"),
    }
}

#[test]
fn update_calendar_event_accepts_ambiguous_with_warning() {
    let conn = test_conn();
    let event_id = "01966a3f-7c8b-7d4e-8f3a-000000000414";
    seed_timed_event(&conn, event_id);
    let mut args = update_args(event_id);
    args.start_date = Patch::Set("2026-11-01".to_string());
    args.start_time = Patch::Set("01:30".to_string());
    args.end_time = Patch::Set("02:30".to_string());

    let event = update_calendar_event_internal(&conn, args, "2026-10-20T09:00:00Z")
        .expect("ambiguous wall-clock update must be accepted");

    assert_eq!(event.start_time.as_deref(), Some("01:30"));
    let (level, source, message, details): (String, String, String, String) = conn
        .query_row(
            "SELECT level, source, message, details FROM error_logs
             WHERE source = 'calendar_events.dst_ambiguous'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("one error_logs row for DST ambiguity");
    assert_eq!(level, "warn");
    assert_eq!(source, "calendar_events.dst_ambiguous");
    assert!(
        message.contains("America/New_York") && message.contains("01:30"),
        "unexpected warn message: {message}"
    );
    assert!(
        details.contains(event_id),
        "warning details should point at event id, got: {details}"
    );
}

#[test]
fn until_extension_preserves_skeleton() {
    let old = r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO"],"UNTIL":"20260101"}"#;
    let new = r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO"],"UNTIL":"20270101"}"#;
    assert!(recurrence_skeleton_matches(old, new));
}

#[test]
fn count_change_preserves_skeleton() {
    let old = r#"{"FREQ":"DAILY","INTERVAL":1,"COUNT":5}"#;
    let new = r#"{"FREQ":"DAILY","INTERVAL":1,"COUNT":10}"#;
    assert!(recurrence_skeleton_matches(old, new));
}

#[test]
fn untimed_to_bounded_still_matches_skeleton() {
    // Adding UNTIL to a previously-unbounded recurrence preserves
    // the grid; existing EXDATE must survive.
    let old = r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO"]}"#;
    let new = r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO"],"UNTIL":"20270101"}"#;
    assert!(recurrence_skeleton_matches(old, new));
}

#[test]
fn freq_change_breaks_skeleton() {
    let old = r#"{"FREQ":"WEEKLY","INTERVAL":1}"#;
    let new = r#"{"FREQ":"DAILY","INTERVAL":1}"#;
    assert!(!recurrence_skeleton_matches(old, new));
}

#[test]
fn byday_change_breaks_skeleton() {
    let old = r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO"]}"#;
    let new = r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["TU"]}"#;
    assert!(!recurrence_skeleton_matches(old, new));
}

#[test]
fn interval_change_breaks_skeleton() {
    let old = r#"{"FREQ":"WEEKLY","INTERVAL":1}"#;
    let new = r#"{"FREQ":"WEEKLY","INTERVAL":2}"#;
    assert!(!recurrence_skeleton_matches(old, new));
}

#[test]
fn unparseable_input_falls_back_to_clearing() {
    assert!(!recurrence_skeleton_matches(
        "not json",
        r#"{"FREQ":"DAILY"}"#
    ));
    assert!(!recurrence_skeleton_matches(
        r#"{"FREQ":"DAILY"}"#,
        "not json"
    ));
}
