use super::support::{
    enqueue_payload_delete, enqueue_payload_upsert, insert_habit, insert_list, insert_task,
    insert_task_calendar_event_link, naming, test_db, tombstone_completions_for_habit_delete,
    tombstone_edges_for_calendar_event_delete, tombstone_reminder_policies_for_habit_delete,
    OutboxWriteContext,
};
use lorvex_domain::ids::{EventId, HabitId};

#[test]
fn calendar_event_link_delete_helpers_return_full_edge_snapshots() {
    let conn = test_db();
    insert_task_calendar_event_link(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000217f",
        "01966a3f-7c8b-7d4e-8f3a-000000002116",
    );

    let snapshots = tombstone_edges_for_calendar_event_delete(
        &conn,
        &EventId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000002116".to_string()),
        "0000000000001_0000_deleteedgeedge01",
    )
    .unwrap();
    assert_eq!(snapshots.len(), 1);
    let snapshot = &snapshots[0];
    assert_eq!(snapshot.task_id, "01966a3f-7c8b-7d4e-8f3a-00000000217f");
    assert_eq!(
        snapshot.calendar_event_id,
        "01966a3f-7c8b-7d4e-8f3a-000000002116"
    );
    assert_eq!(
        snapshot.entity_id(),
        "01966a3f-7c8b-7d4e-8f3a-00000000217f:01966a3f-7c8b-7d4e-8f3a-000000002116"
    );
    let payload = snapshot.payload();
    assert_eq!(payload["task_id"], "01966a3f-7c8b-7d4e-8f3a-00000000217f");
    assert_eq!(
        payload["calendar_event_id"],
        "01966a3f-7c8b-7d4e-8f3a-000000002116"
    );
    assert_eq!(payload["version"], "0000000000000_0000_edgeedgeedgeedge");
    assert_eq!(payload["created_at"], "2026-04-02T08:00:00.000Z");
    assert_eq!(payload["updated_at"], "2026-04-02T09:00:00.000Z");
}

