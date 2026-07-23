use super::*;
use crate::commands::tasks::checklists::{
    add_task_checklist_item_with_conn, remove_task_checklist_item_with_conn,
    reorder_task_checklist_items_with_conn, set_task_checklist_item_completed_with_conn,
    update_task_checklist_item_text_with_conn,
};
use crate::commands::tasks::finalize_task_mutation;
use crate::commands::tasks::update_task_internal;
use crate::error::AppError;

#[allow(clippy::too_many_arguments)]
fn insert_task_for_task_commands_test(
    conn: &Connection,
    id: &str,
    title: &str,
    status: &str,
    due_date: Option<&str>,
    recurrence: Option<&str>,
    completed_at: Option<&str>,
    last_deferred_at: Option<&str>,
) {
    // Active series config: set canonical_occurrence_date + recurrence_group_id when recurrence is set.
    let has_recurrence = recurrence.is_some_and(|r| !r.is_empty());
    let canonical_occurrence_date = if has_recurrence { due_date } else { None };
    let recurrence_group_id: Option<String> = if has_recurrence {
        Some(uuid::Uuid::now_v7().to_string())
    } else {
        None
    };
    // Stays raw: TaskBuilder doesn't expose `canonical_occurrence_date`
    // or `last_deferred_at`, both load-bearing for the recurrence /
    // deferral lifecycle paths this helper feeds.
    conn.execute(
        "INSERT INTO tasks (
            id, title, status, due_date, recurrence, canonical_occurrence_date,
            recurrence_group_id, priority, completed_at, last_deferred_at,
            version, created_at, updated_at
        ) VALUES (
            ?1, ?2, ?3, ?4, ?5, ?6, ?7, 3, ?8, ?9, ?10, ?11, ?11
        )",
        params![
            id,
            title,
            status,
            due_date,
            recurrence,
            canonical_occurrence_date,
            recurrence_group_id,
            completed_at,
            last_deferred_at,
            TEST_VERSION,
            "2026-03-10T09:00:00Z"
        ],
    )
    .expect("insert task for task_commands test");
}

#[test]
fn update_task_internal_spawns_next_recurrence_from_updated_task_fields() {
    let conn = setup_sync_test_conn();
    insert_task_for_task_commands_test(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000c001",
        "Original title",
        "open",
        Some("2026-03-10"),
        Some("{\"FREQ\":\"DAILY\",\"INTERVAL\":1}"),
        None,
        None,
    );

    // `apply_lifecycle_transition` debug-asserts the
    // caller already opened a transaction. Production paths route
    // through `with_immediate_transaction`; tests must mirror that.
    let updated = with_immediate_transaction(&conn, |conn| {
        update_task_internal(
            conn,
            "01966a3f-7c8b-7d4e-8f3a-00000000c001",
            &json!({
                "status": "completed",
                "title": "Updated title",
                "due_date": "2026-03-12"
            }),
            "2026-03-10T09:00:00Z",
        )
    })
    .expect("complete recurring task through internal update flow");

    assert_eq!(updated.status, "completed");
    assert_eq!(updated.title, "Updated title");
    assert_eq!(updated.due_date.as_deref(), Some("2026-03-12"));

    let spawned = conn
        .query_row(
            &format!("SELECT {TASK_COLS} FROM tasks WHERE id != ?1"),
            params!["01966a3f-7c8b-7d4e-8f3a-00000000c001"],
            task_from_row,
        )
        .expect("load spawned recurring task");

    assert_eq!(spawned.status, "open");
    assert_eq!(spawned.title, "Updated title");
    // The workflow's recurrence spawner derives the next cadence step
    // from `sync_timestamp_now()` rather than a test-injected `now`,
    // so this test no longer pins a specific date — it just asserts a
    // spawned successor exists and its anchor + due_date line up.
    assert!(
        spawned.due_date.is_some(),
        "spawned successor must have a due_date"
    );
    assert_eq!(spawned.canonical_occurrence_date, spawned.due_date);
}

