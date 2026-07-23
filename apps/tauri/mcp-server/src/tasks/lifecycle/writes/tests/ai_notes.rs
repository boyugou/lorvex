//! `set_task_ai_notes`: current assistant-context replacement and the
//! mandatory parent-task `version` bump (#2975-H2).

use super::support::*;

#[test]
#[serial_test::serial(hlc)]
fn set_task_ai_notes_replaces_current_context() {
    let conn = open_temp_db();
    let now = "2026-03-01T00:00:00Z";
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-00000000011d")
        .title("Task 1")
        .created_at(now)
        .insert(&conn);

    let response = set_task_ai_notes(
        &conn,
        SetTaskAiNotesArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-00000000011d".to_string(),
            notes: "Needs clearer execution steps".to_string(),
            idempotency_key: None,
        },
    )
    .expect("set task ai notes");

    let payload: Value = serde_json::from_str(&response).expect("parse set_task_ai_notes response");
    let notes = payload
        .get("ai_notes")
        .and_then(Value::as_str)
        .expect("ai notes string");
    assert_eq!(notes, "Needs clearer execution steps");
}

/// pre-fix task AI note UPDATE wrote `ai_notes` and `updated_at` but
/// left `version` untouched. Peer LWW (`excluded.version > tasks.version`)
/// silently dropped the resulting upsert envelope. Pin the bump.
#[test]
#[serial_test::serial(hlc)]
fn set_task_ai_notes_bumps_parent_task_version() {
    let conn = open_temp_db();
    let now = "2026-04-01T00:00:00Z";
    let initial_version = "0000000000000_0000_0000000000000000";
    seed_task_with_version(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000115",
        "Task H2",
        initial_version,
        now,
    );

    let (before_version, _) =
        read_task_version_updated(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000115");
    assert_eq!(before_version, initial_version);

    set_task_ai_notes(
        &conn,
        SetTaskAiNotesArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-000000000115".to_string(),
            notes: "Investigate flaky test".to_string(),
            idempotency_key: None,
        },
    )
    .expect("set task ai notes");

    let (after_version, _) =
        read_task_version_updated(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000115");
    assert_ne!(
        after_version, initial_version,
        "set_task_ai_notes must mint a fresh HLC version on the parent task"
    );
    assert!(
        after_version.as_str() > initial_version,
        "fresh HLC must be strictly greater than the seed (#2975-H2)"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn set_task_ai_notes_rejects_stale_parent_version_without_mutating_notes() {
    let conn = open_temp_db();
    let now = "2026-04-01T00:00:00Z";
    let stale_barrier = "9999999999999_0000_ffffffffffffffff";
    let task_id = "01966a3f-7c8b-7d4e-8f3a-000000000615";
    seed_task_with_version(&conn, task_id, "Task stale AI notes", stale_barrier, now);

    let err = set_task_ai_notes(
        &conn,
        SetTaskAiNotesArgs {
            id: task_id.to_string(),
            notes: "must not land under a stale local stamp".to_string(),
            idempotency_key: None,
        },
    )
    .expect_err("stale set_task_ai_notes must reject");

    match err {
        McpError::Store(store_err)
            if matches!(*store_err, lorvex_store::StoreError::StaleVersion { .. }) =>
        {
            let lorvex_store::StoreError::StaleVersion { entity, id } = *store_err else {
                unreachable!()
            };
            assert_eq!(entity, lorvex_domain::naming::ENTITY_TASK);
            assert_eq!(id, task_id);
        }
        other => panic!("expected stale-version error, got {other:?}"),
    }

    let (ai_notes, version): (Option<String>, String) = conn
        .query_row(
            "SELECT ai_notes, version FROM tasks WHERE id = ?1",
            [task_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read task after rejected ai notes");
    assert!(ai_notes.is_none());
    assert_eq!(version, stale_barrier);
}
