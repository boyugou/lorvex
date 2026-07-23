use super::super::*;

#[test]
fn import_rejects_invalid_canonical_calendar_event_type_before_db_insert() {
    let conn = open_db_in_memory().unwrap();
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("bad-calendar-event-type.zip");

    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_CALENDAR_EVENT,
            "entity_id": "evt-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "evt-1",
                "title": "Offsite",
                "start_date": "2026-03-29",
                "all_day": true,
                "event_type": "meeting",
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    match err {
        ImportError::InvalidPayload(message) => {
            assert!(message.contains("calendar_event payload"));
            assert!(message.contains("event_type"));
            assert!(message.contains("event, birthday, anniversary, memorial"));
        }
        other => panic!(
            "expected InvalidPayload for invalid canonical calendar event type, got {other:?}"
        ),
    }
}

#[test]
fn import_rejects_legacy_underscore_attendee_status_before_db_insert() {
    let conn = open_db_in_memory().unwrap();
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("bad-attendee-status.zip");

    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_CALENDAR_EVENT,
            "entity_id": "evt-legacy-attendee-status",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "evt-legacy-attendee-status",
                "title": "Offsite",
                "start_date": "2026-03-29",
                "all_day": true,
                "event_type": "event",
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z",
                "attendees": [
                    { "email": "alice@example.com", "status": "needs_action" }
                ]
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    match err {
        ImportError::InvalidPayload(message) => {
            assert!(message.contains("calendar_event payload.attendees[0].status"));
            assert!(message.contains("needs_action"));
            assert!(message.contains("not a recognized RFC 5545 PARTSTAT"));
        }
        other => panic!("expected InvalidPayload for legacy attendee status, got {other:?}"),
    }

    let attendee_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM calendar_event_attendees", [], |row| {
            row.get(0)
        })
        .expect("count attendees");
    assert_eq!(
        attendee_count, 0,
        "legacy attendee status must fail before materializing attendee rows"
    );
}

#[test]
fn import_rejects_malformed_calendar_event_boundary_fields_before_db_insert() {
    for (field, value) in [
        ("start_date", "tomorrow"),
        ("end_date", "03-30-2026"),
        ("start_time", "25:00"),
        ("end_time", "not-a-time"),
    ] {
        let conn = open_db_in_memory().unwrap();
        let dir = tempdir().unwrap();
        let zip_path = dir.path().join(format!("bad-calendar-event-{field}.zip"));

        let mut payload = serde_json::json!({
            "id": format!("evt-bad-{field}"),
            "title": "Offsite",
            "start_date": "2026-03-29",
            "all_day": false,
            "event_type": "event",
            "created_at": "2026-03-29T00:00:00Z",
            "updated_at": "2026-03-29T00:00:00Z"
        });
        payload[field] = serde_json::json!(value);
        if field == "end_time" {
            payload["start_time"] = serde_json::json!("09:00");
        }

        write_import_zip(
            &zip_path,
            &[serde_json::json!({
                "entity_type": ENTITY_CALENDAR_EVENT,
                "entity_id": format!("evt-bad-{field}"),
                "version": "1711234567890_0001_deadbeefdeadbeef",
                "payload": payload
            })],
            &[],
            &[],
            &[],
            &[],
        );

        let err = import_from_zip(&conn, &zip_path).unwrap_err();
        match err {
            ImportError::InvalidPayload(message) => {
                assert!(message.contains(field), "got: {message}");
            }
            other => panic!("expected InvalidPayload for malformed {field}, got {other:?}"),
        }

        let event_count: i64 = conn
            .query_row("SELECT COUNT(*) FROM calendar_events", [], |row| row.get(0))
            .expect("count calendar events");
        assert_eq!(
            event_count, 0,
            "malformed {field} must fail before inserting a calendar event row"
        );
    }
}

