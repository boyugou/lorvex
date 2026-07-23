use super::*;

pub(super) const TEST_VER: &str = "0000000000000_0000_a0a0a0a0a0a0a0a0";
pub(super) const NOW_TS: &str = "2026-04-18T09:00:00.000000Z";

/// Apply an undo inside an immediate transaction, mirroring the
/// production `undo_task_lifecycle_with_conn` wrap so the reverse-write
/// enqueues run atomically against a caller-owned transaction.
pub(super) fn apply_undo_in_txn(conn: &Connection, undo: &UndoToken) {
    crate::commands::with_immediate_transaction(conn, |conn| apply_single_undo(conn, undo, NOW_TS))
        .expect("apply_single_undo");
}

/// Seed an open parent task, a completed successor spawned from it,
/// 2 tag edges, 3 checklist items, 1 reminder, and the plain forward
/// outbox rows the completion enqueued for the successor and its
/// children. Returns the completion undo token pointing at the parent.
///
/// The forward rows are ordinary immediately-dispatchable upserts —
/// there is no emit-hold and no undo-group scoping. Undo issues a fresh
/// set of reverse writes (a parent upsert plus a successor delete +
/// tombstone) rather than retracting these rows, so they may still be
/// present (or already synced) when the undo runs.
pub(super) fn seed_recurrence_undo_fixture(conn: &Connection) -> UndoToken {
    let parent_id = "01966a3f-7c8b-7d4e-8f3a-000000000022";
    let successor_id = "01966a3f-7c8b-7d4e-8f3a-000000000023";

    // Parent (completed) + successor (open).
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000000024', 'Default', ?1, ?2, ?2)",
        params![TEST_VER, NOW_TS],
    )
    .unwrap();
    // lift to canonical TaskBuilder.
    use lorvex_store::test_support::fixtures::TaskBuilder;
    TaskBuilder::new(parent_id)
        .title("Parent")
        .status("completed")
        .version(TEST_VER)
        .created_at(NOW_TS)
        .list_id(Some("01966a3f-7c8b-7d4e-8f3a-000000000024"))
        .completed_at(Some(NOW_TS))
        .insert(conn);
    TaskBuilder::new(successor_id)
        .title("Successor")
        .version(TEST_VER)
        .created_at(NOW_TS)
        .list_id(Some("01966a3f-7c8b-7d4e-8f3a-000000000024"))
        .insert(conn);

    // Tags + 2 edges on successor.
    for tag_id in [
        "01966a3f-7c8b-7d4e-8f3a-000000000025",
        "01966a3f-7c8b-7d4e-8f3a-000000000026",
    ] {
        conn.execute(
            "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
             VALUES (?1, ?1, ?1, ?2, ?3, ?3)",
            params![tag_id, TEST_VER, NOW_TS],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO task_tags (task_id, tag_id, version, created_at)
             VALUES (?1, ?2, ?3, ?4)",
            params![successor_id, tag_id, TEST_VER, NOW_TS],
        )
        .unwrap();
    }

    // 3 checklist items on successor.
    for (i, item_id) in [
        "01966a3f-7c8b-7d4e-8f3a-000000000029",
        "01966a3f-7c8b-7d4e-8f3a-00000000002a",
        "01966a3f-7c8b-7d4e-8f3a-00000000002b",
    ]
    .iter()
    .enumerate()
    {
        conn.execute(
            "INSERT INTO task_checklist_items
                (id, task_id, position, text, version, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)",
            params![
                item_id,
                successor_id,
                i as i64,
                format!("item-{i}"),
                TEST_VER,
                NOW_TS
            ],
        )
        .unwrap();
    }

    // 1 reminder on successor.
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-00000000002c', ?1, '2026-04-19T09:00:00Z', ?2, ?3)",
        params![successor_id, TEST_VER, NOW_TS],
    )
    .unwrap();

    // Plain forward outbox rows the completion enqueued for the
    // successor + its children. Immediately dispatchable, no emit-hold.
    let outbox_rows: [(&str, &str); 7] = [
        (ENTITY_TASK, successor_id),
        (
            EDGE_TASK_TAG,
            "01966a3f-7c8b-7d4e-8f3a-000000000023:01966a3f-7c8b-7d4e-8f3a-000000000025",
        ),
        (
            EDGE_TASK_TAG,
            "01966a3f-7c8b-7d4e-8f3a-000000000023:01966a3f-7c8b-7d4e-8f3a-000000000026",
        ),
        (
            ENTITY_TASK_CHECKLIST_ITEM,
            "01966a3f-7c8b-7d4e-8f3a-000000000029",
        ),
        (
            ENTITY_TASK_CHECKLIST_ITEM,
            "01966a3f-7c8b-7d4e-8f3a-00000000002a",
        ),
        (
            ENTITY_TASK_CHECKLIST_ITEM,
            "01966a3f-7c8b-7d4e-8f3a-00000000002b",
        ),
        (ENTITY_TASK_REMINDER, "01966a3f-7c8b-7d4e-8f3a-00000000002c"),
    ];
    for (etype, eid) in outbox_rows {
        conn.execute(
            "INSERT INTO sync_outbox
                (entity_type, entity_id, operation, version,
                 payload_schema_version, payload, device_id, created_at)
             VALUES (?1, ?2, 'upsert', ?3, 1, '{}', 'dev-1', ?4)",
            params![etype, eid, TEST_VER, NOW_TS],
        )
        .unwrap();
    }

    UndoToken {
        task_id: parent_id.to_string(),
        action: LifecycleAction::Complete,
        cancel_series: false,
        pre_status: TaskStatus::Open,
        pre_completed_at: None,
        pre_planned_date: None,
        pre_defer_count: 0,
        pre_last_deferred_at: None,
        pre_last_defer_reason: None,
        spawned_successor_id: Some(successor_id.to_string()),
        cancelled_reminder_ids: vec![],
        deleted_dep_edges: vec![],
        affected_dependent_ids: vec![],
        expires_at: (chrono::Utc::now() + chrono::Duration::seconds(60))
            .to_rfc3339_opts(chrono::SecondsFormat::Micros, true),
        pre_task_snapshot: None,
    }
}