#[test]
fn update_task_internal_rejects_completed_to_cancelled() {
    let conn = setup_sync_test_conn();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-00000000ca01";
    insert_task_for_task_commands_test(
        &conn,
        task_id,
        "Needs cleanup",
        "completed",
        Some("2026-03-10"),
        None,
        Some("2026-03-09T08:00:00Z"),
        Some("2026-03-08T08:00:00Z"),
    );

    // `apply_lifecycle_transition` debug-asserts the
    // caller already opened a transaction. Production paths route
    // through `with_immediate_transaction`; tests must mirror that.
    let cancelled = with_immediate_transaction(&conn, |conn| {
        update_task_internal(
            conn,
            task_id,
            &json!({ "status": "cancelled" }),
            "2026-03-10T09:00:00Z",
        )
    })
    .expect_err("completed tasks must be reopened before cancelling");

    let message = cancelled.to_string();
    assert!(
        message.contains("from completed to cancelled"),
        "unexpected error: {message}"
    );
    assert!(message.contains(task_id), "unexpected error: {message}");
}

#[test]
fn update_task_internal_rejects_cancelled_to_completed() {
    let conn = setup_sync_test_conn();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-00000000ca02";
    insert_task_for_task_commands_test(
        &conn,
        task_id,
        "Needs completion",
        "cancelled",
        Some("2026-03-10"),
        None,
        None,
        Some("2026-03-08T08:00:00Z"),
    );

    // `apply_lifecycle_transition` debug-asserts the
    // caller already opened a transaction. Production paths route
    // through `with_immediate_transaction`; tests must mirror that.
    let completed = with_immediate_transaction(&conn, |conn| {
        update_task_internal(
            conn,
            task_id,
            &json!({ "status": "completed" }),
            "2026-03-10T09:00:00Z",
        )
    })
    .expect_err("cancelled tasks must be reopened before completion");

    let message = completed.to_string();
    assert!(
        message.contains("from cancelled to completed"),
        "unexpected error: {message}"
    );
    assert!(message.contains(task_id), "unexpected error: {message}");
}

#[test]
fn update_task_internal_clears_terminal_timestamps_when_reopening() {
    let conn = setup_sync_test_conn();
    insert_task_for_task_commands_test(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000c002",
        "Needs cleanup",
        "completed",
        Some("2026-03-10"),
        None,
        Some("2026-03-09T08:00:00Z"),
        Some("2026-03-08T08:00:00Z"),
    );

    // `apply_lifecycle_transition` debug-asserts the
    // caller already opened a transaction. Production paths route
    // through `with_immediate_transaction`; tests must mirror that.
    let reopened = with_immediate_transaction(&conn, |conn| {
        update_task_internal(
            conn,
            "01966a3f-7c8b-7d4e-8f3a-00000000c002",
            &json!({ "status": "open" }),
            "2026-03-10T09:00:00Z",
        )
    })
    .expect("reopen task through internal update flow");

    assert_eq!(reopened.status, "open");
    assert_eq!(reopened.completed_at, None);
    assert_eq!(reopened.last_deferred_at, None);
}

#[test]
fn update_task_internal_rejects_clearing_list_id() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES ('list-1', 'Personal', ?1, '2026-03-10T08:00:00Z', '2026-03-10T08:00:00Z')",
        params![TEST_VERSION],
    )
    .expect("insert test list");
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new("task-listed")
        .title("Keep classified")
        .version(TEST_VERSION)
        .created_at("2026-03-10T08:00:00Z")
        .list_id(Some("list-1"))
        .insert(&conn);

    let error = update_task_internal(
        &conn,
        "task-listed",
        &json!({ "list_id": null }),
        "2026-03-10T09:00:00Z",
    )
    .expect_err("clearing list_id should fail");

    assert!(error
        .to_string()
        .contains("Tasks must belong to a real list"));
}

#[test]
fn fetch_task_by_id_returns_not_found_for_missing_task() {
    let conn = setup_sync_test_conn();

    let error = fetch_task_by_id(&conn, "missing-task").expect_err("missing task should error");

    match error {
        AppError::NotFound(message) => {
            assert!(message.contains("missing-task"));
        }
        other => panic!("expected AppError::NotFound, got {other:?}"),
    }
}

