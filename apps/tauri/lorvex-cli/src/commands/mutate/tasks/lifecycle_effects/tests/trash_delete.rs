use super::super::*;
use super::support::*;

#[test]
fn cancel_task_with_conn_updates_status_and_enqueues_outbox() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let task_id = "01949c00-0000-7000-8000-000000000040";
    seed_task(&conn, task_id, "Cancel me", "open");

    cancel_task_with_conn(&conn, &tid(task_id), false).expect("cancel task");

    let status: String = conn
        .query_row("SELECT status FROM tasks WHERE id = ?1", [task_id], |row| {
            row.get(0)
        })
        .expect("load cancelled task");
    assert_eq!(status, "cancelled");

    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            [ENTITY_TASK, task_id],
            |row| row.get(0),
        )
        .expect("count outbox");
    assert_eq!(outbox_count, 1);

    let seq = read_local_change_seq(&conn).expect("read local change seq");
    assert_eq!(seq, 1);
}

#[test]
fn trash_lifecycle_archives_restores_and_gates_permanent_delete() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let task_id = "01949c00-0000-7000-8000-000000000030";
    seed_task(&conn, task_id, "Trash me", "open");

    let archive = archive_task_with_conn(&conn, &tid(task_id)).expect("archive task");
    assert!(archive.lifecycle().archived_at().is_some());
    assert!(archive.core().updated_at() >= "2026-03-30T00:00:00Z");

    let archived_at: Option<String> = conn
        .query_row(
            "SELECT archived_at FROM tasks WHERE id = ?1",
            [task_id],
            |row| row.get(0),
        )
        .expect("load archived_at");
    assert!(archived_at.is_some());

    let restored = restore_task_from_trash_with_conn(&conn, &tid(task_id)).expect("restore task");
    assert!(restored.lifecycle().archived_at().is_none());

    let live_delete_error = permanent_delete_task_with_conn(&mut conn, &tid(task_id), false)
        .expect_err("live task hard delete should require trash first");
    assert!(
        live_delete_error.to_string().contains("Trash"),
        "delete error should explain the Trash gate: {live_delete_error}"
    );
}

#[test]
fn permanent_delete_task_with_conn_deletes_archived_task_and_syncs_children() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let task_id = "01949c00-0000-7000-8000-000000000031";
    let tag_id = "01949c00-0000-7000-8000-000000000032";
    let checklist_id = "01949c00-0000-7000-8000-000000000033";
    let reminder_id = "01949c00-0000-7000-8000-000000000034";
    let event_id = "01949c00-0000-7000-8000-000000000035";
    seed_task(&conn, task_id, "Delete forever", "open");
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
         VALUES (?1, 'Delete Tag', 'delete-tag', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-30T00:00:00Z', '2026-03-30T00:00:00Z')",
        [tag_id],
    )
    .expect("seed tag");
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, version, created_at)
         VALUES (?1, ?2, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-30T00:00:00Z')",
        [task_id, tag_id],
    )
    .expect("seed task tag");
    conn.execute(
        "INSERT INTO task_checklist_items (id, task_id, position, text, completed_at, version, created_at, updated_at)
         VALUES (?1, ?2, 1, 'Child', NULL, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-30T00:00:00Z', '2026-03-30T00:00:00Z')",
        [checklist_id, task_id],
    )
    .expect("seed checklist");
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES (?1, ?2, '2026-05-01T13:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-30T00:00:00Z')",
        [reminder_id, task_id],
    )
    .expect("seed reminder");
    conn.execute(
        "INSERT INTO calendar_events (id, title, start_date, all_day, version, created_at, updated_at)
         VALUES (?1, 'Linked event', '2026-05-01', 1, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-30T00:00:00Z', '2026-03-30T00:00:00Z')",
        [event_id],
    )
    .expect("seed event");
    conn.execute(
        "INSERT INTO task_calendar_event_links (task_id, calendar_event_id, version, created_at, updated_at)
         VALUES (?1, ?2, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-30T00:00:00Z', '2026-03-30T00:00:00Z')",
        [task_id, event_id],
    )
    .expect("seed event link");

    archive_task_with_conn(&conn, &tid(task_id)).expect("archive task");
    let outbox_before_dry_run: i64 = conn
        .query_row("SELECT COUNT(*) FROM sync_outbox", [], |row| row.get(0))
        .expect("count outbox before dry run");
    let seq_before_dry_run = read_local_change_seq(&conn).expect("read local seq before dry run");
    let dry_run = permanent_delete_task_with_conn(&mut conn, &tid(task_id), true).expect("dry run");
    assert_eq!(dry_run.task_id, task_id);
    assert!(dry_run.dry_run);
    assert!(!dry_run.deleted);
    let outbox_after_dry_run: i64 = conn
        .query_row("SELECT COUNT(*) FROM sync_outbox", [], |row| row.get(0))
        .expect("count outbox after dry run");
    assert_eq!(outbox_after_dry_run, outbox_before_dry_run);
    assert_eq!(
        read_local_change_seq(&conn).expect("read local seq after dry run"),
        seq_before_dry_run
    );
    assert!(
        conn.query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = ?1",
            [task_id],
            |row| { row.get::<_, i64>(0) }
        )
        .expect("count task")
            > 0
    );

    let deleted =
        permanent_delete_task_with_conn(&mut conn, &tid(task_id), false).expect("delete task");
    assert!(deleted.deleted);
    assert_eq!(deleted.title.as_deref(), Some("Delete forever"));

    let task_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = ?1",
            [task_id],
            |row| row.get(0),
        )
        .expect("count deleted task");
    assert_eq!(task_count, 0);

    for entity_type in [
        ENTITY_TASK,
        EDGE_TASK_TAG,
        ENTITY_TASK_CHECKLIST_ITEM,
        ENTITY_TASK_REMINDER,
        EDGE_TASK_CALENDAR_EVENT_LINK,
    ] {
        let delete_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND operation = ?2",
                rusqlite::params![entity_type, OP_DELETE],
                |row| row.get(0),
            )
            .expect("count delete outbox entries");
        assert!(
            delete_count >= 1,
            "expected delete outbox entry for {entity_type}"
        );
    }

    let changelog_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3",
            rusqlite::params![ENTITY_TASK, task_id, OP_DELETE],
            |row| row.get(0),
        )
        .expect("count changelog");
    assert_eq!(changelog_count, 1);
}