#[test]
fn habit_delete_cascade_helpers_return_full_child_snapshots() {
    let conn = test_db();
    insert_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000002120", "Read");
    conn.execute(
        "INSERT INTO habit_completions
         (habit_id, completed_date, value, note, version, created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000002120', '2026-04-26', 3, 'Long session',
                 '0000000000000_0000_c0c0c0c0c0c0c0c0',
                 '2026-04-26T08:00:00.000Z', '2026-04-26T09:00:00.000Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO habit_reminder_policies
         (id, habit_id, reminder_time, enabled, version, created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000002141', '01966a3f-7c8b-7d4e-8f3a-000000002120', '18:30', 0,
                 '0000000000000_0000_d0d0d0d0d0d0d0d0',
                 '2026-04-25T08:00:00.000Z', '2026-04-25T09:00:00.000Z')",
        [],
    )
    .unwrap();

    let completions = tombstone_completions_for_habit_delete(
        &conn,
        &HabitId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000002120".to_string()),
        "0000000000001_0000_decafdecafdecaf0",
    )
    .unwrap();
    assert_eq!(completions.len(), 1);
    let completion = &completions[0];
    assert_eq!(
        completion.entity_id(),
        "01966a3f-7c8b-7d4e-8f3a-000000002120:2026-04-26"
    );
    assert_eq!(completion.value, 3);
    assert_eq!(completion.note.as_deref(), Some("Long session"));
    let completion_payload = completion.payload();
    assert_eq!(
        completion_payload["habit_id"],
        "01966a3f-7c8b-7d4e-8f3a-000000002120"
    );
    assert_eq!(completion_payload["completed_date"], "2026-04-26");
    assert_eq!(completion_payload["value"], 3);
    assert_eq!(completion_payload["note"], "Long session");
    assert_eq!(
        completion_payload["version"],
        "0000000000000_0000_c0c0c0c0c0c0c0c0"
    );

    let policies = tombstone_reminder_policies_for_habit_delete(
        &conn,
        &HabitId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000002120".to_string()),
        "0000000000001_0000_decafdecafdecaf1",
    )
    .unwrap();
    assert_eq!(policies.len(), 1);
    let policy = &policies[0];
    assert_eq!(policy.id, "01966a3f-7c8b-7d4e-8f3a-000000002141");
    assert_eq!(policy.habit_id, "01966a3f-7c8b-7d4e-8f3a-000000002120");
    assert_eq!(policy.reminder_time, "18:30");
    assert!(!policy.enabled);
    let policy_payload = policy.payload();
    assert_eq!(policy_payload["id"], "01966a3f-7c8b-7d4e-8f3a-000000002141");
    assert_eq!(
        policy_payload["habit_id"],
        "01966a3f-7c8b-7d4e-8f3a-000000002120"
    );
    assert_eq!(policy_payload["reminder_time"], "18:30");
    assert_eq!(policy_payload["enabled"], false);
    assert_eq!(
        policy_payload["version"],
        "0000000000000_0000_d0d0d0d0d0d0d0d0"
    );

    assert!(crate::tombstone::is_tombstoned(
        &conn,
        naming::EDGE_HABIT_COMPLETION,
        "01966a3f-7c8b-7d4e-8f3a-000000002120:2026-04-26",
    )
    .unwrap());
    assert!(crate::tombstone::is_tombstoned(
        &conn,
        naming::ENTITY_HABIT_REMINDER_POLICY,
        "01966a3f-7c8b-7d4e-8f3a-000000002141",
    )
    .unwrap());
}

/// a coalesced UPSERT → DELETE → UPSERT sequence
/// must NOT leave a stale local tombstone behind. Pre-fix the
/// DELETE step minted a tombstone that the second UPSERT never
/// cleared; the next inbound apply pass for the same entity_id
/// then dropped a peer's concurrent edit because the
/// tombstone-vs-upsert gate compared `tombstone.version >=
/// envelope.version` and the dead tombstone "won" against any
/// envelope authored before the second UPSERT's HLC.
#[test]
fn upsert_after_delete_clears_stale_tombstone() {
    let conn = test_db();

    // Step 1: insert a list and enqueue the initial UPSERT so the
    // outbox / version_stamp invariants are happy.
    insert_list(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000213d", "Resurrected");
    let v1 = "1711234560000_0000_a0a0a0a0a0a0a0a0";
    enqueue_payload_upsert(
        &conn,
        naming::ENTITY_LIST,
        "01966a3f-7c8b-7d4e-8f3a-00000000213d",
        &serde_json::json!({
            "id": "01966a3f-7c8b-7d4e-8f3a-00000000213d",
            "name": "Resurrected",
            "color": null,
            "created_at": "2026-04-19T00:00:00.000Z",
            "updated_at": "2026-04-19T00:00:00.000Z",
        }),
        OutboxWriteContext {
            version: v1,
            device_id: "dev-001",
        },
    )
    .unwrap();

    // Step 2: delete the row (mirrors the user / cascade flow:
    // remove the row, then enqueue the Delete envelope).
    conn.execute(
        "DELETE FROM lists WHERE id = '01966a3f-7c8b-7d4e-8f3a-00000000213d'",
        [],
    )
    .unwrap();
    let v2 = "1711234561000_0000_a0a0a0a0a0a0a0a0";
    enqueue_payload_delete(
        &conn,
        naming::ENTITY_LIST,
        "01966a3f-7c8b-7d4e-8f3a-00000000213d",
        &serde_json::json!({}),
        OutboxWriteContext {
            version: v2,
            device_id: "dev-001",
        },
    )
    .unwrap();

    // Tombstone now exists locally — exactly what we want a
    // future inbound apply to consult.
    assert!(
        crate::tombstone::is_tombstoned(
            &conn,
            naming::ENTITY_LIST,
            "01966a3f-7c8b-7d4e-8f3a-00000000213d"
        )
        .unwrap(),
        "delete enqueue should mint a local tombstone"
    );

    // Step 3: re-create the list (resurrection) and enqueue the
    // second UPSERT. Pre-fix this branch left the v2 tombstone
    // in place and any peer envelope at HLC < v3 lost LWW to
    // the tombstone forever.
    insert_list(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000213d",
        "Resurrected v2",
    );
    let v3 = "1711234562000_0000_a0a0a0a0a0a0a0a0";
    enqueue_payload_upsert(
        &conn,
        naming::ENTITY_LIST,
        "01966a3f-7c8b-7d4e-8f3a-00000000213d",
        &serde_json::json!({
            "id": "01966a3f-7c8b-7d4e-8f3a-00000000213d",
            "name": "Resurrected v2",
            "color": null,
            "created_at": "2026-04-19T00:00:00.000Z",
            "updated_at": "2026-04-19T00:01:00.000Z",
        }),
        OutboxWriteContext {
            version: v3,
            device_id: "dev-001",
        },
    )
    .unwrap();

    // The fix: after the second UPSERT, the local tombstone is
    // gone. Any peer concurrent-edit envelope at any HLC will
    // race the resurrected row through the normal LWW gate
    // instead of being silently rejected by a dead tombstone.
    assert!(
        !crate::tombstone::is_tombstoned(
            &conn,
            naming::ENTITY_LIST,
            "01966a3f-7c8b-7d4e-8f3a-00000000213d"
        )
        .unwrap(),
        "issue #2973-H4: upsert after delete must clear the stale tombstone"
    );

    let stale_tombstone_trace_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs
             WHERE source = 'sync.outbox_enqueue.stale_tombstone_removed'
               AND level = 'info'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        stale_tombstone_trace_count, 1,
        "stale tombstone cleanup should leave an info-level diagnostic row"
    );
}

#[test]
fn stale_delete_rejected_by_outbox_coalesce_does_not_create_tombstone() {
    let conn = test_db();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-00000000219a";
    let newer_upsert_version = "1711234562000_0000_a0a0a0a0a0a0a0a0";
    let stale_delete_version = "1711234561000_0000_a0a0a0a0a0a0a0a0";

    insert_task(&conn, task_id, "Fresh local edit");
    enqueue_payload_upsert(
        &conn,
        naming::ENTITY_TASK,
        task_id,
        &serde_json::json!({
            "id": task_id,
            "title": "Fresh local edit",
            "status": "open",
            "created_at": "2026-04-19T00:00:00.000Z",
            "updated_at": "2026-04-19T00:02:00.000Z",
        }),
        OutboxWriteContext {
            version: newer_upsert_version,
            device_id: "dev-001",
        },
    )
    .unwrap();

    conn.execute("DELETE FROM tasks WHERE id = ?1", [task_id])
        .unwrap();
    enqueue_payload_delete(
        &conn,
        naming::ENTITY_TASK,
        task_id,
        &serde_json::json!({}),
        OutboxWriteContext {
            version: stale_delete_version,
            device_id: "dev-001",
        },
    )
    .unwrap();

    let (operation, version): (String, String) = conn
        .query_row(
            "SELECT operation, version FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2 AND synced_at IS NULL",
            rusqlite::params![naming::ENTITY_TASK, task_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(operation, naming::OP_UPSERT);
    assert_eq!(version, newer_upsert_version);
    assert!(
        !crate::tombstone::is_tombstoned(&conn, naming::ENTITY_TASK, task_id).unwrap(),
        "a stale delete rejected by outbox coalescing must not mint a local tombstone"
    );
}
