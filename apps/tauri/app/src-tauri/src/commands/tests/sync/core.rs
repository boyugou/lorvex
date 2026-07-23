use super::*;

#[test]
fn compare_sync_versions_uses_lexicographic_hlc_ordering() {
    // Older HLC version sorts before newer.
    let older = compare_sync_versions(
        "0001711000000_0001_6465766963656231",
        "0001711060000_0001_6465766963656131",
    );
    assert!(older.is_lt());

    // Equal versions compare equal.
    let equal = compare_sync_versions(
        "0001711060000_0001_6465766963657a31",
        "0001711060000_0001_6465766963657a31",
    );
    assert!(equal.is_eq());
}
#[test]
fn latest_entity_sync_version_prefers_higher_version() {
    let conn = setup_sync_test_conn();
    conn.execute(
        "INSERT INTO sync_outbox (
            entity_type, entity_id, operation, version, payload_schema_version, payload, device_id, created_at, synced_at, retry_count
         ) VALUES ('task', 'task-poisoned', 'upsert', '0001711000000_0001_6465766963656131', 1, '{}', 'device-a', '2026-03-05T09:00:00Z', '2026-03-05T09:00:00Z', 0)",
        [],
    )
    .expect("insert lower version sync outbox entry");
    let good_id: i64 = {
        conn.execute(
            "INSERT INTO sync_outbox (
                entity_type, entity_id, operation, version, payload_schema_version, payload, device_id, created_at, synced_at, retry_count
             ) VALUES ('task', 'task-poisoned', 'upsert', '0001711060000_0001_6465766963656231', 1, '{}', 'device-b', '2026-03-05T10:00:00Z', '2026-03-05T10:00:00Z', 0)",
            [],
        )
        .expect("insert higher version sync outbox entry");
        conn.last_insert_rowid()
    };

    let latest = latest_entity_sync_version(&conn, "task", "task-poisoned")
        .expect("resolve latest sync version")
        .expect("latest sync version should exist");

    assert_eq!(latest.0, good_id.to_string());
}

#[test]
fn file_sync_idempotency_treats_semantically_identical_payload_json_as_equal() {
    let existing = make_sync_event(
        "event-1",
        "task",
        "task-1",
        "upsert",
        serde_json::json!({"id":"task-1","title":"Write tests","status":"open"}),
        "0001711060000_0001_6465766963656131",
        "device-a",
    );
    let outgoing = IncomingSyncRecord {
        envelope: lorvex_sync::envelope::SyncEnvelope {
            payload: r#"{"status":"open","updated_at":"0001711060000_0001_6465766963656131","title":"Write tests","id":"task-1","defer_count":0,"created_at":"0001711060000_0001_6465766963656131"}"#.to_string(),
            ..existing.envelope.clone()
        },
        ..existing.clone()
    };

    assert!(
        incoming_records_match_for_file_idempotency(&existing, &outgoing),
        "semantic JSON equality should not trigger a mismatched-payload retry"
    );
}
#[test]
fn sync_entity_priority_prefers_lists_before_tasks() {
    assert!(
        sync_entity_apply_priority("list", "upsert") < sync_entity_apply_priority("task", "upsert")
    );
}

