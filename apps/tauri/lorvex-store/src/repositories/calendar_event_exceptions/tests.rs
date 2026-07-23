use super::*;
use crate::open_db_in_memory;
use crate::repositories::calendar_event_write::{create_calendar_event, CalendarEventCreateParams};
use lorvex_domain::EventId;

fn evt(id: &str) -> EventId {
    EventId::from_trusted(id.to_string())
}

fn setup_recurring_event(conn: &Connection) {
    let params = CalendarEventCreateParams {
        id: "evt-r1",
        title: "Daily Standup",
        description: None,
        recurrence: Some(r#"{"FREQ":"DAILY","INTERVAL":1}"#),
        recurrence_exceptions: None,
        timezone: Some("UTC"),
        start_date: "2026-03-20",
        start_time: Some("09:00"),
        end_date: Some("2026-03-20"),
        end_time: Some("09:30"),
        all_day: false,
        location: None,
        url: None,
        color: None,
        event_type: "event",
        person_name: None,
        version: "v0",
        now: "2026-03-20T00:00:00Z",
    };
    create_calendar_event(conn, &params).unwrap();
}

fn setup_non_recurring_event(conn: &Connection) {
    let params = CalendarEventCreateParams {
        id: "evt-nr1",
        title: "One-off Meeting",
        description: None,
        recurrence: None,
        recurrence_exceptions: None,
        timezone: Some("UTC"),
        start_date: "2026-03-25",
        start_time: Some("14:00"),
        end_date: Some("2026-03-25"),
        end_time: Some("15:00"),
        all_day: false,
        location: None,
        url: None,
        color: None,
        event_type: "event",
        person_name: None,
        version: "v0",
        now: "2026-03-25T00:00:00Z",
    };
    create_calendar_event(conn, &params).unwrap();
}

#[test]
fn add_exception_to_recurring_event() {
    let conn = open_db_in_memory().unwrap();
    setup_recurring_event(&conn);

    let json = add_recurrence_exception(
        &conn,
        &evt("evt-r1"),
        "2026-03-25",
        "v1",
        "2026-03-27T12:00:00Z",
    )
    .unwrap();

    let parsed: Vec<String> = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed, vec!["2026-03-25"]);

    // Verify DB
    let (exc, ver): (Option<String>, String) = conn
        .query_row(
            "SELECT (SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]') \
         FROM calendar_event_recurrence_exceptions WHERE event_id = calendar_events.id), \
        version FROM calendar_events WHERE id = 'evt-r1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(exc.as_deref(), Some(&json[..]));
    assert_eq!(ver, "v1");
}

#[test]
fn add_exception_sorts_and_deduplicates() {
    let conn = open_db_in_memory().unwrap();
    setup_recurring_event(&conn);

    add_recurrence_exception(
        &conn,
        &evt("evt-r1"),
        "2026-03-25",
        "v1",
        "2026-03-27T12:00:00Z",
    )
    .unwrap();
    add_recurrence_exception(
        &conn,
        &evt("evt-r1"),
        "2026-03-22",
        "v2",
        "2026-03-27T12:01:00Z",
    )
    .unwrap();

    let exc: String = conn
        .query_row(
            "SELECT (SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]') \
         FROM calendar_event_recurrence_exceptions WHERE event_id = calendar_events.id) \
        FROM calendar_events WHERE id = 'evt-r1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    let parsed: Vec<String> = serde_json::from_str(&exc).unwrap();
    assert_eq!(parsed, vec!["2026-03-22", "2026-03-25"]);
}

#[test]
fn add_duplicate_exception_returns_error() {
    let conn = open_db_in_memory().unwrap();
    setup_recurring_event(&conn);

    add_recurrence_exception(
        &conn,
        &evt("evt-r1"),
        "2026-03-25",
        "v1",
        "2026-03-27T12:00:00Z",
    )
    .unwrap();
    let result = add_recurrence_exception(
        &conn,
        &evt("evt-r1"),
        "2026-03-25",
        "v2",
        "2026-03-27T12:01:00Z",
    );
    let err = result.unwrap_err();
    assert!(matches!(err, StoreError::Validation(_)));
    assert!(err.to_string().contains("Exception already exists"));
}

#[test]
fn add_exception_to_non_recurring_returns_error() {
    let conn = open_db_in_memory().unwrap();
    setup_non_recurring_event(&conn);

    let result = add_recurrence_exception(
        &conn,
        &evt("evt-nr1"),
        "2026-03-25",
        "v1",
        "2026-03-27T12:00:00Z",
    );
    let err = result.unwrap_err();
    assert!(matches!(err, StoreError::Validation(_)));
    assert!(err.to_string().contains("not recurring"));
}

#[test]
fn add_exception_before_start_date_returns_error() {
    let conn = open_db_in_memory().unwrap();
    setup_recurring_event(&conn);

    let result = add_recurrence_exception(
        &conn,
        &evt("evt-r1"),
        "2026-03-19",
        "v1",
        "2026-03-27T12:00:00Z",
    );
    let err = result.unwrap_err();
    assert!(matches!(err, StoreError::Validation(_)));
    assert!(err.to_string().contains("event start date"));
}

#[test]
fn add_exception_for_nonexistent_event_returns_error() {
    let conn = open_db_in_memory().unwrap();
    let result = add_recurrence_exception(
        &conn,
        &evt("nonexistent"),
        "2026-03-25",
        "v1",
        "2026-03-27T12:00:00Z",
    );
    assert!(matches!(
        result,
        Err(StoreError::NotFound {
            entity: ENTITY_CALENDAR_EVENT,
            ..
        })
    ));
}

#[test]
fn add_exception_invalid_date_format_returns_error() {
    let conn = open_db_in_memory().unwrap();
    setup_recurring_event(&conn);

    let result = add_recurrence_exception(
        &conn,
        &evt("evt-r1"),
        "not-a-date",
        "v1",
        "2026-03-27T12:00:00Z",
    );
    let err = result.unwrap_err();
    assert!(matches!(err, StoreError::Validation(_)));
    assert!(err.to_string().contains("invalid date format"));
}

#[test]
fn add_exception_non_occurrence_returns_error() {
    let conn = open_db_in_memory().unwrap();
    // Weekly event, only Fridays
    let params = CalendarEventCreateParams {
        id: "evt-weekly",
        title: "Weekly Friday",
        description: None,
        recurrence: Some(r#"{"FREQ":"WEEKLY","INTERVAL":1}"#),
        recurrence_exceptions: None,
        timezone: Some("UTC"),
        start_date: "2026-03-20", // a Friday
        start_time: Some("10:00"),
        end_date: Some("2026-03-20"),
        end_time: Some("11:00"),
        all_day: false,
        location: None,
        url: None,
        color: None,
        event_type: "event",
        person_name: None,
        version: "v0",
        now: "2026-03-20T00:00:00Z",
    };
    create_calendar_event(&conn, &params).unwrap();

    // 2026-03-25 is a Wednesday, not a Friday occurrence
    let result = add_recurrence_exception(
        &conn,
        &evt("evt-weekly"),
        "2026-03-25",
        "v1",
        "2026-03-27T12:00:00Z",
    );
    let err = result.unwrap_err();
    assert!(matches!(err, StoreError::Validation(_)));
    assert!(err
        .to_string()
        .contains("not a valid occurrence of the recurrence pattern"));
}

#[test]
fn remove_exception_succeeds() {
    let conn = open_db_in_memory().unwrap();
    setup_recurring_event(&conn);

    add_recurrence_exception(
        &conn,
        &evt("evt-r1"),
        "2026-03-25",
        "v1",
        "2026-03-27T12:00:00Z",
    )
    .unwrap();
    add_recurrence_exception(
        &conn,
        &evt("evt-r1"),
        "2026-03-22",
        "v2",
        "2026-03-27T12:01:00Z",
    )
    .unwrap();

    let result = remove_recurrence_exception(
        &conn,
        &evt("evt-r1"),
        "2026-03-25",
        "v3",
        "2026-03-27T12:02:00Z",
    )
    .unwrap();
    let json = result.unwrap();
    let parsed: Vec<String> = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed, vec!["2026-03-22"]);
}

#[test]
fn remove_last_exception_sets_null() {
    let conn = open_db_in_memory().unwrap();
    setup_recurring_event(&conn);

    add_recurrence_exception(
        &conn,
        &evt("evt-r1"),
        "2026-03-25",
        "v1",
        "2026-03-27T12:00:00Z",
    )
    .unwrap();
    let result = remove_recurrence_exception(
        &conn,
        &evt("evt-r1"),
        "2026-03-25",
        "v2",
        "2026-03-27T12:01:00Z",
    )
    .unwrap();
    assert!(result.is_none());

    // Verify DB has NULL
    let exc: Option<String> = conn
        .query_row(
            "SELECT (SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]') \
         FROM calendar_event_recurrence_exceptions WHERE event_id = calendar_events.id) \
        FROM calendar_events WHERE id = 'evt-r1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert!(exc.is_none());
}

#[test]
fn remove_nonexistent_exception_returns_error() {
    let conn = open_db_in_memory().unwrap();
    setup_recurring_event(&conn);

    let result = remove_recurrence_exception(
        &conn,
        &evt("evt-r1"),
        "2026-03-25",
        "v1",
        "2026-03-27T12:00:00Z",
    );
    let err = result.unwrap_err();
    assert!(matches!(err, StoreError::Validation(_)));
    assert!(err.to_string().contains("not in the exceptions list"));
}

#[test]
fn remove_from_nonexistent_event_returns_error() {
    let conn = open_db_in_memory().unwrap();
    let result = remove_recurrence_exception(
        &conn,
        &evt("nonexistent"),
        "2026-03-25",
        "v1",
        "2026-03-27T12:00:00Z",
    );
    assert!(matches!(
        result,
        Err(StoreError::NotFound {
            entity: ENTITY_CALENDAR_EVENT,
            ..
        })
    ));
}

#[test]
fn empty_version_rejected() {
    let conn = open_db_in_memory().unwrap();
    setup_recurring_event(&conn);

    let result = add_recurrence_exception(
        &conn,
        &evt("evt-r1"),
        "2026-03-25",
        "",
        "2026-03-28T00:00:00Z",
    );
    assert!(result.is_err());
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("version must not be empty"));

    let result = remove_recurrence_exception(
        &conn,
        &evt("evt-r1"),
        "2026-03-25",
        "",
        "2026-03-28T00:00:00Z",
    );
    assert!(result.is_err());
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("version must not be empty"));

    // Whitespace-only should also be rejected
    let result = add_recurrence_exception(
        &conn,
        &evt("evt-r1"),
        "2026-03-25",
        "  ",
        "2026-03-28T00:00:00Z",
    );
    assert!(result.is_err());
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("version must not be empty"));
}

// Pre-#4585 the exception list lived as a free-form JSON TEXT
// column, so a manually-corrupted row could ship malformed JSON
// into the parser. The list now normalizes into
// `calendar_event_recurrence_exceptions`, with each row a bare
// `YYYY-MM-DD` date string built up by `json_group_array` on
// read — the parser can no longer observe malformed JSON. The
// two `*_rejects_malformed_existing_exceptions_json` regressions
// have been retired: the bug class they pinned is no longer
// reachable at the storage layer.