#[test]
fn permanent_delete_reenqueues_parent_aggregate_upserts_for_focus_and_schedule_days() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let task_id = "01949c00-0000-7000-8000-000000000036";
    seed_task(&conn, task_id, "Focused delete", "open");
    conn.execute(
        "UPDATE tasks
         SET archived_at = '2026-04-30T00:00:00Z'
         WHERE id = ?1",
        [task_id],
    )
    .expect("mark task archived");
    conn.execute(
        "INSERT INTO current_focus (date, briefing, timezone, version, created_at, updated_at)
         VALUES ('2026-05-01', 'Focus before delete', 'UTC', '0000000000000_0000_cf00000000000000', '2026-04-30T00:00:00Z', '2026-04-30T00:00:00Z')",
        [],
    )
    .expect("seed current_focus parent");
    conn.execute(
        "INSERT INTO current_focus_items (date, position, task_id)
         VALUES ('2026-05-01', 0, ?1)",
        [task_id],
    )
    .expect("seed current_focus child");
    conn.execute(
        "INSERT INTO focus_schedule (date, rationale, timezone, version, created_at, updated_at)
         VALUES ('2026-05-02', 'Schedule before delete', 'UTC', '0000000000000_0000_fs00000000000000', '2026-04-30T00:00:00Z', '2026-04-30T00:00:00Z')",
        [],
    )
    .expect("seed focus_schedule parent");
    conn.execute(
        "INSERT INTO focus_schedule_blocks
             (schedule_date, position, block_type, start_time, end_time, task_id, title)
         VALUES ('2026-05-02', 0, 'task', 540, 570, ?1, 'Focused delete')",
        [task_id],
    )
    .expect("seed focus_schedule block");

    let deleted = permanent_delete_task_with_conn(&mut conn, &tid(task_id), false)
        .expect("permanent delete focused task");
    assert!(deleted.deleted);

    for (table, date_column, date) in [
        ("current_focus_items", "date", "2026-05-01"),
        ("focus_schedule_blocks", "schedule_date", "2026-05-02"),
    ] {
        let remaining: i64 = conn
            .query_row(
                &format!("SELECT COUNT(*) FROM {table} WHERE {date_column} = ?1 AND task_id = ?2"),
                [date, task_id],
                |row| row.get(0),
            )
            .expect("count stale focus refs");
        assert_eq!(
            remaining, 0,
            "hard delete must remove stale refs from {table}"
        );
    }

    for (entity_type, entity_id) in [
        (ENTITY_CURRENT_FOCUS, "2026-05-01"),
        (ENTITY_FOCUS_SCHEDULE, "2026-05-02"),
    ] {
        let upsert_count: i64 = conn
            .query_row(
                "SELECT COUNT(*)
                 FROM sync_outbox
                 WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3",
                rusqlite::params![entity_type, entity_id, OP_UPSERT],
                |row| row.get(0),
            )
            .expect("count aggregate upsert outbox rows");
        assert!(
            upsert_count >= 1,
            "permanent delete must enqueue {entity_type} upsert for {entity_id}"
        );
    }
}
