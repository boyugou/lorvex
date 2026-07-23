//! Unit tests for [`build_task_row`]. These exercise the pure
//! parsing / validation / tri-state-splitting logic in isolation —
//! the upsert SQL is covered separately by integration tests in
//! `apply/aggregate/tests/`.
//!
//! Each test pins a specific behaviour (presence flags on absence
//! vs explicit-null vs explicit-value, validator error shapes,
//! list_id fallback, defer_count default) so a future refactor that
//! breaks the partial-update preservation invariant fails here
//! before it can land in production.

use super::super::super::super::ApplyError;
use super::build_task_row;
use crate::test_db;
use lorvex_domain::ids::TaskId;

const TASK_ID: &str = "00000000-0000-7000-8000-000000000099";

fn task_id() -> TaskId {
    // Issue #3285 phase 3: build_task_row now takes a typed `&TaskId`.
    // The fixtures use `from_trusted` rather than `parse` so the
    // tests can keep using the same hand-rolled UUIDv7 literal — the
    // typed seam at the apply handler entry is what we exercise here,
    // not the parse-side validation.
    TaskId::from_trusted(TASK_ID.to_string())
}
const VERSION: &str = "1711234567000_0000_dec0000100000001";

fn minimal_payload() -> serde_json::Value {
    serde_json::json!({
        "title": "task title",
        "status": "open",
        "list_id": lorvex_store::INBOX_LIST_ID,
        "created_at": "2026-04-01T00:00:00.000Z",
        "updated_at": "2026-04-01T00:00:00.000Z",
    })
}

fn payload_str(v: &serde_json::Value) -> String {
    serde_json::to_string(v).unwrap()
}

#[test]
fn minimal_payload_marks_every_optional_column_absent() {
    let conn = test_db();
    let payload = payload_str(&minimal_payload());
    let row = build_task_row(&conn, &task_id(), &payload, VERSION).unwrap();

    assert_eq!(row.entity_id.as_str(), TASK_ID);
    assert_eq!(row.title, "task title");
    assert_eq!(row.status, "open");
    assert_eq!(row.created_at, "2026-04-01T00:00:00.000Z");
    assert_eq!(row.updated_at, "2026-04-01T00:00:00.000Z");
    assert_eq!(row.version, VERSION);

    // Every optional column must report `present = 0` so the
    // partial-update gate preserves the local value on the
    // receiving device.
    assert_eq!(row.body_present, 0);
    assert_eq!(row.raw_input_present, 0);
    assert_eq!(row.ai_notes_present, 0);
    assert_eq!(row.priority_present, 0);
    assert_eq!(row.due_date_present, 0);
    assert_eq!(row.due_time_present, 0);
    assert_eq!(row.estimated_minutes_present, 0);
    assert_eq!(row.recurrence_present, 0);
    assert_eq!(row.recurrence_exceptions_present, 0);
    assert_eq!(row.spawned_from_present, 0);
    assert_eq!(row.recurrence_group_id_present, 0);
    assert_eq!(row.canonical_occurrence_date_present, 0);
    assert_eq!(row.completed_at_present, 0);
    assert_eq!(row.last_deferred_at_present, 0);
    assert_eq!(row.last_defer_reason_present, 0);
    assert_eq!(row.planned_date_present, 0);
    assert_eq!(row.defer_count_present, 0);
    assert_eq!(row.recurrence_instance_key_present, 0);
    assert_eq!(row.archived_at_present, 0);

    // The bind values for absent fields are None / 0 (defer_count
    // schema default).
    assert!(row.body.is_none());
    assert!(row.priority.is_none());
    assert!(row.estimated_minutes.is_none());
    assert_eq!(row.defer_count, 0);
}

#[test]
fn explicit_null_value_marks_field_present_with_none_value() {
    // Explicit JSON null on a nullable column means "clear the
    // column". The row must report `present = 1` AND value =
    // `None` so the UPDATE path lands a SQL NULL on the row.
    let conn = test_db();
    let mut payload = minimal_payload();
    payload["body"] = serde_json::Value::Null;
    payload["priority"] = serde_json::Value::Null;
    payload["recurrence"] = serde_json::Value::Null;
    let row = build_task_row(&conn, &task_id(), &payload_str(&payload), VERSION).unwrap();

    assert_eq!(row.body_present, 1);
    assert!(row.body.is_none());
    assert_eq!(row.priority_present, 1);
    assert!(row.priority.is_none());
    assert_eq!(row.recurrence_present, 1);
    assert!(row.recurrence.is_none());
}

#[test]
fn explicit_empty_string_on_text_column_collapses_to_clear() {
    // The tri-state helper treats `""` as an explicit clear so
    // peers can NULL-out a column without sending JSON null. The
    // bind value lands as None but `present = 1` so the UPDATE
    // path actually writes the NULL.
    let conn = test_db();
    let mut payload = minimal_payload();
    payload["body"] = serde_json::Value::String(String::new());
    payload["due_date"] = serde_json::Value::String(String::new());
    let row = build_task_row(&conn, &task_id(), &payload_str(&payload), VERSION).unwrap();

    assert_eq!(row.body_present, 1);
    assert!(row.body.is_none());
    assert_eq!(row.due_date_present, 1);
    assert!(row.due_date.is_none());
}

