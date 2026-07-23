use super::support::{insert_base_task, TS, V};
use lorvex_store::open_db_in_memory;
use rusqlite::params;

#[test]
fn check_task_status_rejects_invalid() {
    let conn = open_db_in_memory().unwrap();
    let err = conn.execute(
        "INSERT INTO tasks (id, title, status, version, created_at, updated_at) VALUES ('t1', 'T', 'invalid', ?1, ?2, ?2)",
        params![V, TS],
    ).unwrap_err();
    assert!(
        err.to_string().contains("CHECK"),
        "expected CHECK violation: {err}"
    );
}

#[test]
fn check_task_priority_bounds() {
    let conn = open_db_in_memory().unwrap();
    // priority 0 is out of range (valid: 1-3)
    let err = conn.execute(
        "INSERT INTO tasks (id, title, status, priority, version, created_at, updated_at) VALUES ('t1', 'T', 'open', 0, ?1, ?2, ?2)",
        params![V, TS],
    ).unwrap_err();
    assert!(err.to_string().contains("CHECK"), "priority 0: {err}");

    // priority 4 is out of range
    let err = conn.execute(
        "INSERT INTO tasks (id, title, status, priority, version, created_at, updated_at) VALUES ('t1', 'T', 'open', 4, ?1, ?2, ?2)",
        params![V, TS],
    ).unwrap_err();
    assert!(err.to_string().contains("CHECK"), "priority 4: {err}");

    // priority NULL is allowed
    conn.execute(
        "INSERT INTO tasks (id, title, status, version, created_at, updated_at) VALUES ('t1', 'T', 'open', ?1, ?2, ?2)",
        params![V, TS],
    ).unwrap();
}

#[test]
fn check_recurrence_requires_due_date_and_group() {
    let conn = open_db_in_memory().unwrap();
    // recurrence set but no due_date → CHECK violation
    let err = conn
        .execute(
            "INSERT INTO tasks (id, title, status, recurrence, version, created_at, updated_at) \
         VALUES ('t1', 'T', 'open', '{\"FREQ\":\"DAILY\"}', ?1, ?2, ?2)",
            params![V, TS],
        )
        .unwrap_err();
    assert!(
        err.to_string().contains("CHECK"),
        "recurrence without due_date: {err}"
    );
}

#[test]
fn check_self_dependency_rejected() {
    let conn = open_db_in_memory().unwrap();
    insert_base_task(&conn, "t1");
    let err = conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) VALUES ('t1', 't1', ?1, ?2)",
        params![V, TS],
    ).unwrap_err();
    assert!(err.to_string().contains("CHECK"), "self-dependency: {err}");
}

#[test]
fn check_calendar_all_day_clears_times() {
    let conn = open_db_in_memory().unwrap();
    // all_day = 1 with start_time → CHECK violation
    let err = conn.execute(
        "INSERT INTO calendar_events (id, title, start_date, event_type, all_day, start_time, version, created_at, updated_at) \
         VALUES ('e1', 'E', '2026-03-01', 'event', 1, '09:00', ?1, ?2, ?2)",
        params![V, TS],
    ).unwrap_err();
    assert!(
        err.to_string().contains("CHECK"),
        "all_day with start_time: {err}"
    );
}

// ── Foreign key enforcement ──────────────────────────────────────────

#[test]
fn fk_task_tag_requires_existing_task() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) VALUES ('tag1', 'Tag', 'tag', ?1, ?2, ?2)",
        params![V, TS],
    ).unwrap();
    let err = conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, version, created_at) VALUES ('nonexistent', 'tag1', ?1, ?2)",
        params![V, TS],
    ).unwrap_err();
    assert!(
        err.to_string().contains("FOREIGN KEY"),
        "FK task_tags.task_id: {err}"
    );
}

#[test]
fn fk_cascade_delete_task_removes_tags() {
    let conn = open_db_in_memory().unwrap();
    insert_base_task(&conn, "t1");
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) VALUES ('tag1', 'Tag', 'tag', ?1, ?2, ?2)",
        params![V, TS],
    ).unwrap();
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, version, created_at) VALUES ('t1', 'tag1', ?1, ?2)",
        params![V, TS],
    ).unwrap();

    conn.execute("DELETE FROM tasks WHERE id = 't1'", [])
        .unwrap();

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_tags WHERE task_id = 't1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count, 0, "CASCADE should remove task_tags on task delete");
}

