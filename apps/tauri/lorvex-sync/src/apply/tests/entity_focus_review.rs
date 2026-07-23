use super::*;
use lorvex_store::test_support::fixtures::TaskBuilder;

#[test]
fn current_focus_upsert_materializes_items() {
    let conn = test_db();

    // Pre-create tasks.
    for tid in &["01966a3f-7c8b-7d4e-8f3a-000000002155", "t2", "t3"] {
        TaskBuilder::new(tid).title("T").insert(&conn);
    }

    let payload = r#"{
        "briefing": "Focus on top 3",
        "timezone": "America/New_York",
        "task_ids": ["01966a3f-7c8b-7d4e-8f3a-000000002155", "t2", "t3"],
        "created_at": "2026-03-24",
        "updated_at": "2026-03-24"
    }"#;
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::CurrentFocus,
        entity_id: "2026-03-24".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: payload.to_string(),
        device_id: "remote-device".to_string(),
    };

    apply_envelope(&conn, &env).unwrap();

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus_items WHERE date = ?1",
            ["2026-03-24"],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(count, 3);
}

#[test]
fn current_focus_upsert_rejects_non_string_briefing_when_present() {
    let conn = test_db();
    let payload = r#"{
        "briefing": 42,
        "task_ids": [],
        "created_at": "2026-03-24",
        "updated_at": "2026-03-24"
    }"#;
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::CurrentFocus,
        entity_id: "2026-03-24".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: payload.to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(matches!(result, Err(ApplyError::InvalidPayload(_))));
}

#[test]
fn current_focus_upsert_rejects_non_string_task_ids() {
    let conn = test_db();
    let payload = r#"{
        "briefing": "Broken",
        "timezone": "America/New_York",
        "task_ids": ["01966a3f-7c8b-7d4e-8f3a-000000002155", 42],
        "created_at": "2026-03-24",
        "updated_at": "2026-03-24"
    }"#;
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::CurrentFocus,
        entity_id: "2026-03-24".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: payload.to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(matches!(result, Err(ApplyError::InvalidPayload(_))));
}

#[test]
fn focus_schedule_upsert_rejects_non_string_timezone_when_present() {
    let conn = test_db();
    let payload = r#"{
        "timezone": 9,
        "blocks": [],
        "created_at": "2026-03-24",
        "updated_at": "2026-03-24"
    }"#;
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::FocusSchedule,
        entity_id: "2026-03-24".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: payload.to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(matches!(result, Err(ApplyError::InvalidPayload(_))));
}

#[test]
fn focus_schedule_upsert_rejects_invalid_block_time() {
    let conn = test_db();
    let payload = r#"{
        "rationale": "Broken",
        "timezone": "America/New_York",
        "blocks": [
            {
                "block_type": "task",
                "start_time": "25:99",
                "end_time": "10:30",
                "task_id": "01966a3f-7c8b-7d4e-8f3a-000000002155"
            }
        ],
        "created_at": "2026-03-24",
        "updated_at": "2026-03-24"
    }"#;
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::FocusSchedule,
        entity_id: "2026-03-24".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: payload.to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(matches!(result, Err(ApplyError::InvalidPayload(_))));
}

#[test]
fn current_focus_upsert_accepts_missing_task_ids_as_empty() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::CurrentFocus,
        entity_id: "2026-03-29".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{"created_at":"","updated_at":""}"#.to_string(),
        device_id: "remote-device".to_string(),
    };

    // Missing task_ids should be treated as empty for forward-compatibility
    let result = apply_envelope(&conn, &env);
    assert!(
        result.is_ok(),
        "missing task_ids should default to empty: {result:?}"
    );
}

#[test]
fn focus_schedule_upsert_rejects_missing_blocks() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::FocusSchedule,
        entity_id: "2026-03-29".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{"created_at":"","updated_at":""}"#.to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(matches!(result, Err(ApplyError::InvalidPayload(_))));
}

#[test]
fn daily_review_upsert_rejects_non_integer_mood_when_present() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::DailyReview,
        entity_id: "2026-03-29".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{
            "summary":"s",
            "mood":"great",
            "linked_task_ids":[],
            "linked_list_ids":[],
            "created_at":"",
            "updated_at":""
        }"#
        .to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(matches!(result, Err(ApplyError::InvalidPayload(_))));
}

#[test]
fn daily_review_upsert_rejects_non_string_wins_when_present() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::DailyReview,
        entity_id: "2026-03-29".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{
            "summary":"s",
            "wins":[],
            "linked_task_ids":[],
            "linked_list_ids":[],
            "created_at":"",
            "updated_at":""
        }"#
        .to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(matches!(result, Err(ApplyError::InvalidPayload(_))));
}

