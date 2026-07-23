//! `complete_task` and `cancel_task`: terminal-state guards plus the
//! typed dependency-edge tombstone that fires from the cancel
//! cascade.

use super::support::*;

#[test]
#[serial_test::serial(hlc)]
fn complete_task_rejects_cancelled_task() {
    let _hlc_guard = crate::runtime::change_tracking::hlc_test_mutex()
        .lock()
        .expect("hlc test mutex");
    crate::runtime::change_tracking::reset_thread_hlc_for_tests();
    let conn = open_temp_db();
    let now = "2026-04-20T00:00:00Z";
    lorvex_store::test_support::TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-000000000117")
        .title("Cancelled Complete")
        .status("cancelled")
        .version("0000000000000_0000_0000000000000000")
        .created_at(now)
        .insert(&conn);

    conn.execute_batch("BEGIN IMMEDIATE;")
        .expect("begin immediate");
    let error = complete_task(
        &conn,
        CompleteTaskArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-000000000117".to_string(),
            idempotency_key: None,
        },
    )
    .expect_err("cancelled tasks must be reopened before completion");
    conn.execute_batch("COMMIT;")
        .expect("commit unchanged transaction");

    assert!(
        error.to_string().contains("from cancelled to completed"),
        "unexpected error: {error}"
    );

    let status: String = conn
        .query_row(
            "SELECT status FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000117'",
            [],
            |row| row.get(0),
        )
        .expect("load task status");
    assert_eq!(status, "cancelled");

    let side_effect_count: i64 = conn
        .query_row(
            "SELECT
                (SELECT COUNT(*) FROM sync_outbox WHERE entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000117') +
                (SELECT COUNT(*) FROM ai_changelog WHERE entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000117')",
            [],
            |row| row.get(0),
        )
        .expect("count side effects");
    assert_eq!(
        side_effect_count, 0,
        "rejected completion must not enqueue sync or changelog side effects"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn complete_task_logs_focus_rewire_audit_at_mcp_boundary_without_duplicate_aggregate_sync() {
    let _hlc_guard = crate::runtime::change_tracking::hlc_test_mutex()
        .lock()
        .expect("hlc test mutex");
    crate::runtime::change_tracking::reset_thread_hlc_for_tests();
    let conn = open_temp_db();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-00000000013a";
    lorvex_store::test_support::TaskBuilder::new(task_id)
        .title("Daily rewire")
        .due_date(Some("2099-05-20"))
        .canonical_occurrence_date("2099-05-20")
        .recurrence(r#"{"FREQ":"DAILY","INTERVAL":1}"#)
        .recurrence_group_id("grp-mcp-rewire")
        .version("0000000000000_0000_0000000000000000")
        .created_at("2099-05-19T00:00:00Z")
        .insert(&conn);
    conn.execute(
        "INSERT OR IGNORE INTO focus_schedule \
            (date, rationale, timezone, version, created_at, updated_at) \
         VALUES ('2099-05-20', NULL, 'UTC', '0000000000000_0000_00000000000000aa', ?1, ?1)",
        ["2099-05-19T00:00:00Z"],
    )
    .expect("seed focus schedule");
    conn.execute(
        "INSERT INTO focus_schedule_blocks \
            (schedule_date, position, block_type, start_time, end_time, task_id, event_id, title) \
         VALUES ('2099-05-20', 0, 'task', 540, 600, ?1, NULL, 'Morning slot')",
        [task_id],
    )
    .expect("seed focus schedule block");
    conn.execute(
        "INSERT OR IGNORE INTO current_focus \
            (date, briefing, timezone, version, created_at, updated_at) \
         VALUES ('2099-05-20', NULL, 'UTC', '0000000000000_0000_00000000000000bb', ?1, ?1)",
        ["2099-05-19T00:00:00Z"],
    )
    .expect("seed current focus");
    conn.execute(
        "INSERT INTO current_focus_items (date, position, task_id) VALUES ('2099-05-20', 0, ?1)",
        [task_id],
    )
    .expect("seed current focus item");

    conn.execute_batch("BEGIN IMMEDIATE;")
        .expect("begin immediate");
    complete_task(
        &conn,
        CompleteTaskArgs {
            id: task_id.to_string(),
            idempotency_key: None,
        },
    )
    .expect("complete recurring task");
    conn.execute_batch("COMMIT;").expect("commit");

    let rewire_rows: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog
             WHERE operation = 'recurrence_rewire'
               AND mcp_tool = 'complete_task'
               AND entity_type IN ('focus_schedule', 'current_focus')
               AND entity_id = '2099-05-20'",
            [],
            |row| row.get(0),
        )
        .expect("count recurrence rewire audit rows");
    assert_eq!(
        rewire_rows, 2,
        "MCP lifecycle boundary should log one rewire audit row per aggregate root"
    );

    let focus_schedule_syncs: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = 'focus_schedule'
               AND entity_id = '2099-05-20'
               AND operation = 'upsert'",
            [],
            |row| row.get(0),
        )
        .expect("count focus_schedule syncs");
    assert_eq!(
        focus_schedule_syncs, 1,
        "recurrence_rewire audit rows must skip duplicate aggregate sync; flush_sync_plan already enqueues it"
    );

    let current_focus_syncs: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = 'current_focus'
               AND entity_id = '2099-05-20'
               AND operation = 'upsert'",
            [],
            |row| row.get(0),
        )
        .expect("count current_focus syncs");
    assert_eq!(
        current_focus_syncs, 1,
        "recurrence_rewire audit rows must skip duplicate aggregate sync; flush_sync_plan already enqueues it"
    );
}

/// `enqueue_deleted_task_dependency_syncs` was the
/// last #2818-class delete helper still emitting degenerate
/// `{"id": entity_id}` payloads. Cancel a task with an active
/// dependency, then assert the resulting EDGE_TASK_DEPENDENCY DELETE
/// envelope carries the typed struct's `(task_id, depends_on_task_id,
/// version, created_at)` — not the fallback `{"id": ...}` shape.
#[test]
#[serial_test::serial(hlc)]
fn cancel_task_dependency_tombstone_carries_typed_struct_fields() {
    let _hlc_guard = crate::runtime::change_tracking::hlc_test_mutex()
        .lock()
        .expect("hlc test mutex");
    crate::runtime::change_tracking::reset_thread_hlc_for_tests();
    let conn = open_temp_db();
    let now = "2026-04-04T00:00:00Z";
    let dep_version = "0000000000001_0000_0000000000000000";
    seed_task_with_version(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000011c",
        "Cancelled",
        "0000000000000_0000_0000000000000000",
        now,
    );
    seed_task_with_version(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001001",
        "Dependent",
        "0000000000000_0000_0000000000000000",
        now,
    );
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000001001', '01966a3f-7c8b-7d4e-8f3a-00000000011c', ?1, ?2)",
        rusqlite::params![dep_version, now],
    )
    .expect("insert dependency");

    // The shared `apply_cancel_transition` invariant (#2901-M18 +
    // ancestors) requires every caller to run inside an open
    // transaction so the cancel + side-effect cascade commits
    // atomically. Production MCP tools wrap each call in
    // `BEGIN IMMEDIATE; ... COMMIT;` (see `server.rs::with_busy_retry`
    // → `with_savepoint_mapped`); the test must do the same.
    conn.execute_batch("BEGIN IMMEDIATE;")
        .expect("begin immediate");
    cancel_task(
        &conn,
        CancelTaskArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-00000000011c".to_string(),
            reason: None,
            cancel_series: None,
            idempotency_key: None,
            dry_run: false,
        },
    )
    .expect("cancel task");
    conn.execute_batch("COMMIT;").expect("commit");

    // Find the dependency-edge tombstone in the outbox.
    let entity_id = "01966a3f-7c8b-7d4e-8f3a-000000001001:01966a3f-7c8b-7d4e-8f3a-00000000011c";
    let payload_text: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox
             WHERE entity_type = 'task_dependency' AND entity_id = ?1
               AND operation = 'delete'
             ORDER BY id DESC LIMIT 1",
            [entity_id],
            |row| row.get(0),
        )
        .expect("dependency tombstone in outbox");
    let payload: Value =
        serde_json::from_str(&payload_text).expect("dependency tombstone payload is JSON");

    // Pre-fix the payload was `{"id": "01966a3f-7c8b-7d4e-8f3a-000000001001:01966a3f-7c8b-7d4e-8f3a-00000000011c"}`.
    // Post-fix the payload mirrors the pre-delete row shape sourced
    // from the typed `DeletedDependencyEdge` struct.
    assert_eq!(
        payload.get("task_id").and_then(Value::as_str),
        Some("01966a3f-7c8b-7d4e-8f3a-000000001001"),
        "dependency tombstone must carry task_id from the typed struct"
    );
    assert_eq!(
        payload.get("depends_on_task_id").and_then(Value::as_str),
        Some("01966a3f-7c8b-7d4e-8f3a-00000000011c"),
        "dependency tombstone must carry depends_on_task_id from the typed struct"
    );
    assert_eq!(
        payload.get("created_at").and_then(Value::as_str),
        Some(now),
        "dependency tombstone must carry the edge's pre-delete created_at"
    );
    // `version` is overwritten by the outbox HLC stamp at
    // `enqueue_payload_internal_body` (line 509-518) for both upserts
    // and deletes, so we can't pin the pre-delete value here. What we
    // CAN pin is that the field is present (i.e. the typed snapshot
    // path, not the degenerate fallback, produced the payload — the
    // fallback shape `{"id": entity_id}` had no `version` slot at
    // all before the outbox stamp re-injected one).
    assert!(
        payload.get("version").is_some(),
        "dependency tombstone must carry a version field"
    );
    // The pre-fix degenerate payload had a top-level `id` field. The
    // task_dependencies schema has no `id` column (composite PK), so
    // a typed snapshot must NOT manufacture one — its presence would
    // mean we fell through to the outbox snapshot fallback.
    assert!(
        payload.get("id").is_none(),
        "dependency tombstone must not carry a synthesized 'id' field — task_dependencies is a composite-PK relation, the pre-fix `{{\"id\": entity_id}}` fallback is the bug"
    );
    // Suppress unused-variable warning on the seed version.
    let _ = dep_version;
}

