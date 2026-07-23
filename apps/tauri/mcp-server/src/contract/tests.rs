use super::*;
use crate::contract_validate::{ContractValidate, ValidationCtx};
use serde_json::json;

#[test]
#[serial_test::serial(hlc)]
fn create_calendar_event_args_reject_string_all_day() {
    let err = serde_json::from_value::<CreateCalendarEventArgs>(json!({
        "title": "Calendar strict bool",
        "start_date": "2026-03-20",
        "all_day": "true"
    }))
    .expect_err("string all_day should be rejected");

    assert!(err.to_string().contains("boolean"));
}

// ── ContractValidate derive coverage (#3373) ─────────────────────
//
// These tests exercise the proc-macro emitted shape-only validators
// against the Phase 1 migrated structs. They lock in:
//   - UUID format gate fires on non-UUID `id` values
//   - Optional UUID fields on lifecycle structs accept missing input
//   - String length cap fires on over-cap `notes` / `summary` payloads
//   - Composite structs (`BatchLinkTasksToEventArgs`) validate every
//     element of a `Vec<String>` UUID list

#[test]
#[serial_test::serial(hlc)]
fn contract_validate_rejects_non_uuid_complete_task_id() {
    let args = CompleteTaskArgs {
        id: "not-a-uuid".to_string(),
        idempotency_key: None,
    };
    let err = args
        .validate_shape()
        .expect_err("non-UUID id should be rejected");
    let msg = err.to_string();
    assert!(
        msg.contains("not a valid UUID") || msg.contains("UUID"),
        "expected UUID-shape error, got: {msg}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn contract_validate_accepts_well_formed_complete_task_id() {
    let args = CompleteTaskArgs {
        id: "01966a3f-7c8b-7d4e-8f3a-000000000001".to_string(),
        idempotency_key: None,
    };
    args.validate_shape().expect("valid UUID id should pass");
}

#[test]
#[serial_test::serial(hlc)]
fn contract_validate_caps_set_task_ai_notes_length() {
    let huge = "x".repeat(crate::contract::MAX_AI_NOTES_LENGTH + 1);
    let args = SetTaskAiNotesArgs {
        id: "01966a3f-7c8b-7d4e-8f3a-000000000001".to_string(),
        notes: huge,
        idempotency_key: None,
    };
    args.validate_shape()
        .expect_err("over-cap notes should be rejected");
}

#[test]
#[serial_test::serial(hlc)]
fn contract_validate_passes_optional_reason_when_unset() {
    let args = CancelTaskArgs {
        id: "01966a3f-7c8b-7d4e-8f3a-000000000001".to_string(),
        reason: None,
        cancel_series: None,
        idempotency_key: None,
        dry_run: false,
    };
    args.validate_shape().expect("missing reason should pass");
}

#[test]
#[serial_test::serial(hlc)]
fn contract_validate_calendar_link_rejects_bad_uuid_element() {
    let args = BatchLinkTasksToEventArgs {
        task_ids: vec![
            "01966a3f-7c8b-7d4e-8f3a-000000000001".to_string(),
            "task-1".to_string(),
        ],
        event_id: "01966a3f-7c8b-7d4e-8f3a-000000000002".to_string(),
        idempotency_key: None,
    };

    let err = args
        .validate_shape()
        .expect_err("non-UUID task id should be rejected");
    let msg = err.to_string();
    assert!(
        msg.contains("UUID") && msg.contains("task-1"),
        "expected UUID element error, got: {msg}"
    );
}

// ── Phase 2: ContractValidate derive `exists_in` coverage (#3437) ─

fn db_for_validate_tests() -> rusqlite::Connection {
    let conn = rusqlite::Connection::open_in_memory().expect("open in-memory db");
    lorvex_store::migration::apply_migrations(&conn, &lorvex_store::schema::all_migrations())
        .expect("apply migrations");
    conn
}

#[test]
#[serial_test::serial(hlc)]
fn contract_validate_set_current_focus_rejects_phantom_task_id() {
    // The derive on `SetCurrentFocusArgs` declares
    // `#[validate(exists_in = "tasks_active")]` on `task_ids`. With
    // an empty DB, a well-formed UUID that does not exist must be
    // rejected by `args.validate(&ctx)?`.
    let conn = db_for_validate_tests();
    let args = SetCurrentFocusArgs {
        task_ids: vec!["01966a3f-7c8b-7d4e-8f3a-000000000001".to_string()],
        briefing: None,
        date: None,
        idempotency_key: None,
    };
    let ctx = ValidationCtx::new(&conn);
    let err = args
        .validate(&ctx)
        .expect_err("phantom task_id should be rejected");
    assert!(
        err.to_string().contains("non-existent task"),
        "expected non-existent task error, got: {err}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn contract_validate_set_current_focus_rejects_archived_task() {
    // Soft-deleted (archived) tasks must also be rejected by the
    // `tasks_active` exists_in target — pinning a freshly-trashed
    // task into focus is almost always a stale-context bug.
    let conn = db_for_validate_tests();
    lorvex_store::test_support::fixtures::TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-000000000001")
        .title("Archived")
        .archived_at(Some("2026-04-26T00:00:00.000Z"))
        .insert(&conn);
    let args = SetCurrentFocusArgs {
        task_ids: vec!["01966a3f-7c8b-7d4e-8f3a-000000000001".to_string()],
        briefing: None,
        date: None,
        idempotency_key: None,
    };
    let err = args
        .validate(&ValidationCtx::new(&conn))
        .expect_err("archived task should be rejected");
    assert!(
        err.to_string().contains("archived"),
        "expected archived error, got: {err}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn contract_validate_amend_daily_review_rejects_phantom_list_id() {
    // `AmendDailyReviewArgs.linked_list_ids` carries
    // `#[validate(exists_in = "lists")]`. With no list rows, a
    // well-formed but unknown list id must fail.
    let conn = db_for_validate_tests();
    let args = AmendDailyReviewArgs {
        date: "2026-05-01".to_string(),
        summary: None,
        mood: None,
        energy_level: None,
        wins: None,
        blockers: None,
        learnings: None,
        ai_synthesis: None,
        linked_task_ids: None,
        linked_list_ids: Some(vec!["lst-phantom".to_string()]),
    };
    let err = args
        .validate(&ValidationCtx::new(&conn))
        .expect_err("phantom list id should be rejected");
    assert!(
        err.to_string().contains("non-existent list"),
        "expected non-existent list error, got: {err}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn contract_validate_amend_daily_review_passes_when_optional_links_unset() {
    // Both `linked_task_ids` and `linked_list_ids` are `Option`s.
    // When unset, the derive must not query the DB and must succeed.
    let conn = db_for_validate_tests();
    let args = AmendDailyReviewArgs {
        date: "2026-05-01".to_string(),
        summary: Some("ok".to_string()),
        mood: None,
        energy_level: None,
        wins: None,
        blockers: None,
        learnings: None,
        ai_synthesis: None,
        linked_task_ids: None,
        linked_list_ids: None,
    };
    args.validate(&ValidationCtx::new(&conn))
        .expect("None options should skip DB lookups");
}