/// Seed a cancelled task whose forward cancel suspended one reminder
/// and deleted one dependency edge (task depends on `dep`). Returns the
/// cancel undo token carrying those side effects so undo can un-suspend
/// the reminder and re-insert the edge.
///
/// Both endpoints of the dependency exist; only the edge row is absent
/// (the forward cancel deleted it), so the undo re-inserts it and
/// re-publishes it as a `task_dependency` edge upsert.
pub(super) fn seed_cancel_undo_fixture(conn: &Connection) -> UndoToken {
    let task_id = "01966a3f-7c8b-7d4e-8f3a-000000000042";
    let dep_id = "01966a3f-7c8b-7d4e-8f3a-000000000043";
    let reminder_id = "01966a3f-7c8b-7d4e-8f3a-000000000044";

    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000000024', 'Default', ?1, ?2, ?2)",
        params![TEST_VER, NOW_TS],
    )
    .unwrap();
    use lorvex_store::test_support::fixtures::TaskBuilder;
    TaskBuilder::new(task_id)
        .title("Cancelled")
        .status("cancelled")
        .version(TEST_VER)
        .created_at(NOW_TS)
        .list_id(Some("01966a3f-7c8b-7d4e-8f3a-000000000024"))
        .insert(conn);
    TaskBuilder::new(dep_id)
        .title("Dependency")
        .version(TEST_VER)
        .created_at(NOW_TS)
        .list_id(Some("01966a3f-7c8b-7d4e-8f3a-000000000024"))
        .insert(conn);

    // Reminder suspended by the forward cancel (cancelled_at set).
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, cancelled_at, version, created_at)
         VALUES (?1, ?2, '2026-04-19T09:00:00Z', ?3, ?4, ?3)",
        params![reminder_id, task_id, NOW_TS, TEST_VER],
    )
    .unwrap();

    UndoToken {
        task_id: task_id.to_string(),
        action: LifecycleAction::Cancel,
        cancel_series: false,
        pre_status: TaskStatus::Open,
        pre_completed_at: None,
        pre_planned_date: None,
        pre_defer_count: 0,
        pre_last_deferred_at: None,
        pre_last_defer_reason: None,
        spawned_successor_id: None,
        cancelled_reminder_ids: vec![reminder_id.to_string()],
        deleted_dep_edges: vec![(task_id.to_string(), dep_id.to_string())],
        affected_dependent_ids: vec![],
        expires_at: (chrono::Utc::now() + chrono::Duration::seconds(60))
            .to_rfc3339_opts(chrono::SecondsFormat::Micros, true),
        pre_task_snapshot: None,
    }
}
