use super::*;

#[test]
fn import_rejects_calendar_event_attendee_missing_email() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_CALENDAR_EVENT,
            "entity_id": "evt-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "evt-1",
                "title": "Event",
                "start_date": "2026-03-29",
                "all_day": false,
                "event_type": "event",
                "attendees": [{"name": "Missing Email"}],
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("attendees"),
        "expected attendees error, got: {err}"
    );
}

#[test]
fn import_rejects_calendar_subscription_missing_url() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_CALENDAR_SUBSCRIPTION,
            "entity_id": "sub-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "sub-1",
                "name": "Work",
                "enabled": true,
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("url"),
        "expected url error, got: {err}"
    );
}

#[test]
fn import_rejects_calendar_event_missing_event_type() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_CALENDAR_EVENT,
            "entity_id": "evt-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "evt-1",
                "title": "Event",
                "start_date": "2026-03-29",
                "all_day": false,
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("event_type"),
        "expected event_type error, got: {err}"
    );
}

#[test]
fn import_rejects_calendar_event_missing_title() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_CALENDAR_EVENT,
            "entity_id": "evt-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "evt-1",
                "start_date": "2026-03-29",
                "all_day": false,
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

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("title"),
        "expected title error, got: {err}"
    );
}

#[test]
fn import_rejects_calendar_event_non_string_timezone_when_present() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_CALENDAR_EVENT,
            "entity_id": "evt-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "evt-1",
                "title": "Event",
                "start_date": "2026-03-29",
                "all_day": false,
                "timezone": 9,
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

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("timezone"),
        "expected timezone error, got: {err}"
    );
}

#[test]
fn import_rejects_habit_missing_frequency_type() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_HABIT,
            "entity_id": "habit-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "habit-1",
                "name": "Walk",
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

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("frequency_type"),
        "expected frequency_type error, got: {err}"
    );
}

#[test]
fn import_rejects_current_focus_with_non_string_task_ids() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_CURRENT_FOCUS,
            "entity_id": "2026-03-29",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "date": "2026-03-29",
                "briefing": "Focus",
                "timezone": "UTC",
                "task_ids": ["task-1", 7],
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("task_ids"),
        "expected task_ids error, got: {err}"
    );
}

#[test]
fn import_rejects_focus_schedule_with_invalid_block_time() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_FOCUS_SCHEDULE,
            "entity_id": "2026-03-29",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "date": "2026-03-29",
                "timezone": "UTC",
                "blocks": [{
                    "block_type": "task",
                    "start_time": "09:00",
                    "end_time": 600,
                    "task_id": "task-1"
                }],
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("start_time"),
        "expected block time error, got: {err}"
    );
}

#[test]
fn import_rejects_current_focus_missing_created_at() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_CURRENT_FOCUS,
            "entity_id": "2026-03-29",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "date": "2026-03-29",
                "task_ids": [],
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("created_at"),
        "expected created_at error, got: {err}"
    );
}

#[test]
fn import_rejects_current_focus_non_string_briefing_when_present() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_CURRENT_FOCUS,
            "entity_id": "2026-03-29",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "date": "2026-03-29",
                "briefing": 42,
                "task_ids": [],
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("briefing"),
        "expected briefing error, got: {err}"
    );
}

#[test]
fn import_rejects_focus_schedule_missing_created_at() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_FOCUS_SCHEDULE,
            "entity_id": "2026-03-29",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "date": "2026-03-29",
                "blocks": [],
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("created_at"),
        "expected created_at error, got: {err}"
    );
}

#[test]
fn import_rejects_focus_schedule_non_string_timezone_when_present() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_FOCUS_SCHEDULE,
            "entity_id": "2026-03-29",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "date": "2026-03-29",
                "timezone": 9,
                "blocks": [],
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("timezone"),
        "expected timezone error, got: {err}"
    );
}

#[test]
fn import_rejects_daily_review_with_non_string_linked_ids() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_DAILY_REVIEW,
            "entity_id": "2026-03-29",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "date": "2026-03-29",
                "summary": "Good day",
                "linked_task_ids": ["task-1", 3],
                "linked_list_ids": ["list-1"],
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("linked_task_ids"),
        "expected linked_task_ids error, got: {err}"
    );
}

#[test]
fn import_rejects_daily_review_non_integer_mood_when_present() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_DAILY_REVIEW,
            "entity_id": "2026-03-29",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "date": "2026-03-29",
                "summary": "Good day",
                "mood": "great",
                "linked_task_ids": [],
                "linked_list_ids": [],
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("mood"),
        "expected mood error, got: {err}"
    );
}

#[test]
fn import_rejects_daily_review_missing_summary() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_DAILY_REVIEW,
            "entity_id": "2026-03-29",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "date": "2026-03-29",
                "linked_task_ids": [],
                "linked_list_ids": [],
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("summary"),
        "expected summary error, got: {err}"
    );
}

#[test]
fn import_rejects_audit_entry_missing_summary() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[],
        &[],
        &[],
        &[serde_json::json!({
            "entity_type": ENTITY_AI_CHANGELOG,
            "entity_id": "cl-1",
            "payload": {
                "id": "cl-1",
                "timestamp": "2026-03-29T00:00:00Z",
                "operation": "create",
                "entity_type": ENTITY_TASK,
                "initiated_by": "ai"
            }
        })],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("summary"),
        "expected summary error, got: {err}"
    );
}

#[test]
fn import_rejects_preference_missing_value() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_PREFERENCE,
            "entity_id": "theme",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "key": "theme",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("value"),
        "expected value error, got: {err}"
    );
}

#[test]
fn import_preference_value_is_stored_as_canonical_json_text() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[
            serde_json::json!({
                "entity_type": ENTITY_PREFERENCE,
                "entity_id": "theme",
                "version": "1711234567890_0001_deadbeefdeadbeef",
                "payload": {
                    "key": "theme",
                    "value": "dark",
                    "updated_at": "2026-03-29T00:00:00Z"
                }
            }),
            serde_json::json!({
                "entity_type": ENTITY_PREFERENCE,
                "entity_id": "working_hours",
                "version": "1711234567890_0002_deadbeefdeadbeef",
                "payload": {
                    "key": "working_hours",
                    "value": {"start": "09:00", "end": "17:00"},
                    "updated_at": "2026-03-29T00:00:00Z"
                }
            }),
        ],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    import_from_zip(&conn, &zip_path).unwrap();

    let theme: String = conn
        .query_row(
            "SELECT value FROM preferences WHERE key = 'theme'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(theme, "\"dark\"");

    let working_hours: String = conn
        .query_row(
            "SELECT value FROM preferences WHERE key = 'working_hours'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(working_hours, "{\"end\":\"17:00\",\"start\":\"09:00\"}");
}

#[test]
fn import_rejects_memory_missing_content() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_MEMORY,
            "entity_id": "behavioral_patterns",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "key": "behavioral_patterns",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("content"),
        "expected content error, got: {err}"
    );
}