/// `sync_entity_apply_priority`
/// must explicitly enumerate every syncable entity_type so children
/// (reminders, checklist items, edges, …) cannot fall through to the
/// catch-all `4` bucket and apply BEFORE their parent. The PRIMARY
/// sort key in `apply/remote/core.rs` is this comparator (#2932-H1), so a
/// child landing at the same priority as a parent is a silent FK-
/// violation regression — the apply pipeline would buffer the child
/// in `sync_pending_inbox` despite the parent being adjacent in the
/// same envelope batch.
#[test]
fn sync_entity_priority_table_pins_every_known_entity_to_its_bucket() {
    use lorvex_domain::naming::*;

    let cases: &[(&str, &str, i32, &str)] = &[
        // Pure parents (priority 0 — no FK to anything else).
        (
            ENTITY_LIST,
            OP_UPSERT,
            0,
            "list is the only pure-parent root",
        ),
        // Day-scoped / singleton aggregates referenced by children
        // (priority 1).
        (
            ENTITY_CURRENT_FOCUS,
            OP_UPSERT,
            1,
            "current_focus links to tasks",
        ),
        (
            ENTITY_DAILY_REVIEW,
            OP_UPSERT,
            1,
            "daily_review references lists",
        ),
        (
            ENTITY_PREFERENCE,
            OP_UPSERT,
            1,
            "preferences may be referenced",
        ),
        (ENTITY_MEMORY, OP_UPSERT, 1, "memories are referenceable"),
        (
            ENTITY_FOCUS_SCHEDULE,
            OP_UPSERT,
            1,
            "focus_schedule stands alone",
        ),
        // Aggregate roots (priority 2).
        (ENTITY_TASK, OP_UPSERT, 2, "task has list_id FK"),
        (
            ENTITY_CALENDAR_EVENT,
            OP_UPSERT,
            2,
            "calendar_event has list-implicit FK",
        ),
        (ENTITY_HABIT, OP_UPSERT, 2, "habit is an aggregate root"),
        (ENTITY_TAG, OP_UPSERT, 2, "tag is an aggregate root"),
        // Children + edges (priority 3).
        (
            ENTITY_TASK_REMINDER,
            OP_UPSERT,
            3,
            "task_reminder.task_id FK",
        ),
        (
            ENTITY_TASK_CHECKLIST_ITEM,
            OP_UPSERT,
            3,
            "task_checklist_item.task_id FK",
        ),
        (
            ENTITY_HABIT_REMINDER_POLICY,
            OP_UPSERT,
            3,
            "habit_reminder_policy.habit_id FK",
        ),
        (
            EDGE_TASK_CALENDAR_EVENT_LINK,
            OP_UPSERT,
            3,
            "edge: task ↔ calendar_event",
        ),
        (
            EDGE_HABIT_COMPLETION,
            OP_UPSERT,
            3,
            "edge: habit_completion.habit_id",
        ),
        (EDGE_TASK_TAG, OP_UPSERT, 3, "edge: task ↔ tag"),
        (EDGE_TASK_DEPENDENCY, OP_UPSERT, 3, "edge: task ↔ task"),
        // Catch-all (priority 4) — unknown entity_type, deletes (the
        // apply pipeline handles deletes independently of priority).
        (
            "unknown_entity",
            OP_UPSERT,
            4,
            "unknown entity_type lands last",
        ),
        (
            ENTITY_TASK,
            "delete",
            4,
            "deletes do not participate in upsert priority",
        ),
        (
            ENTITY_LIST,
            "delete",
            4,
            "deletes lift to the catch-all bucket",
        ),
    ];

    for (entity_type, operation, expected, why) in cases {
        let actual = sync_entity_apply_priority(entity_type, operation);
        assert_eq!(
            actual, *expected,
            "({entity_type}, {operation}) expected priority {expected} ({why}); got {actual}"
        );
    }

    // Cross-cutting invariant: parents must apply before children
    // when both are in the same envelope batch.
    assert!(
        sync_entity_apply_priority(ENTITY_LIST, OP_UPSERT)
            < sync_entity_apply_priority(ENTITY_TASK, OP_UPSERT)
    );
    assert!(
        sync_entity_apply_priority(ENTITY_TASK, OP_UPSERT)
            < sync_entity_apply_priority(ENTITY_TASK_REMINDER, OP_UPSERT)
    );
    assert!(
        sync_entity_apply_priority(ENTITY_HABIT, OP_UPSERT)
            < sync_entity_apply_priority(EDGE_HABIT_COMPLETION, OP_UPSERT)
    );
    assert!(
        sync_entity_apply_priority(ENTITY_TASK, OP_UPSERT)
            < sync_entity_apply_priority(EDGE_TASK_DEPENDENCY, OP_UPSERT)
    );
}
