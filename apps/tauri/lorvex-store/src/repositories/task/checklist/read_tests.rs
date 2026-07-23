use rusqlite::{params, Connection};

use super::{list_task_checklist_items, list_task_checklist_items_for_tasks};
use crate::test_support::{test_conn, TaskBuilder, TEST_VERSION};
use lorvex_domain::TaskId;

fn tid(id: &str) -> TaskId {
    TaskId::from_trusted(id.to_string())
}

/// Seed `task_checklist_items` rows directly. The repo only exposes
/// reads; mutations live in `super::promote` and the import
/// pipeline. We INSERT to set up the read fixtures so the read
/// contract is exercised in isolation from the mutation paths.
fn insert_item(
    conn: &Connection,
    id: &str,
    task_id: &str,
    position: i64,
    text: &str,
    completed_at: Option<&str>,
) {
    conn.execute(
        "INSERT INTO task_checklist_items \
         (id, task_id, position, text, completed_at, version, created_at, updated_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7)",
        params![
            id,
            task_id,
            position,
            text,
            completed_at,
            TEST_VERSION,
            "2026-05-03T12:00:00.000Z",
        ],
    )
    .expect("insert checklist item");
}

#[test]
fn list_task_checklist_items_empty_for_unknown_task() {
    let conn = test_conn();
    // No setup — query a task that has no checklist items.
    let items = list_task_checklist_items(&conn, &tid("task-no-such-id")).expect("list");
    assert!(
        items.is_empty(),
        "expected empty Vec for unknown task, got {items:?}"
    );
}

#[test]
fn list_task_checklist_items_returns_position_first_then_created_then_id() {
    let conn = test_conn();
    let task = "task-1";
    TaskBuilder::new(task).insert(&conn);
    // Insert in scrambled order to prove the ORDER BY survives.
    insert_item(&conn, "item-c", task, 2, "third", None);
    insert_item(&conn, "item-a", task, 0, "first", None);
    insert_item(&conn, "item-b", task, 1, "second", None);

    let items = list_task_checklist_items(&conn, &tid(task)).expect("list");
    let positions: Vec<i64> = items.iter().map(|row| row.position).collect();
    assert_eq!(positions, vec![0, 1, 2], "must order by position ASC");
    let ids: Vec<&str> = items.iter().map(|row| row.id.as_str()).collect();
    assert_eq!(ids, vec!["item-a", "item-b", "item-c"]);
}

#[test]
fn list_task_checklist_items_includes_completed_rows() {
    // The repo is unfiltered — completion state is rendered, not
    // filtered. A regression that bolts on a `WHERE completed_at IS
    // NULL` would silently hide done items from the task detail
    // panel. Pin the contract.
    let conn = test_conn();
    let task = "task-1";
    TaskBuilder::new(task).insert(&conn);
    insert_item(&conn, "item-a", task, 0, "open", None);
    insert_item(
        &conn,
        "item-b",
        task,
        1,
        "done",
        Some("2026-05-03T13:00:00.000Z"),
    );

    let items = list_task_checklist_items(&conn, &tid(task)).expect("list");
    assert_eq!(items.len(), 2);
    assert!(items[0].completed_at.is_none());
    assert_eq!(
        items[1].completed_at.as_deref(),
        Some("2026-05-03T13:00:00.000Z")
    );
}

#[test]
fn list_task_checklist_items_isolates_tasks() {
    let conn = test_conn();
    let task_a = "task-A";
    let task_b = "task-B";
    TaskBuilder::new(task_a).insert(&conn);
    TaskBuilder::new(task_b).insert(&conn);
    insert_item(&conn, "a-1", task_a, 0, "for A", None);
    insert_item(&conn, "b-1", task_b, 0, "for B", None);

    let only_a = list_task_checklist_items(&conn, &tid(task_a)).expect("list");
    assert_eq!(only_a.len(), 1);
    assert_eq!(only_a[0].id, "a-1");
}

#[test]
fn list_task_checklist_items_for_tasks_handles_empty_input_without_a_query() {
    // Important shortcut: an empty `task_ids` slice must return Ok([])
    // WITHOUT preparing or executing a SQL statement, because the
    // `IN ()` shape is invalid SQLite syntax. A regression that drops
    // the early-return would surface as a hard `prepare` error at
    // every site that batches reads for a deduped-but-empty task list.
    let conn = test_conn();
    let items = list_task_checklist_items_for_tasks(&conn, &[]).expect("list empty");
    assert!(items.is_empty());
}

#[test]
fn list_task_checklist_items_for_tasks_orders_by_task_id_then_position() {
    let conn = test_conn();
    // Use task ids that lex-sort in a known order.
    let task_a = "task-aaa";
    let task_b = "task-bbb";
    TaskBuilder::new(task_a).insert(&conn);
    TaskBuilder::new(task_b).insert(&conn);
    insert_item(&conn, "i-b1", task_b, 0, "B0", None);
    insert_item(&conn, "i-b2", task_b, 1, "B1", None);
    insert_item(&conn, "i-a1", task_a, 0, "A0", None);
    insert_item(&conn, "i-a2", task_a, 1, "A1", None);

    let items = list_task_checklist_items_for_tasks(&conn, &[tid(task_b), tid(task_a)])
        .expect("list batch");

    // ORDER BY task_id ASC means task-aaa rows come before task-bbb,
    // regardless of the order task ids were passed to the query.
    let task_ids: Vec<&str> = items.iter().map(|row| row.task_id.as_str()).collect();
    assert_eq!(task_ids, vec![task_a, task_a, task_b, task_b]);
    let positions: Vec<i64> = items.iter().map(|row| row.position).collect();
    assert_eq!(positions, vec![0, 1, 0, 1]);
}

#[test]
fn list_task_checklist_items_for_tasks_skips_unrelated_tasks() {
    let conn = test_conn();
    let task_a = "task-aaa";
    let task_b = "task-bbb";
    let task_c = "task-ccc";
    TaskBuilder::new(task_a).insert(&conn);
    TaskBuilder::new(task_b).insert(&conn);
    TaskBuilder::new(task_c).insert(&conn);
    insert_item(&conn, "i-a", task_a, 0, "A", None);
    insert_item(&conn, "i-b", task_b, 0, "B", None);
    insert_item(&conn, "i-c", task_c, 0, "C", None);

    let only_ac = list_task_checklist_items_for_tasks(&conn, &[tid(task_a), tid(task_c)])
        .expect("list batch");
    let task_ids: Vec<&str> = only_ac.iter().map(|row| row.task_id.as_str()).collect();
    assert_eq!(task_ids, vec![task_a, task_c]);
}