#[test]
fn explicit_value_carries_through_validated_and_scrubbed() {
    let conn = test_db();
    let mut payload = minimal_payload();
    payload["body"] = serde_json::json!("hello world");
    payload["priority"] = serde_json::json!(2);
    payload["estimated_minutes"] = serde_json::json!(45);
    payload["due_date"] = serde_json::json!("2026-05-01");
    let row = build_task_row(&conn, &task_id(), &payload_str(&payload), VERSION).unwrap();

    assert_eq!(row.body.as_deref(), Some("hello world"));
    assert_eq!(row.body_present, 1);
    assert_eq!(row.priority, Some(2));
    assert_eq!(row.priority_present, 1);
    assert_eq!(row.estimated_minutes, Some(45));
    assert_eq!(row.estimated_minutes_present, 1);
    assert_eq!(row.due_date.as_deref(), Some("2026-05-01"));
}

#[test]
fn invalid_status_yields_typed_invalid_payload_error() {
    let conn = test_db();
    let mut payload = minimal_payload();
    payload["status"] = serde_json::json!("garbage");
    let err = build_task_row(&conn, &task_id(), &payload_str(&payload), VERSION).unwrap_err();
    match err {
        ApplyError::InvalidPayload(msg) => {
            assert!(
                msg.contains("status"),
                "error must mention the offending field, got: {msg}"
            );
        }
        other => panic!("expected InvalidPayload, got {other:?}"),
    }
}

#[test]
fn negative_defer_count_is_rejected_at_apply_boundary() {
    let conn = test_db();
    let mut payload = minimal_payload();
    payload["defer_count"] = serde_json::json!(-1);
    let err = build_task_row(&conn, &task_id(), &payload_str(&payload), VERSION).unwrap_err();
    match err {
        ApplyError::InvalidPayload(msg) => {
            assert!(msg.contains("defer_count"), "got: {msg}");
        }
        other => panic!("expected InvalidPayload, got {other:?}"),
    }
}

#[test]
fn invalid_defer_reason_enum_is_rejected() {
    let conn = test_db();
    let mut payload = minimal_payload();
    payload["last_defer_reason"] = serde_json::json!("totally-not-a-real-reason");
    let err = build_task_row(&conn, &task_id(), &payload_str(&payload), VERSION).unwrap_err();
    match err {
        ApplyError::InvalidPayload(msg) => {
            assert!(msg.contains("last_defer_reason"), "got: {msg}");
        }
        other => panic!("expected InvalidPayload, got {other:?}"),
    }
}

#[test]
fn list_id_falls_back_to_inbox_when_payload_omits_field() {
    let conn = test_db();
    // The test_db seed contains the canonical inbox list. Drop
    // the field from the payload entirely.
    let mut payload = minimal_payload();
    payload.as_object_mut().unwrap().remove("list_id");
    let row = build_task_row(&conn, &task_id(), &payload_str(&payload), VERSION).unwrap();
    assert_eq!(
        row.list_id.as_deref(),
        Some(lorvex_store::INBOX_LIST_ID),
        "absent list_id must fall back to the canonical inbox list"
    );
}

#[test]
fn list_id_falls_back_to_inbox_when_payload_supplies_empty_string() {
    let conn = test_db();
    let mut payload = minimal_payload();
    payload["list_id"] = serde_json::json!("");
    let row = build_task_row(&conn, &task_id(), &payload_str(&payload), VERSION).unwrap();
    assert_eq!(row.list_id.as_deref(), Some(lorvex_store::INBOX_LIST_ID));
}

#[test]
fn defer_count_default_is_zero_when_field_absent() {
    let conn = test_db();
    let payload = payload_str(&minimal_payload());
    let row = build_task_row(&conn, &task_id(), &payload, VERSION).unwrap();
    assert_eq!(
        row.defer_count, 0,
        "defer_count must default to 0 (schema default) when the envelope omits it"
    );
    assert_eq!(
        row.defer_count_present, 0,
        "absent defer_count must be marked not-present so UPDATE preserves the local counter"
    );
}

#[test]
fn priority_out_of_range_is_rejected() {
    let conn = test_db();
    let mut payload = minimal_payload();
    payload["priority"] = serde_json::json!(99);
    let err = build_task_row(&conn, &task_id(), &payload_str(&payload), VERSION).unwrap_err();
    assert!(matches!(err, ApplyError::InvalidPayload(_)));
}

#[test]
fn malformed_due_time_is_rejected_at_apply_boundary() {
    let conn = test_db();
    let mut payload = minimal_payload();
    payload["due_time"] = serde_json::json!("25:00");

    let err = build_task_row(&conn, &task_id(), &payload_str(&payload), VERSION).unwrap_err();

    match err {
        ApplyError::InvalidPayload(msg) => assert!(msg.contains("due_time"), "got: {msg}"),
        other => panic!("expected InvalidPayload, got {other:?}"),
    }
}

#[test]
fn malformed_planned_date_is_rejected_at_apply_boundary() {
    let conn = test_db();
    let mut payload = minimal_payload();
    payload["planned_date"] = serde_json::json!("next friday");

    let err = build_task_row(&conn, &task_id(), &payload_str(&payload), VERSION).unwrap_err();

    match err {
        ApplyError::InvalidPayload(msg) => assert!(msg.contains("planned_date"), "got: {msg}"),
        other => panic!("expected InvalidPayload, got {other:?}"),
    }
}

#[test]
fn malformed_canonical_occurrence_date_is_rejected_at_apply_boundary() {
    let conn = test_db();
    let mut payload = minimal_payload();
    payload["canonical_occurrence_date"] = serde_json::json!("2026/05/08");

    let err = build_task_row(&conn, &task_id(), &payload_str(&payload), VERSION).unwrap_err();

    match err {
        ApplyError::InvalidPayload(msg) => {
            assert!(msg.contains("canonical_occurrence_date"), "got: {msg}");
        }
        other => panic!("expected InvalidPayload, got {other:?}"),
    }
}