#[test]
fn finalize_task_mutation_does_not_emit_data_changed_before_commit() {
    let conn = setup_sync_test_conn();
    insert_task_for_task_commands_test(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000c003",
        "Rollback Emit",
        "open",
        Some("2026-03-10"),
        None,
        None,
        None,
    );

    crate::event_bus::clear_test_emitted_data_changed();

    let error = with_immediate_transaction(&conn, |conn| {
        let _task = finalize_task_mutation(conn, "01966a3f-7c8b-7d4e-8f3a-00000000c003")?;
        Err::<crate::commands::Task, AppError>(AppError::Validation(
            "force rollback after finalize".to_string(),
        ))
    })
    .expect_err("transaction should roll back");

    assert!(
        error.to_string().contains("force rollback after finalize"),
        "unexpected error: {error}"
    );
    assert!(
        crate::event_bus::take_test_emitted_data_changed().is_empty(),
        "data-changed should not emit before commit"
    );
}

#[test]
fn task_checklist_commands_add_update_toggle_reorder_and_remove_items() {
    let conn = setup_sync_test_conn();
    insert_task_for_task_commands_test(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000c004",
        "Checklist task",
        "open",
        None,
        None,
        None,
        None,
    );

    let checklist_task_id =
        lorvex_domain::TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000c004".to_string());
    let first = add_task_checklist_item_with_conn(
        &conn,
        &checklist_task_id,
        "First item",
        None,
        "2026-03-10T09:00:00Z",
    )
    .expect("add first checklist item");
    let second = add_task_checklist_item_with_conn(
        &conn,
        &checklist_task_id,
        "Second item",
        None,
        "2026-03-10T09:00:01Z",
    )
    .expect("add second checklist item");
    let inserted = add_task_checklist_item_with_conn(
        &conn,
        &checklist_task_id,
        "Inserted item",
        Some(1),
        "2026-03-10T09:00:02Z",
    )
    .expect("insert checklist item at explicit position");

    assert_eq!(inserted.position, 1);

    let renamed = update_task_checklist_item_text_with_conn(
        &conn,
        &inserted.id,
        "Renamed item",
        "2026-03-10T09:00:03Z",
    )
    .expect("rename checklist item");
    assert_eq!(renamed.text, "Renamed item");

    let completed =
        set_task_checklist_item_completed_with_conn(&conn, &first.id, true, "2026-03-10T09:00:04Z")
            .expect("complete checklist item");
    assert!(completed.completed_at.is_some());

    let reordered = reorder_task_checklist_items_with_conn(
        &conn,
        &checklist_task_id,
        vec![second.id.clone(), inserted.id.clone(), first.id.clone()],
        "2026-03-10T09:00:05Z",
    )
    .expect("reorder checklist items");
    assert_eq!(
        reordered
            .iter()
            .map(|item| item.id.as_str())
            .collect::<Vec<_>>(),
        vec![second.id.as_str(), inserted.id.as_str(), first.id.as_str()]
    );
    assert_eq!(
        reordered
            .iter()
            .map(|item| item.position)
            .collect::<Vec<_>>(),
        vec![0, 1, 2]
    );

    remove_task_checklist_item_with_conn(&conn, &inserted.id, "2026-03-10T09:00:06Z")
        .expect("remove checklist item");

    let remaining = fetch_task_by_id(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000c004")
        .expect("reload task with checklist");
    let remaining_items = remaining
        .checklist_items
        .expect("task should still expose remaining checklist items");
    assert_eq!(remaining_items.len(), 2);
    assert_eq!(
        remaining_items
            .iter()
            .map(|item| item.id.as_str())
            .collect::<Vec<_>>(),
        vec![second.id.as_str(), first.id.as_str()]
    );
    assert_eq!(
        remaining_items
            .iter()
            .map(|item| item.position)
            .collect::<Vec<_>>(),
        vec![0, 1]
    );
}

/// a checklist mutation must advance the
/// parent task's `(version, updated_at)` AND emit a sync-outbox row for
/// the post-touch parent. Pre-fix `touch_parent_task_timestamp` bumped
/// only `updated_at`, leaving `version` stale and silently swallowing
/// every peer envelope that legitimately advanced the parent task. No
/// outbox row was emitted for the parent either, so peers never saw the
/// post-checklist parent state.
///
/// This test exercises the five callsites that funnel through
/// `touch_parent_task_timestamp` (add, update text, set completed,
/// remove, reorder) and after each mutation asserts:
///   1. the parent's `version` column changed (proves the HLC mint ran);
///   2. the parent's `version` parses as a canonical HLC string;
///   3. a sync_outbox row tagged `entity_type = ENTITY_TASK` /
///      `operation = OP_UPSERT` exists for the parent task id.
#[test]
fn task_checklist_mutations_bump_parent_task_version_and_enqueue_outbox() {
    use lorvex_domain::naming::{ENTITY_TASK, OP_UPSERT};

    let conn = setup_sync_test_conn();
    insert_task_for_task_commands_test(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000c005",
        "Parent task",
        "open",
        None,
        None,
        None,
        None,
    );

    fn read_parent_version(conn: &Connection) -> String {
        conn.query_row(
            "SELECT version FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-00000000c005'",
            [],
            |row| row.get::<_, String>(0),
        )
        .expect("read parent task version")
    }

    fn assert_parent_outbox_row_present(conn: &Connection, after_step: &str) {
        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sync_outbox \
                 WHERE entity_id = '01966a3f-7c8b-7d4e-8f3a-00000000c005' \
                   AND entity_type = ?1 AND operation = ?2",
                params![ENTITY_TASK, OP_UPSERT],
                |row| row.get(0),
            )
            .expect("count parent outbox rows");
        assert!(
            count >= 1,
            "expected parent task outbox upsert after {after_step} \
             (count={count})"
        );
    }

    fn assert_version_advanced(prev: &str, next: &str, after_step: &str) {
        assert_ne!(prev, next, "parent version must advance after {after_step}");
        assert!(
            lorvex_domain::hlc::Hlc::parse(next).is_ok(),
            "parent version after {after_step} must be a canonical HLC, got {next:?}"
        );
    }

    let v0 = read_parent_version(&conn);

    // Step 1: add an item.
    let parent_task_id =
        lorvex_domain::TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000c005".to_string());
    let added = add_task_checklist_item_with_conn(
        &conn,
        &parent_task_id,
        "Step one",
        None,
        "2026-04-26T09:00:00Z",
    )
    .expect("add checklist item");
    let v1 = read_parent_version(&conn);
    assert_version_advanced(&v0, &v1, "add");
    assert_parent_outbox_row_present(&conn, "add");

    // Step 2: update text.
    update_task_checklist_item_text_with_conn(
        &conn,
        &added.id,
        "Step one (updated)",
        "2026-04-26T09:00:01Z",
    )
    .expect("rename checklist item");
    let v2 = read_parent_version(&conn);
    assert_version_advanced(&v1, &v2, "update text");
    assert_parent_outbox_row_present(&conn, "update text");

    // Step 3: toggle completion.
    set_task_checklist_item_completed_with_conn(&conn, &added.id, true, "2026-04-26T09:00:02Z")
        .expect("complete checklist item");
    let v3 = read_parent_version(&conn);
    assert_version_advanced(&v2, &v3, "set completed");
    assert_parent_outbox_row_present(&conn, "set completed");

    // Step 4: reorder (need at least 2 items).
    let second = add_task_checklist_item_with_conn(
        &conn,
        &parent_task_id,
        "Step two",
        None,
        "2026-04-26T09:00:03Z",
    )
    .expect("add second checklist item");
    let v_after_second_add = read_parent_version(&conn);
    reorder_task_checklist_items_with_conn(
        &conn,
        &parent_task_id,
        vec![second.id.clone(), added.id],
        "2026-04-26T09:00:04Z",
    )
    .expect("reorder checklist items");
    let v4 = read_parent_version(&conn);
    assert_version_advanced(&v_after_second_add, &v4, "reorder");
    assert_parent_outbox_row_present(&conn, "reorder");

    // Step 5: remove an item.
    remove_task_checklist_item_with_conn(&conn, &second.id, "2026-04-26T09:00:05Z")
        .expect("remove checklist item");
    let v5 = read_parent_version(&conn);
    assert_version_advanced(&v4, &v5, "remove");
    assert_parent_outbox_row_present(&conn, "remove");
}

