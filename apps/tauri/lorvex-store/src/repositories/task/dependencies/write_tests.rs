use super::write::*;
use crate::connection::open_db_in_memory;
use crate::error::StoreError;
use crate::repositories::task::write::{create_task, TaskCreateParams};
use lorvex_domain::TaskId;
use rusqlite::Connection;

fn setup() -> Connection {
    open_db_in_memory().expect("in-memory DB")
}

fn insert_task(conn: &Connection, id: &str, title: &str) {
    let params = TaskCreateParams::builder(id, title, "open", "v1", "2026-03-27T00:00:00Z")
        .build()
        .unwrap();
    create_task(conn, &params).unwrap();
}

// Issue #3285: tests bypass the trust-boundary parser via
// `from_trusted` because the seeded FK rows use short labels
// (`t1`, `t2`, …) rather than UUIDs.
fn task(id: &str) -> TaskId {
    TaskId::from_trusted(id.to_string())
}
fn tasks(ids: &[&str]) -> Vec<TaskId> {
    ids.iter().map(|s| task(s)).collect()
}

#[test]
fn batch_insert_creates_all_edges() {
    let conn = setup();
    insert_task(&conn, "t1", "Task 1");
    insert_task(&conn, "t2", "Task 2");
    insert_task(&conn, "t3", "Task 3");
    let count = insert_dependency_edges_batch(
        &conn,
        &task("t1"),
        &tasks(&["t2", "t3"]),
        "v1",
        "2026-03-27T00:00:00Z",
    )
    .unwrap();
    assert_eq!(count, 2);
    let edge_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_dependencies WHERE task_id = 't1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(edge_count, 2);
}

#[test]
fn batch_insert_ignores_duplicates() {
    let conn = setup();
    insert_task(&conn, "t1", "Task 1");
    insert_task(&conn, "t2", "Task 2");
    insert_dependency_edges_batch(
        &conn,
        &task("t1"),
        &tasks(&["t2"]),
        "v1",
        "2026-03-27T00:00:00Z",
    )
    .unwrap();
    let count = insert_dependency_edges_batch(
        &conn,
        &task("t1"),
        &tasks(&["t2"]),
        "v2",
        "2026-03-27T01:00:00Z",
    )
    .unwrap();
    assert_eq!(count, 0);
}

#[test]
fn batch_insert_empty_is_noop() {
    let conn = setup();
    let count = insert_dependency_edges_batch(&conn, &task("t1"), &[], "v1", "now").unwrap();
    assert_eq!(count, 0);
}

#[test]
fn batch_delete_removes_specific_edges() {
    let conn = setup();
    insert_task(&conn, "t1", "Task 1");
    insert_task(&conn, "t2", "Task 2");
    insert_task(&conn, "t3", "Task 3");
    insert_task(&conn, "t4", "Task 4");
    insert_dependency_edges_batch(
        &conn,
        &task("t1"),
        &tasks(&["t2", "t3", "t4"]),
        "v1",
        "2026-03-27T00:00:00Z",
    )
    .unwrap();
    let deleted = delete_dependency_edges_batch(&conn, &task("t1"), &tasks(&["t2", "t3"])).unwrap();
    assert_eq!(deleted, 2);
    let remaining: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_dependencies WHERE task_id = 't1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(remaining, 1);
}

#[test]
fn batch_delete_empty_is_noop() {
    let conn = setup();
    let count = delete_dependency_edges_batch(&conn, &task("t1"), &[]).unwrap();
    assert_eq!(count, 0);
}

/// any archived endpoint must reject the batch insert.
/// Without the preflight, a UI race could re-introduce a soft-deleted
/// task into the dependency graph, reviving it visually.
#[test]
fn batch_insert_rejects_archived_endpoint() {
    let conn = setup();
    insert_task(&conn, "live", "Alive");
    insert_task(&conn, "trashed", "Trashed");
    // Soft-delete one endpoint.
    conn.execute(
        "UPDATE tasks SET archived_at = '2026-04-26T00:00:00.000Z' WHERE id = 'trashed'",
        [],
    )
    .unwrap();

    let err = insert_dependency_edges_batch(
        &conn,
        &task("live"),
        &tasks(&["trashed"]),
        "v1",
        "2026-03-27T00:00:00Z",
    )
    .unwrap_err();
    assert!(matches!(err, StoreError::Validation(_)));

    // No edge written.
    let edge_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM task_dependencies", [], |r| r.get(0))
        .unwrap();
    assert_eq!(edge_count, 0);
}

