use super::support::{NOW_TS, TEST_VER};
use super::*;
use crate::test_support::test_conn;

// ──────────────────────────────────────────────────────────────────
// IPC edge coverage for `undo_task_lifecycle[_batch]`.
// The token parsing and apply logic are covered above; these test
// the additional guards the IPC wrappers layer on top — malformed
// JSON, status drift between mutation and undo, and empty-batch
// rejection.
// ──────────────────────────────────────────────────────────────────

#[test]
fn malformed_undo_token_json_is_rejected_with_validation_error() {
    let err = parse_and_validate_undo_token("{not valid json}")
        .expect_err("garbage JSON must be rejected");
    match err {
        AppError::Validation(msg) => {
            assert!(msg.contains("Invalid undo token"), "unexpected: {msg}");
        }
        other => panic!("expected Validation, got {other:?}"),
    }
}

#[test]
fn apply_single_undo_rejects_task_not_in_expected_post_state() {
    // The user hit "Undo complete" but the task is currently open
    // (e.g. a peer already reopened it before this undo fired).
    // The guard must surface a Validation error rather than
    // silently rewriting the row.
    let conn = test_conn();
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000000024', 'Default', ?1, ?2, ?2)",
        params![TEST_VER, NOW_TS],
    )
    .unwrap();
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-000000000012")
        .title("Drifted")
        .version(TEST_VER)
        .created_at(NOW_TS)
        .list_id(Some("01966a3f-7c8b-7d4e-8f3a-000000000024"))
        .insert(&conn);

    let undo = UndoToken {
        task_id: "01966a3f-7c8b-7d4e-8f3a-000000000012".to_string(),
        action: LifecycleAction::Complete, // expects post-state 'completed'
        cancel_series: false,
        pre_status: TaskStatus::Open,
        pre_completed_at: None,
        pre_planned_date: None,
        pre_defer_count: 0,
        pre_last_deferred_at: None,
        pre_last_defer_reason: None,
        spawned_successor_id: None,
        pre_task_snapshot: None,
        cancelled_reminder_ids: vec![],
        deleted_dep_edges: vec![],
        affected_dependent_ids: vec![],
        expires_at: (chrono::Utc::now() + chrono::Duration::seconds(60))
            .to_rfc3339_opts(chrono::SecondsFormat::Micros, true),
    };

    let err = apply_single_undo(&conn, &undo, NOW_TS)
        .expect_err("task not in post-state must be rejected");
    match err {
        AppError::Validation(msg) => {
            assert!(
                msg.contains("Cannot undo") && msg.contains("01966a3f-7c8b-7d4e-8f3a-000000000012"),
                "unexpected: {msg}"
            );
        }
        other => panic!("expected Validation, got {other:?}"),
    }
}

#[test]
fn undo_task_lifecycle_batch_rejects_empty_tokens() {
    // The frontend builds the batch from selection state. An empty
    // batch is a usage error (not a no-op) because the UI should
    // never hit the command with zero selections.
    let err = undo_task_lifecycle_batch(vec![]).expect_err("empty batch must be rejected");
    assert!(err.contains("No undo tokens"), "unexpected: {err}");
}
