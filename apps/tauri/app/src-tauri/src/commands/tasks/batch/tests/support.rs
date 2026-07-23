use rusqlite::params;

pub(super) use super::super::super::undo::{apply_single_undo_for_tests, LifecycleAction};
pub(super) use crate::test_support::test_conn;
pub(super) use lorvex_domain::naming::{
    TaskStatus, EDGE_TASK_TAG, ENTITY_CURRENT_FOCUS, ENTITY_FOCUS_SCHEDULE, ENTITY_TASK,
    ENTITY_TASK_CHECKLIST_ITEM, ENTITY_TASK_REMINDER, STATUS_CANCELLED,
};

pub(super) const SEED_VERSION: &str = "0000000000000_0000_7365656473656564";

pub(super) fn uid() -> String {
    uuid::Uuid::now_v7().to_string()
}

pub(super) fn seed_task(
    conn: &rusqlite::Connection,
    id: &str,
    title: &str,
    list_id: &str,
    status: &str,
) {
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title(title)
        .status(status)
        .list_id(Some(list_id))
        .version(SEED_VERSION)
        .created_at("2026-04-01T08:00:00Z")
        .insert(conn);
}

pub(super) fn seed_list(conn: &rusqlite::Connection, id: &str, name: &str) {
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES (?1, ?2, ?3, '2026-04-01T08:00:00Z', '2026-04-01T08:00:00Z')",
        params![id, name, SEED_VERSION],
    )
    .expect("seed list");
}

/// Seed a recurring task with enough fixture state that
/// `apply_cancel_transition` will spawn a successor when
/// `cancel_series=false`.
pub(super) fn seed_recurring_task(
    conn: &rusqlite::Connection,
    id: &str,
    title: &str,
    list_id: &str,
    due_date: &str,
) {
    let group_id = format!("rgrp-{id}");
    // Stays raw: TaskBuilder doesn't expose
    // `canonical_occurrence_date`, which the schema CHECK requires
    // alongside `recurrence`.
    conn.execute(
        "INSERT INTO tasks (
            id, title, status, list_id, due_date,
            recurrence, canonical_occurrence_date, recurrence_group_id,
            version, created_at, updated_at
        ) VALUES (
            ?1, ?2, 'open', ?3, ?4,
            '{\"FREQ\":\"DAILY\",\"INTERVAL\":1}', ?4, ?5,
            '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z', '2026-04-01T08:00:00Z'
        )",
        params![id, title, list_id, due_date, group_id],
    )
    .expect("seed recurring task");
}

pub(super) fn seed_successor_copied_children(conn: &rusqlite::Connection, task_id: &str) {
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000000027', 'Recurring', 'recurring', ?1, '2026-04-01T08:00:00Z', '2026-04-01T08:00:00Z')",
        params![SEED_VERSION],
    )
    .expect("seed copied tag");
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, version, created_at)
         VALUES (?1, '01966a3f-7c8b-7d4e-8f3a-000000000027', ?2, '2026-04-01T08:00:00Z')",
        params![task_id, SEED_VERSION],
    )
    .expect("seed copied task tag");
    conn.execute(
        "INSERT INTO task_checklist_items
            (id, task_id, position, text, version, created_at, updated_at)
         VALUES (?1, ?2, 0, 'copied step', ?3, '2026-04-01T08:00:00Z', '2026-04-01T08:00:00Z')",
        params![uid(), task_id, SEED_VERSION],
    )
    .expect("seed copied checklist item");
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES (?1, ?2, '2026-04-10T09:00:00Z', ?3, '2026-04-01T08:00:00Z')",
        params![uid(), task_id, SEED_VERSION],
    )
    .expect("seed copied reminder");
}

/// Count pending (unsynced) outbox rows for an entity type, optionally
/// narrowed to a specific entity id. Forward mutations enqueue plain,
/// immediately-dispatchable rows — there is no undo-group scoping.
pub(super) fn plain_outbox_count(
    conn: &rusqlite::Connection,
    entity_type: &str,
    entity_id: Option<&str>,
) -> i64 {
    match entity_id {
        Some(entity_id) => conn
            .query_row(
                "SELECT COUNT(*) FROM sync_outbox
                 WHERE entity_type = ?1 AND entity_id = ?2 AND synced_at IS NULL",
                params![entity_type, entity_id],
                |row| row.get(0),
            )
            .expect("count pending entity rows"),
        None => conn
            .query_row(
                "SELECT COUNT(*) FROM sync_outbox
                 WHERE entity_type = ?1 AND synced_at IS NULL",
                params![entity_type],
                |row| row.get(0),
            )
            .expect("count pending entity rows"),
    }
}

pub(super) fn sole_successor_checklist_item_id(
    conn: &rusqlite::Connection,
    successor_id: &str,
) -> String {
    conn.query_row(
        "SELECT id FROM task_checklist_items WHERE task_id = ?1",
        params![successor_id],
        |row| row.get(0),
    )
    .expect("load successor checklist item")
}

pub(super) fn sole_successor_reminder_id(
    conn: &rusqlite::Connection,
    successor_id: &str,
) -> String {
    conn.query_row(
        "SELECT id FROM task_reminders WHERE task_id = ?1",
        params![successor_id],
        |row| row.get(0),
    )
    .expect("load successor reminder")
}
