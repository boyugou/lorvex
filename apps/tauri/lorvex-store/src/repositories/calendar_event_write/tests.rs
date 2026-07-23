use super::*;
use crate::test_support::test_conn;

#[test]
fn create_and_delete_calendar_event() {
    let conn = test_conn();
    let params = CalendarEventCreateParams {
        id: "evt-1",
        title: "Meeting",
        description: Some("Team sync"),
        recurrence: None,
        recurrence_exceptions: None,
        timezone: Some("America/New_York"),
        start_date: "2026-03-27",
        start_time: Some("10:00"),
        end_date: Some("2026-03-27"),
        end_time: Some("11:00"),
        all_day: false,
        location: Some("Room A"),
        url: None,
        color: Some("#ff0000"),
        event_type: "event",
        person_name: None,
        version: "0000000000000_0000_0000000000000000",
        now: "2026-03-27T00:00:00.000Z",
    };
    create_calendar_event(&conn, &params).unwrap();

    // Verify exists
    let title: String = conn
        .query_row(
            "SELECT title FROM calendar_events WHERE id = ?1",
            ["evt-1"],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(title, "Meeting");

    let stale_delete =
        delete_calendar_event_lww(&conn, "evt-1", "0000000000000_0000_0000000000000000")
            .unwrap_err();
    match stale_delete {
        StoreError::StaleVersion { entity, id } => {
            assert_eq!(entity, ENTITY_CALENDAR_EVENT);
            assert_eq!(id, "evt-1");
        }
        other => panic!("expected StaleVersion, got {other:?}"),
    }

    // Delete — `usize` shape.
    assert_eq!(
        delete_calendar_event_lww(&conn, "evt-1", "0000000000001_0000_0000000000000000").unwrap(),
        1
    );
    assert_eq!(
        delete_calendar_event_lww(&conn, "evt-1", "0000000000002_0000_0000000000000000").unwrap(),
        0
    );
}

#[test]
fn apply_update_partial_fields() {
    let conn = test_conn();
    let create = CalendarEventCreateParams {
        id: "evt-2",
        title: "Old Title",
        description: None,
        recurrence: None,
        recurrence_exceptions: None,
        timezone: None,
        start_date: "2026-04-01",
        start_time: None,
        end_date: None,
        end_time: None,
        all_day: true,
        location: None,
        url: None,
        color: None,
        event_type: "event",
        person_name: None,
        version: "0000000000000_0000_0000000000000000",
        now: "2026-03-27T00:00:00.000Z",
    };
    create_calendar_event(&conn, &create).unwrap();

    let patch = CalendarEventUpdatePatch {
        event_id: "evt-2",
        title: Some("New Title"),
        description: Patch::Set("Added desc"),
        version: "0000000000001_0000_0000000000000000",
        now: "2026-03-27T01:00:00.000Z",
        ..Default::default()
    };
    apply_calendar_event_update(&conn, &patch).unwrap();

    let (title, desc): (String, Option<String>) = conn
        .query_row(
            "SELECT title, description FROM calendar_events WHERE id = ?1",
            ["evt-2"],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(title, "New Title");
    assert_eq!(desc.as_deref(), Some("Added desc"));
}

#[test]
fn apply_update_clear_nullable_field() {
    let conn = test_conn();
    let create = CalendarEventCreateParams {
        id: "evt-3",
        title: "With Location",
        description: None,
        recurrence: None,
        recurrence_exceptions: None,
        timezone: None,
        start_date: "2026-04-01",
        start_time: None,
        end_date: None,
        end_time: None,
        all_day: true,
        location: Some("Room B"),
        url: None,
        color: None,
        event_type: "event",
        person_name: None,
        version: "0000000000000_0000_0000000000000000",
        now: "2026-03-27T00:00:00.000Z",
    };
    create_calendar_event(&conn, &create).unwrap();

    // Clear location to NULL
    let patch = CalendarEventUpdatePatch {
        event_id: "evt-3",
        location: Patch::Clear,
        version: "0000000000001_0000_0000000000000000",
        now: "2026-03-27T01:00:00.000Z",
        ..Default::default()
    };
    apply_calendar_event_update(&conn, &patch).unwrap();

    let location: Option<String> = conn
        .query_row(
            "SELECT location FROM calendar_events WHERE id = ?1",
            ["evt-3"],
            |row| row.get(0),
        )
        .unwrap();
    assert!(location.is_none());
}

#[test]
fn delete_nonexistent_returns_zero() {
    let conn = test_conn();
    assert_eq!(
        delete_calendar_event_lww(&conn, "nonexistent", "0000000000001_0000_0000000000000000",)
            .unwrap(),
        0
    );
}

/// #2941-M2: create rejects unknown event_type with a friendly message
/// rather than a SQL CHECK violation deep in rusqlite.
#[test]
fn create_rejects_unknown_event_type() {
    let conn = test_conn();
    let bad = CalendarEventCreateParams {
        id: "evt-bad",
        title: "Bad",
        description: None,
        recurrence: None,
        recurrence_exceptions: None,
        timezone: None,
        start_date: "2026-04-01",
        start_time: None,
        end_date: None,
        end_time: None,
        all_day: true,
        location: None,
        url: None,
        color: None,
        event_type: "meeting",
        person_name: None,
        version: "0000000000000_0000_0000000000000000",
        now: "2026-04-01T00:00:00.000Z",
    };
    let err = create_calendar_event(&conn, &bad).unwrap_err();
    match err {
        StoreError::Validation(msg) => assert!(msg.contains("must be one of"), "{msg}"),
        other => panic!("expected Validation, got {other:?}"),
    }
}

/// #2941-M2: patch rejects unknown event_type at the entry, before SQL.
#[test]
fn apply_update_rejects_unknown_event_type() {
    let conn = test_conn();
    let create = CalendarEventCreateParams {
        id: "evt-canonical",
        title: "OK",
        description: None,
        recurrence: None,
        recurrence_exceptions: None,
        timezone: None,
        start_date: "2026-04-01",
        start_time: None,
        end_date: None,
        end_time: None,
        all_day: true,
        location: None,
        url: None,
        color: None,
        event_type: "event",
        person_name: None,
        version: "0000000000000_0000_0000000000000000",
        now: "2026-04-01T00:00:00.000Z",
    };
    create_calendar_event(&conn, &create).unwrap();

    let bad_patch = CalendarEventUpdatePatch {
        event_id: "evt-canonical",
        event_type: Patch::Set("meeting"),
        version: "0000000000001_0000_0000000000000000",
        now: "2026-04-01T01:00:00.000Z",
        ..Default::default()
    };
    let err = apply_calendar_event_update(&conn, &bad_patch).unwrap_err();
    match err {
        StoreError::Validation(msg) => assert!(msg.contains("must be one of"), "{msg}"),
        other => panic!("expected Validation, got {other:?}"),
    }
}
