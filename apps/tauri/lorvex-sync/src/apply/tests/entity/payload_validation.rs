use super::*;

#[test]
fn tag_upsert_rejects_legacy_name_only_payload() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Tag,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002157".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload:
            r#"{"name":"01966a3f-7c8b-7d4e-8f3a-00000000212e","created_at":"","updated_at":""}"#
                .to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(matches!(result, Err(ApplyError::InvalidPayload(_))));
}

#[test]
fn tag_upsert_rejects_non_string_color_when_present() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Tag,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002158".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{
            "display_name":"Tag",
            "lookup_key":"tag",
            "color":5,
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
fn task_upsert_rejects_missing_title() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Task,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-00000000216c".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{"status":"open","defer_count":0,"created_at":"","updated_at":""}"#.to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(matches!(result, Err(ApplyError::InvalidPayload(_))));
}

#[test]
fn task_upsert_rejects_non_string_list_id_when_present() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Task,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-00000000216d".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{
            "title":"Task",
            "status":"open",
            "list_id":123,
            "defer_count":0,
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
fn task_upsert_rejects_non_integer_priority_when_present() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Task,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-00000000216e".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{
            "title":"Task",
            "status":"open",
            "priority":"high",
            "defer_count":0,
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
fn list_upsert_rejects_missing_name() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::List,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002131".to_string(),
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
fn list_upsert_rejects_non_string_color_when_present() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::List,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002132".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{"name":"Inbox","color":7,"created_at":"","updated_at":""}"#.to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(matches!(result, Err(ApplyError::InvalidPayload(_))));
}

#[test]
fn habit_upsert_rejects_non_integer_target_count() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Habit,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002123".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4").expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{"name":"habit","frequency_type":"daily","target_count":"one","archived":false,"created_at":"","updated_at":""}"#.to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(matches!(result, Err(ApplyError::InvalidPayload(_))));
}

#[test]
fn habit_upsert_round_trips_milestone_target() {
    let conn = test_db();
    let habit_id = "01966a3f-7c8b-7d4e-8f3a-000000002130";
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Habit,
        entity_id: habit_id.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{"name":"Read","frequency_type":"daily","target_count":1,"milestone_target":30,"archived":false,"created_at":"","updated_at":""}"#.to_string(),
        device_id: "remote-device".to_string(),
    };

    apply_envelope(&conn, &env).expect("apply habit upsert with milestone_target");

    let milestone: Option<i64> = conn
        .query_row(
            "SELECT milestone_target FROM habits WHERE id = ?1",
            [habit_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(milestone, Some(30));
}

#[test]
fn habit_upsert_omits_milestone_target_as_null() {
    let conn = test_db();
    let habit_id = "01966a3f-7c8b-7d4e-8f3a-000000002131";
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Habit,
        entity_id: habit_id.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        // A peer that predates the column omits `milestone_target` entirely.
        payload: r#"{"name":"Read","frequency_type":"daily","target_count":1,"archived":false,"created_at":"","updated_at":""}"#.to_string(),
        device_id: "remote-device".to_string(),
    };

    apply_envelope(&conn, &env).expect("apply habit upsert without milestone_target");

    let milestone: Option<i64> = conn
        .query_row(
            "SELECT milestone_target FROM habits WHERE id = ?1",
            [habit_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(milestone, None);
}

#[test]
fn habit_upsert_rejects_non_positive_milestone_target() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Habit,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002132".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{"name":"Read","frequency_type":"daily","target_count":1,"milestone_target":0,"archived":false,"created_at":"","updated_at":""}"#.to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(matches!(result, Err(ApplyError::InvalidPayload(_))));
}

#[test]
fn habit_upsert_rejects_out_of_range_weekday() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Habit,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002124".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        // Monday-first weekday indices are 0..=6; `9` is out of range.
        payload: r#"{
            "name":"habit",
            "frequency_type":"weekly",
            "weekdays":[0,9],
            "target_count":1,
            "archived":false,
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
fn calendar_event_upsert_rejects_non_boolean_all_day() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::CalendarEvent,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002118".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4").expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{"title":"Event","start_date":"2026-01-01","all_day":"yes","event_type":"event","created_at":"","updated_at":""}"#.to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(matches!(result, Err(ApplyError::InvalidPayload(_))));
}

#[test]
fn calendar_event_upsert_rejects_non_string_timezone_when_present() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::CalendarEvent,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002119".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{
            "title":"Event",
            "start_date":"2026-01-01",
            "all_day":false,
            "timezone":9,
            "event_type":"event",
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
fn calendar_subscription_upsert_rejects_non_boolean_enabled() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::CalendarSubscription,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002151".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4").expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{"name":"Feed","url":"https://example.com","enabled":"yes","created_at":"","updated_at":""}"#.to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(matches!(result, Err(ApplyError::InvalidPayload(_))));
}

#[test]
fn preference_upsert_rejects_missing_value() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Preference,
        entity_id: "timezone".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{"updated_at":""}"#.to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(matches!(result, Err(ApplyError::InvalidPayload(_))));
}