#[test]
fn fk_cascade_delete_task_removes_dependencies() {
    let conn = open_db_in_memory().unwrap();
    insert_base_task(&conn, "t1");
    insert_base_task(&conn, "t2");
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) VALUES ('t2', 't1', ?1, ?2)",
        params![V, TS],
    ).unwrap();

    conn.execute("DELETE FROM tasks WHERE id = 't1'", [])
        .unwrap();

    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM task_dependencies", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(
        count, 0,
        "CASCADE should remove dependencies on task delete"
    );
}

#[test]
fn deleting_non_inbox_list_rehomes_assigned_tasks_to_inbox() {
    // `trg_lists_before_delete` (schema/001_schema.sql) re-homes
    // surviving tasks to `inbox` BEFORE the DELETE proceeds, so the
    // RESTRICT FK on `tasks.list_id` never fires for non-inbox lists.
    // This matches the human-facing UX (a list is a folder; deleting
    // the folder doesn't delete its items) and prevents a sync wedge
    // when a peer legitimately removes a populated list.
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at) VALUES ('l1', 'List', ?1, ?2, ?2)",
        params![V, TS],
    ).unwrap();
    conn.execute(
        "INSERT INTO tasks (id, title, status, list_id, version, created_at, updated_at) VALUES ('t1', 'T', 'open', 'l1', ?1, ?2, ?2)",
        params![V, TS],
    ).unwrap();

    conn.execute("DELETE FROM lists WHERE id = 'l1'", [])
        .expect("trigger should re-home tasks then allow list delete");

    let list_id: String = conn
        .query_row("SELECT list_id FROM tasks WHERE id = 't1'", [], |row| {
            row.get(0)
        })
        .expect("task survives list deletion");
    assert_eq!(list_id, "inbox", "task should be re-homed to inbox");
}

#[test]
fn deleting_inbox_list_aborts_when_tasks_still_exist() {
    // The same trigger ABORTs deletion of `inbox` itself while any
    // task survives — `inbox` is the canonical fallback target, so
    // removing it would leave nowhere for orphaned rows to land. The
    // `reset_all_data_db` flow drains `tasks` first, so its bottom-up
    // wipe of `lists` still works (covered separately).
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO tasks (id, title, status, list_id, version, created_at, updated_at) VALUES ('t1', 'T', 'open', 'inbox', ?1, ?2, ?2)",
        params![V, TS],
    ).unwrap();

    let error = conn
        .execute("DELETE FROM lists WHERE id = 'inbox'", [])
        .expect_err("inbox delete should abort while tasks exist");
    assert!(
        error.to_string().contains("cannot delete inbox list"),
        "unexpected error: {error}"
    );
}

// ── UNIQUE constraints ───────────────────────────────────────────────

#[test]
fn unique_recurrence_instance_key() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO tasks (id, title, status, due_date, canonical_occurrence_date, recurrence, recurrence_group_id, recurrence_instance_key, version, created_at, updated_at) \
         VALUES ('t1', 'T1', 'open', '2026-03-25', '2026-03-25', '{\"FREQ\":\"DAILY\"}', 'grp1', 'grp1:2026-03-25', ?1, ?2, ?2)",
        params![V, TS],
    ).unwrap();

    let err = conn.execute(
        "INSERT INTO tasks (id, title, status, due_date, canonical_occurrence_date, recurrence, recurrence_group_id, recurrence_instance_key, version, created_at, updated_at) \
         VALUES ('t2', 'T2', 'open', '2026-03-25', '2026-03-25', '{\"FREQ\":\"DAILY\"}', 'grp1', 'grp1:2026-03-25', ?1, ?2, ?2)",
        params![V, TS],
    ).unwrap_err();
    assert!(
        err.to_string().contains("UNIQUE"),
        "duplicate instance key: {err}"
    );
}

// ── Default values ───────────────────────────────────────────────────

#[test]
fn task_defaults_are_correct() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO tasks (id, title, status, version, created_at, updated_at) VALUES ('t1', 'T', 'open', ?1, ?2, ?2)",
        params![V, TS],
    ).unwrap();

    let (priority, defer_count, list_id, body, due_date): (
        Option<i64>,
        i64,
        Option<String>,
        Option<String>,
        Option<String>,
    ) = conn
        .query_row(
            "SELECT priority, defer_count, list_id, body, due_date FROM tasks WHERE id = 't1'",
            [],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                ))
            },
        )
        .unwrap();

    assert!(priority.is_none(), "priority should default to NULL");
    assert_eq!(defer_count, 0, "defer_count should default to 0");
    assert_eq!(
        list_id.as_deref(),
        Some("inbox"),
        "list_id should default to 'inbox'"
    );
    assert!(body.is_none(), "body should default to NULL");
    assert!(due_date.is_none(), "due_date should default to NULL");
}