#[test]
fn daily_review_upsert_accepts_missing_link_arrays_as_empty() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::DailyReview,
        entity_id: "2026-03-29".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{"summary":"s","created_at":"","updated_at":""}"#.to_string(),
        device_id: "remote-device".to_string(),
    };

    // Missing link arrays should be treated as empty for forward-compatibility
    let result = apply_envelope(&conn, &env);
    assert!(
        result.is_ok(),
        "missing link arrays should default to empty: {result:?}"
    );
}

#[test]
fn apply_task_payload_collapses_empty_recurrence_to_null() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Task,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002180".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{
            "title":"t",
            "status":"open",
            "defer_count":0,
            "recurrence":"",
            "recurrence_exceptions":"",
            "recurrence_group_id":"",
            "canonical_occurrence_date":"",
            "recurrence_instance_key":"",
            "spawned_from":"",
            "created_at":"",
            "updated_at":""
        }"#
        .to_string(),
        device_id: "remote-device".to_string(),
    };
    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);

    // Each of these optional string fields must be NULL in the row, not "".
    type OptionalFields = (
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
    );
    let (
        recurrence,
        recurrence_exceptions,
        recurrence_group_id,
        canonical_occurrence_date,
        recurrence_instance_key,
        spawned_from,
    ): OptionalFields = conn
        .query_row(
            "SELECT recurrence, \
                    (SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]') \
                     FROM task_recurrence_exceptions WHERE task_id = tasks.id), \
                    recurrence_group_id,
                    canonical_occurrence_date, recurrence_instance_key, spawned_from
             FROM tasks WHERE id = ?1",
            ["01966a3f-7c8b-7d4e-8f3a-000000002180"],
            |r| {
                Ok((
                    r.get(0)?,
                    r.get(1)?,
                    r.get(2)?,
                    r.get(3)?,
                    r.get(4)?,
                    r.get(5)?,
                ))
            },
        )
        .unwrap();
    assert_eq!(recurrence, None, "recurrence must collapse to NULL");
    assert_eq!(
        recurrence_exceptions, None,
        "recurrence_exceptions must collapse to NULL"
    );
    assert_eq!(
        recurrence_group_id, None,
        "recurrence_group_id must collapse to NULL"
    );
    assert_eq!(
        canonical_occurrence_date, None,
        "canonical_occurrence_date must collapse to NULL"
    );
    assert_eq!(
        recurrence_instance_key, None,
        "recurrence_instance_key must collapse to NULL"
    );
    assert_eq!(spawned_from, None, "spawned_from must collapse to NULL");
}

#[test]
fn apply_calendar_event_accepts_all_day_as_json_bool() {
    let conn = test_db();
    let mut env = make_envelope(
        naming::ENTITY_CALENDAR_EVENT,
        "01966a3f-7c8b-7d4e-8f3a-00000000211f",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    // Override payload to ship `all_day` as a JSON bool — the shape the
    // Rust `serde_json::to_value(&CalendarEvent)` actually emits.
    env.payload = r#"{
        "title": "Event",
        "start_date": "2026-04-12",
        "all_day": true,
        "event_type": "event",
        "created_at": "",
        "updated_at": ""
    }"#
    .to_string();

    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);

    let all_day: i64 = conn
        .query_row(
            "SELECT all_day FROM calendar_events WHERE id = ?1",
            ["01966a3f-7c8b-7d4e-8f3a-00000000211f"],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(all_day, 1);
}

#[test]
fn apply_habit_accepts_archived_as_json_bool() {
    let conn = test_db();
    let mut env = make_envelope(
        naming::ENTITY_HABIT,
        "01966a3f-7c8b-7d4e-8f3a-000000002126",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    env.payload = r#"{
        "name": "Read",
        "frequency_type": "daily",
        "target_count": 1,
        "archived": false,
        "created_at": "",
        "updated_at": ""
    }"#
    .to_string();

    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);

    let archived: i64 = conn
        .query_row(
            "SELECT archived FROM habits WHERE id = ?1",
            ["01966a3f-7c8b-7d4e-8f3a-000000002126"],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(archived, 0);
}

#[test]
fn apply_habit_rejects_invalid_color_before_db_write() {
    let conn = test_db();
    let mut env = make_envelope(
        naming::ENTITY_HABIT,
        "01966a3f-7c8b-7d4e-8f3a-000000002125",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    env.payload = r#"{
        "name": "Read",
        "color": "red",
        "frequency_type": "daily",
        "target_count": 1,
        "archived": false,
        "created_at": "",
        "updated_at": ""
    }"#
    .to_string();

    let result = apply_envelope(&conn, &env);
    assert!(
        matches!(&result, Err(ApplyError::InvalidPayload(message)) if message.contains("color") && message.contains("#RGB or #RRGGBB")),
        "expected InvalidPayload for invalid habit color, got {result:?}"
    );

    let habit_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM habits", [], |row| row.get(0))
        .expect("count habits");
    assert_eq!(habit_count, 0, "invalid habit color must not insert a row");
}