#[test]
fn import_rejects_all_day_calendar_event_with_times_before_db_insert() {
    let conn = open_db_in_memory().unwrap();
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("bad-calendar-event-all-day-time.zip");

    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_CALENDAR_EVENT,
            "entity_id": "evt-bad-all-day-time",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "evt-bad-all-day-time",
                "title": "Offsite",
                "start_date": "2026-03-29",
                "start_time": "09:00",
                "all_day": true,
                "event_type": "event",
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    match err {
        ImportError::InvalidPayload(message) => {
            assert!(message.contains("all_day=1"), "got: {message}");
            assert!(message.contains("start_time"), "got: {message}");
        }
        other => panic!("expected InvalidPayload for all-day event with time, got {other:?}"),
    }

    let event_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM calendar_events", [], |row| row.get(0))
        .expect("count calendar events");
    assert_eq!(
        event_count, 0,
        "all-day/time mismatch must fail before inserting a calendar event row"
    );
}

#[test]
fn import_preserves_calendar_event_override_linkage_fields() {
    let conn = open_db_in_memory().unwrap();
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("calendar-event-override.zip");

    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_CALENDAR_EVENT,
            "entity_id": "evt-override",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "evt-override",
                "title": "Moved occurrence",
                "start_date": "2026-03-29",
                "all_day": true,
                "event_type": "event",
                "series_id": "evt-series",
                "recurrence_instance_date": "2026-03-29",
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    import_from_zip(&conn, &zip_path).unwrap();
    let (series_id, recurrence_instance_date): (Option<String>, Option<String>) = conn
        .query_row(
            "SELECT series_id, recurrence_instance_date
               FROM calendar_events
              WHERE id = 'evt-override'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(series_id.as_deref(), Some("evt-series"));
    assert_eq!(recurrence_instance_date.as_deref(), Some("2026-03-29"));
}

#[test]
fn import_rejects_malformed_calendar_event_override_linkage_before_db_insert() {
    for (label, series_id, recurrence_instance_date) in [
        ("half-set-series", Some("evt-series"), None),
        ("half-set-date", None, Some("2026-03-29")),
        ("bad-date", Some("evt-series"), Some("March 29")),
    ] {
        let conn = open_db_in_memory().unwrap();
        let dir = tempdir().unwrap();
        let zip_path = dir
            .path()
            .join(format!("bad-calendar-override-{label}.zip"));

        let mut payload = serde_json::json!({
            "id": format!("evt-{label}"),
            "title": "Moved occurrence",
            "start_date": "2026-03-29",
            "all_day": true,
            "event_type": "event",
            "created_at": "2026-03-29T00:00:00Z",
            "updated_at": "2026-03-29T00:00:00Z"
        });
        if let Some(value) = series_id {
            payload["series_id"] = serde_json::json!(value);
        }
        if let Some(value) = recurrence_instance_date {
            payload["recurrence_instance_date"] = serde_json::json!(value);
        }

        write_import_zip(
            &zip_path,
            &[serde_json::json!({
                "entity_type": ENTITY_CALENDAR_EVENT,
                "entity_id": format!("evt-{label}"),
                "version": "1711234567890_0001_deadbeefdeadbeef",
                "payload": payload
            })],
            &[],
            &[],
            &[],
            &[],
        );

        let err = import_from_zip(&conn, &zip_path).unwrap_err();
        match err {
            ImportError::InvalidPayload(message) => {
                assert!(
                    message.contains("series_id") || message.contains("recurrence_instance_date"),
                    "got: {message}"
                );
            }
            other => {
                panic!("expected InvalidPayload for malformed override linkage, got {other:?}")
            }
        }
        let event_count: i64 = conn
            .query_row("SELECT COUNT(*) FROM calendar_events", [], |row| row.get(0))
            .expect("count calendar events");
        assert_eq!(event_count, 0);
    }
}

#[test]
fn import_rejects_habit_with_invalid_color_before_db_insert() {
    let conn = open_db_in_memory().unwrap();
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("bad-habit-color.zip");

    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_HABIT,
            "entity_id": "habit-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "habit-1",
                "name": "Hydrate",
                "color": "red",
                "frequency_type": "daily",
                "target_count": 1,
                "archived": false,
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    match err {
        ImportError::InvalidPayload(message) => {
            assert!(message.contains("habit-1"));
            assert!(message.contains("color"));
            assert!(message.contains("#RGB or #RRGGBB"));
        }
        other => panic!("expected InvalidPayload for invalid habit color, got {other:?}"),
    }

    let habit_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM habits", [], |row| row.get(0))
        .expect("count habits");
    assert_eq!(habit_count, 0, "invalid habit color must not insert a row");
}