#[test]
#[serial_test::serial(hlc)]
fn cancel_task_with_reason_writes_ai_notes() {
    let _hlc_guard = crate::runtime::change_tracking::hlc_test_mutex()
        .lock()
        .expect("hlc test mutex");
    crate::runtime::change_tracking::reset_thread_hlc_for_tests();
    let conn = open_temp_db();
    let now = "2026-04-20T00:00:00Z";
    lorvex_store::test_support::TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-00000000012b")
        .title("Reason cancel")
        .status("open")
        .version("0000000000000_0000_0000000000000000")
        .created_at(now)
        .insert(&conn);

    conn.execute_batch("BEGIN IMMEDIATE;")
        .expect("begin immediate");
    cancel_task(
        &conn,
        CancelTaskArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-00000000012b".to_string(),
            reason: Some("no longer needed".to_string()),
            cancel_series: None,
            idempotency_key: None,
            dry_run: false,
        },
    )
    .expect("cancel task with reason");
    conn.execute_batch("COMMIT;").expect("commit cancel");

    let ai_notes: Option<String> = conn
        .query_row(
            "SELECT ai_notes
             FROM tasks
             WHERE id = '01966a3f-7c8b-7d4e-8f3a-00000000012b'",
            [],
            |row| row.get(0),
        )
        .expect("load cancelled task notes");

    assert_eq!(ai_notes.as_deref(), Some("Cancelled: no longer needed"));
}
