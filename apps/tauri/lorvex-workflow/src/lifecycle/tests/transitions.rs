use super::super::*;
use super::support::{
    run_cancel_in_tx, run_completion_in_tx, run_reopen_in_tx, seed_status_task, test_conn, tid,
};
use lorvex_domain::naming::TaskStatus;
use lorvex_store::transaction::with_immediate_transaction;
use lorvex_store::StoreError;

#[test]
fn completion_rejects_cancelled_task_at_shared_layer() {
    let conn = test_conn();
    seed_status_task(
        &conn,
        "cancelled-to-completed",
        lorvex_domain::naming::STATUS_CANCELLED,
    );

    let err = run_completion_in_tx(
        &conn,
        "cancelled-to-completed",
        "2026-04-20T09:00:00Z",
        "0000000000001_0000_a0a0a0a0a0a0a0a0",
    )
    .expect_err("terminal-to-terminal transition must be rejected");

    assert!(matches!(err, StoreError::Validation(_)));
    let status: String = conn
        .query_row(
            "SELECT status FROM tasks WHERE id = 'cancelled-to-completed'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(status, lorvex_domain::naming::STATUS_CANCELLED);
}

#[test]
fn cancellation_rejects_completed_task_at_shared_layer() {
    let conn = test_conn();
    seed_status_task(
        &conn,
        "completed-to-cancelled",
        lorvex_domain::naming::STATUS_COMPLETED,
    );

    let err = run_cancel_in_tx(
        &conn,
        "completed-to-cancelled",
        "2026-04-20T09:00:00Z",
        "0000000000001_0000_a0a0a0a0a0a0a0",
        false,
    )
    .expect_err("terminal-to-terminal transition must be rejected");

    assert!(matches!(err, StoreError::Validation(_)));
    let status: String = conn
        .query_row(
            "SELECT status FROM tasks WHERE id = 'completed-to-cancelled'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(status, lorvex_domain::naming::STATUS_COMPLETED);
}

#[test]
fn generic_lifecycle_transition_rejects_terminal_to_terminal_status_patch() {
    let conn = test_conn();
    seed_status_task(
        &conn,
        "generic-terminal-drift",
        lorvex_domain::naming::STATUS_COMPLETED,
    );

    let err = with_immediate_transaction(&conn, |c| {
        apply_lifecycle_transition(
            c,
            &tid("generic-terminal-drift"),
            TaskStatus::Completed,
            TaskStatus::Cancelled,
            "2026-04-20T09:00:00Z",
            "0000000000001_0000_a0a0a0a0a0a0a0a0",
        )
    })
    .expect_err("terminal-to-terminal generic status patch must be rejected");

    assert!(matches!(err, StoreError::Validation(_)));
}

#[test]
fn completion_rejects_unparseable_persisted_status_before_mutation() {
    let conn = test_conn();
    conn.execute("PRAGMA ignore_check_constraints = ON", [])
        .unwrap();
    conn.execute(
        "INSERT INTO tasks (id, title, status, version, created_at, updated_at)
         VALUES ('corrupt-status', 'Corrupt status', 'in_review',
                 '0000000000000_0000_0000000000000000',
                 '2026-04-20T00:00:00Z', '2026-04-20T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute("PRAGMA ignore_check_constraints = OFF", [])
        .unwrap();

    let err = run_completion_in_tx(
        &conn,
        "corrupt-status",
        "2026-04-20T09:00:00Z",
        "0000000000001_0000_a0a0a0a0a0a0a0a0",
    )
    .expect_err("corrupt persisted task status must fail before status mutation");

    assert!(
        matches!(err, StoreError::Invariant(ref message)
            if message.contains("corrupt-status") && message.contains("in_review")),
        "unexpected error for corrupt persisted task status: {err:?}"
    );
    let (status, completed_at): (String, Option<String>) = conn
        .query_row(
            "SELECT status, completed_at FROM tasks WHERE id = 'corrupt-status'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(status, "in_review");
    assert!(completed_at.is_none());
}

#[test]
fn apply_reopen_transition_cancels_spawned_successor_and_collects_side_effects() {
    let conn = test_conn();
    lorvex_store::test_support::TaskBuilder::new("parent")
        .title("Recurring Parent")
        .status(lorvex_domain::naming::STATUS_COMPLETED)
        .due_date(Some("2026-03-25"))
        .canonical_occurrence_date("2026-03-25")
        .recurrence(r#"{"freq":"daily"}"#)
        .recurrence_group_id("grp-parent")
        .completed_at(Some("2026-03-25T08:00:00Z"))
        .created_at("2026-03-20T00:00:00Z")
        .insert(&conn);
    lorvex_store::test_support::TaskBuilder::new("succ")
        .title("Recurring Parent")
        .due_date(Some("2026-03-26"))
        .canonical_occurrence_date("2026-03-26")
        .recurrence(r#"{"freq":"daily"}"#)
        .recurrence_group_id("grp-parent")
        .spawned_from("parent")
        .version("0000000000000_0000_0000000000000001")
        .created_at("2026-03-20T00:00:00Z")
        .insert(&conn);
    lorvex_store::test_support::TaskBuilder::new("prereq")
        .title("Prereq")
        .version("0000000000000_0000_0000000000000002")
        .created_at("2026-03-20T00:00:00Z")
        .insert(&conn);
    lorvex_store::test_support::TaskBuilder::new("dependent")
        .title("Dependent")
        .version("0000000000000_0000_0000000000000003")
        .created_at("2026-03-20T00:00:00Z")
        .insert(&conn);
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES ('rem-succ', 'succ', '2026-03-26T09:00:00Z', '0000000000000_0000_0000000000000004', '2026-03-20T00:00:00Z')",
        [],
    ).unwrap();
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at)
         VALUES ('succ', 'prereq', '0000000000000_0000_0000000000000005', '2026-03-20T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at)
         VALUES ('dependent', 'succ', '0000000000000_0000_0000000000000006', '2026-03-20T00:00:00Z')",
        [],
    )
    .unwrap();
    let result = run_reopen_in_tx(
        &conn,
        "parent",
        lorvex_domain::naming::STATUS_COMPLETED,
        "2026-03-27T10:00:00Z",
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
    )
    .unwrap();
    assert!(result.updated);
    assert_eq!(
        result.transition.cancelled_successor_ids,
        vec!["succ".to_string()]
    );
    assert_eq!(
        result
            .transition
            .successor_cancel_side_effects
            .cancelled_reminder_ids,
        vec!["rem-succ".to_string()]
    );
    assert_eq!(
        result
            .transition
            .successor_cancel_side_effects
            .affected_dependent_ids,
        vec!["dependent".to_string()]
    );
    assert_eq!(
        result
            .transition
            .successor_cancel_side_effects
            .deleted_dependency_edges
            .len(),
        2
    );
    let successor_status: String = conn
        .query_row("SELECT status FROM tasks WHERE id = 'succ'", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(successor_status, lorvex_domain::naming::STATUS_CANCELLED);
    let remaining_edges: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_dependencies
         WHERE task_id IN ('succ', 'dependent') OR depends_on_task_id IN ('succ', 'dependent')",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(remaining_edges, 0);
}

#[test]
fn completion_transition_propagates_successor_tag_copy_failures() {
    let conn = test_conn();
    lorvex_store::test_support::TaskBuilder::new("recurring")
        .title("Recurring")
        .due_date(Some("2026-03-25"))
        .canonical_occurrence_date("2026-03-25")
        .recurrence(r#"{"FREQ":"DAILY"}"#)
        .recurrence_group_id("grp-recurring")
        .created_at("2026-03-10T00:00:00Z")
        .insert(&conn);
    conn.execute("DROP TABLE task_tags", []).unwrap();
    let err = run_completion_in_tx(
        &conn,
        "recurring",
        "2026-03-25T10:00:00Z",
        "0000000000000_0000_test0003",
    )
    .unwrap_err();
    assert!(matches!(err, StoreError::Sql(_)));
}
#[test]
fn reopen_transition_propagates_successor_cancel_failures() {
    let conn = test_conn();
    lorvex_store::test_support::TaskBuilder::new("parent")
        .title("Recurring Parent")
        .status(lorvex_domain::naming::STATUS_COMPLETED)
        .due_date(Some("2026-03-25"))
        .canonical_occurrence_date("2026-03-25")
        .recurrence(r#"{"FREQ":"DAILY"}"#)
        .recurrence_group_id("grp-parent")
        .completed_at(Some("2026-03-25T08:00:00Z"))
        .created_at("2026-03-20T00:00:00Z")
        .insert(&conn);
    lorvex_store::test_support::TaskBuilder::new("succ")
        .title("Recurring Parent")
        .due_date(Some("2026-03-26"))
        .canonical_occurrence_date("2026-03-26")
        .recurrence(r#"{"FREQ":"DAILY"}"#)
        .recurrence_group_id("grp-parent")
        .spawned_from("parent")
        .version("0000000000000_0000_0000000000000001")
        .created_at("2026-03-20T00:00:00Z")
        .insert(&conn);
    conn.execute("DROP TABLE task_dependencies", []).unwrap();
    let err = run_reopen_in_tx(
        &conn,
        "parent",
        lorvex_domain::naming::STATUS_COMPLETED,
        "2026-03-27T10:00:00Z",
        "0000000000000_0000_test0004",
    )
    .unwrap_err();
    assert!(matches!(err, StoreError::Sql(_)));
}
#[test]
fn completion_transition_surfaces_timezone_preference_lookup_failures() {
    let conn = test_conn();
    lorvex_store::test_support::TaskBuilder::new("recurring")
        .title("Recurring")
        .due_date(Some("2026-03-25"))
        .canonical_occurrence_date("2026-03-25")
        .recurrence(r#"{"FREQ":"DAILY"}"#)
        .recurrence_group_id("grp-recurring")
        .created_at("2026-03-10T00:00:00Z")
        .insert(&conn);
    conn.execute("DROP TABLE preferences", []).unwrap();
    let err = run_completion_in_tx(
        &conn,
        "recurring",
        "2026-03-25T10:00:00Z",
        "0000000000000_0000_test0004",
    )
    .unwrap_err();
    assert!(matches!(err, StoreError::Sql(_)));
}
#[test]
fn completion_transition_rejects_malformed_timezone_preference() {
    let conn = test_conn();
    lorvex_store::test_support::TaskBuilder::new("recurring")
        .title("Recurring")
        .due_date(Some("2026-03-25"))
        .canonical_occurrence_date("2026-03-25")
        .recurrence(r#"{"FREQ":"DAILY"}"#)
        .recurrence_group_id("grp-recurring")
        .created_at("2026-03-10T00:00:00Z")
        .insert(&conn);
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at)
         VALUES ('timezone', '\"definitely-not-a-timezone\"', '0000000000000_0000_0000000000000001', '2026-03-10T00:00:00Z')",
        [],
    )
    .unwrap();
    let err = run_completion_in_tx(
        &conn,
        "recurring",
        "2026-03-25T10:00:00Z",
        "0000000000000_0000_test0005",
    )
    .unwrap_err();
    assert!(matches!(err, StoreError::Validation(_)));
}
#[test]
fn completion_transition_rejects_invalid_now_timestamp() {
    let conn = test_conn();
    lorvex_store::test_support::TaskBuilder::new("recurring")
        .title("Recurring")
        .due_date(Some("2026-03-25"))
        .canonical_occurrence_date("2026-03-25")
        .recurrence(r#"{"FREQ":"DAILY"}"#)
        .recurrence_group_id("grp-recurring")
        .created_at("2026-03-10T00:00:00Z")
        .insert(&conn);
    let err = run_completion_in_tx(
        &conn,
        "recurring",
        "not-a-timestamp",
        "0000000000000_0000_test0006",
    )
    .unwrap_err();
    assert!(matches!(err, StoreError::Validation(_)));
}

// -----------------------------------------------------------------------
// transactional discipline — every orchestrator must run inside a
// `with_immediate_transaction` so multi-step writes commit/rollback
// atomically. Each `apply_*_transition` `debug_assert!`s on
// `conn.is_autocommit()`.
// -----------------------------------------------------------------------

/// `apply_lifecycle_transition`
/// must run inside a transaction. The function performs a multi-step
/// write (status row + cascade side effects + recurrence spawn +
/// successor cancel), so a panic between steps would leave divergent
/// state if the caller forgot to wrap it. The runtime guard is a
/// `debug_assert!` on `conn.is_autocommit()`.
#[test]
#[should_panic(expected = "must run inside a transaction")]
fn apply_lifecycle_transition_panics_in_autocommit_in_debug_builds() {
    let conn = test_conn();
    lorvex_store::test_support::TaskBuilder::new("autocommit-victim")
        .title("A")
        .created_at("2026-04-19T00:00:00Z")
        .insert(&conn);
    // Connection is in autocommit mode (no outer BEGIN); the
    // debug_assert in apply_lifecycle_transition must fire.
    let _ = apply_lifecycle_transition(
        &conn,
        &tid("autocommit-victim"),
        TaskStatus::Open,
        TaskStatus::Completed,
        "2026-04-19T00:00:00Z",
        "0000000000000_0000_0000000000000001",
    );
}

/// the dedicated cancel surface performs
/// the same cancel-then-spawn multi-step write and therefore needs
/// the same in-transaction guard so partial-failure recovery rolls
/// back to a coherent state.
#[test]
#[should_panic(expected = "must run inside a transaction")]
fn apply_cancel_transition_panics_in_autocommit_in_debug_builds() {
    let conn = test_conn();
    lorvex_store::test_support::TaskBuilder::new("autocommit-cancel")
        .title("A")
        .created_at("2026-04-19T00:00:00Z")
        .insert(&conn);
    let _ = apply_cancel_transition(
        &conn,
        &tid("autocommit-cancel"),
        "2026-04-19T00:00:00Z",
        "0000000000000_0000_0000000000000001",
        false,
        None,
    );
}

/// the dedicated completion surface owns
/// status mutation + recurrence spawn and therefore needs the same
/// in-transaction guard.
#[test]
#[should_panic(expected = "must run inside a transaction")]
fn apply_completion_transition_panics_in_autocommit_in_debug_builds() {
    let conn = test_conn();
    lorvex_store::test_support::TaskBuilder::new("autocommit-complete")
        .title("A")
        .created_at("2026-04-19T00:00:00Z")
        .insert(&conn);
    let _ = apply_completion_transition(
        &conn,
        &tid("autocommit-complete"),
        "2026-04-19T00:00:00Z",
        "0000000000000_0000_0000000000000001",
    );
}

/// the dedicated reopen surface owns
/// status mutation + successor cancel cascade and therefore needs the
/// same in-transaction guard.
#[test]
#[should_panic(expected = "must run inside a transaction")]
fn apply_reopen_transition_panics_in_autocommit_in_debug_builds() {
    let conn = test_conn();
    lorvex_store::test_support::TaskBuilder::new("autocommit-reopen")
        .title("A")
        .status(lorvex_domain::naming::STATUS_COMPLETED)
        .completed_at(Some("2026-04-19T00:00:00Z"))
        .created_at("2026-04-19T00:00:00Z")
        .insert(&conn);
    let _ = apply_reopen_transition(
        &conn,
        &tid("autocommit-reopen"),
        TaskStatus::Completed,
        "2026-04-19T00:00:00Z",
        "0000000000000_0000_0000000000000001",
    );
}