/// missing-endpoint case must surface the same error
/// shape as archived, since both are "endpoint not live."
#[test]
fn batch_insert_rejects_missing_endpoint() {
    let conn = setup();
    insert_task(&conn, "live", "Alive");
    let err = insert_dependency_edges_batch(
        &conn,
        &task("live"),
        &tasks(&["does-not-exist"]),
        "v1",
        "2026-03-27T00:00:00Z",
    )
    .unwrap_err();
    assert!(matches!(err, StoreError::Validation(_)));
}

/// M5 regression — `(A → A)` self-dependency must be rejected by
/// the preflight as a typed `Validation` error rather than
/// bouncing off the `task_dependencies` CHECK constraint as a
/// generic SQL failure.
/// to `[A]` for the preflight, hiding the self-dep at that level
/// and only surfacing it as a generic constraint error at the
/// INSERT step.
#[test]
fn batch_insert_rejects_self_dependency_with_validation_error() {
    let conn = setup();
    insert_task(&conn, "alpha", "Alpha");

    let err = insert_dependency_edges_batch(
        &conn,
        &task("alpha"),
        &tasks(&["alpha"]),
        "v1",
        "2026-03-27T00:00:00Z",
    )
    .unwrap_err();
    match err {
        StoreError::Validation(msg) => {
            assert!(msg.contains("self-reference"), "got: {msg}");
        }
        other => panic!("expected StoreError::Validation, got {other:?}"),
    }

    // No edge was written.
    let edge_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM task_dependencies", [], |r| r.get(0))
        .unwrap();
    assert_eq!(edge_count, 0);
}

/// M5 — even when `depends_on_ids` mixes a self-reference with a
/// valid edge, the whole batch must reject. Partial writes would
/// leave the dependency graph in an inconsistent state.
#[test]
fn batch_insert_rejects_mixed_batch_with_self_reference() {
    let conn = setup();
    insert_task(&conn, "alpha", "Alpha");
    insert_task(&conn, "beta", "Beta");

    let err = insert_dependency_edges_batch(
        &conn,
        &task("alpha"),
        &tasks(&["beta", "alpha"]),
        "v1",
        "2026-03-27T00:00:00Z",
    )
    .unwrap_err();
    assert!(matches!(err, StoreError::Validation(_)));

    let edge_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM task_dependencies", [], |r| r.get(0))
        .unwrap();
    assert_eq!(edge_count, 0, "no partial writes on rejected batch");
}

/// M5 — the schema-level CHECK constraint is the backstop. Even if
/// a future code path bypassed the preflight, a raw INSERT of a
/// self-edge must still fail. This test pins the schema contract
/// so the constraint can never silently regress.
#[test]
fn schema_check_blocks_raw_self_edge_insert() {
    let conn = setup();
    insert_task(&conn, "alpha", "Alpha");

    let err = conn
        .execute(
            "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) \
             VALUES ('alpha', 'alpha', 'v1', '2026-03-27T00:00:00Z')",
            [],
        )
        .unwrap_err();
    let msg = err.to_string();
    assert!(
        msg.to_ascii_lowercase().contains("check"),
        "expected schema-level CHECK failure, got: {msg}"
    );
}

#[test]
fn batch_insert_single_edge() {
    let conn = setup();
    insert_task(&conn, "t1", "Task 1");
    insert_task(&conn, "t2", "Task 2");
    let count = insert_dependency_edges_batch(
        &conn,
        &task("t1"),
        &tasks(&["t2"]),
        "v1",
        "2026-03-27T00:00:00Z",
    )
    .unwrap();
    assert_eq!(count, 1);
}