// ──────────────────────────────────────────────────────────────────────
// F1 (#3006-M18 follow-up): the Tauri `update_task` IPC now mirrors the
// MCP `RecurrenceRuleArgs` typed contract — the boundary accepts either
// a JSON object (`{"FREQ": ..., "INTERVAL": ..., ...}`) or null.
// Pre-fix it accepted a `Value::String` of stringified RRULE JSON,
// drifting from the MCP boundary that forbade strings. These tests
// pin the new shape, including:
//   * structured object → normalized + persisted on the row;
//   * null → recurrence cleared (existing behavior);
//   * legacy stringified JSON → rejected at the IPC boundary;
//   * undo replay restores the prior recurrence rule (which is stored
//     as a canonical JSON string) without surfacing the legacy-string
//     rejection at the boundary.
// ──────────────────────────────────────────────────────────────────────

#[test]
fn update_task_internal_accepts_typed_recurrence_object() {
    let conn = setup_sync_test_conn();
    insert_task_for_task_commands_test(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000c006",
        "Typed recurrence",
        "open",
        Some("2026-03-10"),
        None,
        None,
        None,
    );

    let updated = with_immediate_transaction(&conn, |conn| {
        update_task_internal(
            conn,
            "01966a3f-7c8b-7d4e-8f3a-00000000c006",
            // F1: the canonical IPC payload is a JSON object, NOT a
            // stringified blob. The boundary forwards it through
            // `lorvex_domain::validation::normalize_task_recurrence`,
            // which stamps INTERVAL=1 and emits the canonical
            // {FREQ, INTERVAL, BYDAY} key order.
            &json!({
                "recurrence": { "FREQ": "WEEKLY", "INTERVAL": 1, "BYDAY": ["MO", "WE", "FR"] }
            }),
            "2026-03-10T09:00:00Z",
        )
    })
    .expect("typed recurrence patch should apply");

    // The canonical normalizer emits keys in `serde_json::Map` order
    // (alphabetical when `preserve_order` is off). Spell out the
    // expected shape to lock the wire output instead of inferring
    // ordering — drift here would silently change the canonical
    // value stored on the row and ripple through every downstream
    // peer compare.
    assert_eq!(
        updated.recurrence.as_deref(),
        Some(r#"{"BYDAY":["MO","WE","FR"],"FREQ":"WEEKLY","INTERVAL":1}"#),
        "structured object must lower to canonical RRULE JSON"
    );
}

#[test]
fn update_task_internal_clears_recurrence_when_payload_is_null() {
    let conn = setup_sync_test_conn();
    insert_task_for_task_commands_test(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000c007",
        "Clear recurrence",
        "open",
        Some("2026-03-10"),
        Some("{\"FREQ\":\"DAILY\",\"INTERVAL\":1}"),
        None,
        None,
    );

    let updated = with_immediate_transaction(&conn, |conn| {
        update_task_internal(
            conn,
            "01966a3f-7c8b-7d4e-8f3a-00000000c007",
            &json!({ "recurrence": null }),
            "2026-03-10T09:00:00Z",
        )
    })
    .expect("null recurrence patch should clear the rule");

    assert_eq!(updated.recurrence, None);
}

#[test]
fn update_task_internal_decodes_stringified_recurrence_from_undo_snapshot() {
    // The undo-replay path snapshots `Task.recurrence` (a JSON-encoded
    // string column) and replays it through the update boundary. The
    // boundary therefore decodes a stringified recurrence into its
    // typed object form before handing it to the workflow — pre-
    // canonicalization. Malformed JSON in that string must still
    // surface a validation error.
    let conn = setup_sync_test_conn();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-00000000ca03";
    insert_task_for_task_commands_test(
        &conn,
        task_id,
        "Snapshot recurrence",
        "open",
        Some("2026-03-10"),
        None,
        None,
        None,
    );

    let error = update_task_internal(
        &conn,
        task_id,
        &json!({ "recurrence": "{not-json" }),
        "2026-03-10T09:00:00Z",
    )
    .expect_err("malformed snapshot recurrence string must surface a validation error");
    match error {
        AppError::Validation(message) => {
            assert!(
                message.contains("malformed recurrence JSON"),
                "expected the boundary decoder's error, got {message}"
            );
        }
        other => panic!("expected Validation, got {other:?}"),
    }
}

#[test]
fn update_task_undo_restores_recurrence_after_typed_clear() {
    use crate::commands::tasks::{apply_single_undo_for_tests, UndoToken};

    // F1: the undo path snapshots `Task.recurrence` (a stored JSON
    // string column) and replays it as part of an `update_task` patch.
    // After F1 the boundary rejects raw strings, so the undo helper
    // re-parses the snapshot's recurrence into the typed object form
    // before threading it back through the patch. Without that fix,
    // undo of a "clear recurrence" mutation would surface the new
    // "RecurrenceRuleArgs object" validation error at the IPC.
    let conn = setup_sync_test_conn();
    // Seed with the canonical (alphabetical) shape the normalizer
    // emits — undo replays through `normalize_task_recurrence` so a
    // non-canonical seed would re-canonicalize on the way back and
    // mask the round-trip we want to pin.
    let initial_rule = "{\"BYDAY\":[\"TU\"],\"FREQ\":\"WEEKLY\",\"INTERVAL\":1}";
    insert_task_for_task_commands_test(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000c008",
        "Undo recurring",
        "open",
        Some("2026-03-10"),
        Some(initial_rule),
        None,
        None,
    );
    // Seed the task's list_id with a UUID-shaped id so the workflow's
    // `validate_list_exists` accepts it during the undo-replay patch
    // (the undo path replays every field from the pre-mutation snapshot
    // including `list_id`).
    let list_id = "01966a3f-7c8b-7d4e-8f3a-00000000c000";
    conn.execute(
        "INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at)
         VALUES (?1, 'Inbox', ?2, '2026-03-10T08:00:00Z', '2026-03-10T08:00:00Z')",
        params![list_id, TEST_VERSION],
    )
    .expect("seed list");
    conn.execute(
        "UPDATE tasks SET list_id = ?1 WHERE id = '01966a3f-7c8b-7d4e-8f3a-00000000c008'",
        params![list_id],
    )
    .expect("repoint task list_id");

    // Forward: clear the recurrence (recurrence: null) — drives the
    // canonical "explicit clear" arm of the boundary's typed match.
    let now = "2026-03-10T09:00:00.000000Z";
    let result = with_immediate_transaction(&conn, |conn| {
        crate::commands::tasks::update_task_inner_with_conn(
            conn,
            "01966a3f-7c8b-7d4e-8f3a-00000000c008",
            &json!({ "recurrence": null }),
        )
    })
    .expect("clear recurrence forward update");
    assert_eq!(result.task.recurrence, None);

    // Undo: replay the snapshot. Pre-fix this would surface the new
    // "RecurrenceRuleArgs object" validation error because the
    // snapshot's `recurrence` was still a JSON-string column value.
    let undo: UndoToken = serde_json::from_str(&result.undo_token).expect("parse undo token");
    let restored =
        with_immediate_transaction(&conn, |conn| apply_single_undo_for_tests(conn, &undo, now))
            .expect("undo of typed-clear should restore the original rule");
    assert_eq!(
        restored.recurrence.as_deref(),
        Some(initial_rule),
        "undo must restore the canonical pre-mutation recurrence rule",
    );
}