#[test]
fn calendar_event_upsert_keeps_name_only_attendee() {
    // Untrusted peer data must never drop the whole event: a name-only
    // attendee (no email) materializes under a `name:`-derived identity
    // rather than failing the apply. Mirrors Apple's sync-apply contract.
    let conn = test_db();
    let event_id = "01966a3f-7c8b-7d4e-8f3a-00000000211a";
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::CalendarEvent,
        entity_id: event_id.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{
            "title":"Event",
            "start_date":"2026-01-01",
            "all_day":false,
            "event_type":"event",
            "created_at":"",
            "updated_at":"",
            "attendees":[{"name":"Missing Email"}]
        }"#
        .to_string(),
        device_id: "remote-device".to_string(),
    };

    apply_envelope(&conn, &env).expect("name-only attendee must be kept");
    let (attendee_id, email): (String, String) = conn
        .query_row(
            "SELECT attendee_id, email FROM calendar_event_attendees WHERE event_id = ?1",
            [event_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("attendee row must exist");
    assert_eq!(attendee_id, "name:missing email");
    assert_eq!(email, "");
}

// ---------------------------------------------------------------------------
// Issue #2880-M6 regressions: calendar_event date/time validators reject
// shape-malformed strings at the trust boundary instead of letting the
// schema CHECK abort the entire apply batch.
// ---------------------------------------------------------------------------

#[test]
fn calendar_event_upsert_rejects_malformed_start_date() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::CalendarEvent,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-00000000211d".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{
            "title":"Event",
            "start_date":"tomorrow",
            "all_day":true,
            "event_type":"event",
            "created_at":"",
            "updated_at":""
        }"#
        .to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(
        matches!(&result, Err(ApplyError::InvalidPayload(msg)) if msg.contains("start_date")),
        "expected start_date validation error, got {result:?}"
    );
}

#[test]
fn calendar_event_upsert_rejects_malformed_end_date() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::CalendarEvent,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-00000000211b".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{
            "title":"Event",
            "start_date":"2026-01-01",
            "end_date":"02-15-2026",
            "all_day":true,
            "event_type":"event",
            "created_at":"",
            "updated_at":""
        }"#
        .to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(
        matches!(&result, Err(ApplyError::InvalidPayload(msg)) if msg.contains("end_date")),
        "expected end_date validation error, got {result:?}"
    );
}

#[test]
fn calendar_event_upsert_rejects_malformed_start_time() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::CalendarEvent,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-00000000211e".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{
            "title":"Event",
            "start_date":"2026-01-01",
            "start_time":"25:00",
            "end_time":"10:30",
            "all_day":false,
            "event_type":"event",
            "created_at":"",
            "updated_at":""
        }"#
        .to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(
        matches!(&result, Err(ApplyError::InvalidPayload(msg)) if msg.contains("start_time")),
        "expected start_time validation error, got {result:?}"
    );
}

#[test]
fn calendar_event_upsert_rejects_malformed_end_time() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::CalendarEvent,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-00000000211c".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{
            "title":"Event",
            "start_date":"2026-01-01",
            "start_time":"09:00",
            "end_time":"not-a-time",
            "all_day":false,
            "event_type":"event",
            "created_at":"",
            "updated_at":""
        }"#
        .to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(
        matches!(&result, Err(ApplyError::InvalidPayload(msg)) if msg.contains("end_time")),
        "expected end_time validation error, got {result:?}"
    );
}

// ---------------------------------------------------------------------------
// focus_schedule blocks with integer-encoded
// `start_time` / `end_time` MUST be range-checked (`0..=1440`) and ordered
// (`start <= end`). The string-encoded path was already validated by
// `parse_required_time_field`; this targets the bypass via raw integers.
// ---------------------------------------------------------------------------

#[test]
fn focus_schedule_upsert_rejects_integer_start_time_above_1440() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::FocusSchedule,
        entity_id: "2026-04-26".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{
            "blocks":[{"block_type":"buffer","start_time":2000,"end_time":2100}],
            "created_at":"2026-04-26",
            "updated_at":"2026-04-26"
        }"#
        .to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(
        matches!(&result, Err(ApplyError::InvalidPayload(msg)) if msg.contains("0..=1440")),
        "expected 0..=1440 range validation error, got {result:?}"
    );
}

#[test]
fn focus_schedule_upsert_rejects_negative_integer_minutes() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::FocusSchedule,
        entity_id: "2026-04-26".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{
            "blocks":[{"block_type":"buffer","start_time":-30,"end_time":60}],
            "created_at":"2026-04-26",
            "updated_at":"2026-04-26"
        }"#
        .to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(
        matches!(&result, Err(ApplyError::InvalidPayload(msg)) if msg.contains("0..=1440")),
        "expected 0..=1440 range validation error, got {result:?}"
    );
}

#[test]
fn focus_schedule_upsert_rejects_inverted_start_end_time() {
    let conn = test_db();
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::FocusSchedule,
        entity_id: "2026-04-26".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{
            "blocks":[{"block_type":"buffer","start_time":600,"end_time":540}],
            "created_at":"2026-04-26",
            "updated_at":"2026-04-26"
        }"#
        .to_string(),
        device_id: "remote-device".to_string(),
    };

    let result = apply_envelope(&conn, &env);
    assert!(
        matches!(&result, Err(ApplyError::InvalidPayload(msg))
            if msg.contains("precedes start_time")),
        "expected start<=end ordering error, got {result:?}"
    );
}
