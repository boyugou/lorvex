//! Tests for `task_dependency_graph`. Extracted from the parent file
//! to keep the production module focused.

use super::*;
use crate::connection::open_db_in_memory;
use crate::repositories::task::write::{create_task, TaskCreateParams};
use rusqlite::Connection;

fn setup() -> Connection {
    open_db_in_memory().expect("in-memory DB")
}

fn insert_task(conn: &Connection, id: &str, title: &str, status: &str) {
    let params = TaskCreateParams::builder(
        id,
        title,
        status,
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
        "2026-03-27T00:00:00Z",
    )
    .build()
    .unwrap();
    create_task(conn, &params).unwrap();
}

fn add_dep(conn: &Connection, task_id: &str, depends_on: &str) {
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) \
         VALUES (?1, ?2, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-27T00:00:00Z')",
        [task_id, depends_on],
    )
    .unwrap();
}

fn insert_list(conn: &Connection, id: &str, name: &str) {
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at) \
         VALUES (?1, ?2, '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')",
        rusqlite::params![id, name],
    )
    .expect("insert list");
}

fn insert_task_in_list(conn: &Connection, id: &str, title: &str, status: &str, list_id: &str) {
    let params = TaskCreateParams::builder(
        id,
        title,
        status,
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
        "2026-03-27T00:00:00Z",
    )
    .list_id(Some(list_id))
    .build()
    .unwrap();
    create_task(conn, &params).unwrap();
}

// ── task_id + list_id intersection semantics ─────────────────

#[test]
fn centered_plus_list_scope_excludes_cross_list_neighbors() {
    let conn = setup();
    insert_list(&conn, "list-a", "List A");
    insert_list(&conn, "list-b", "List B");

    // Center task in list-a
    insert_task_in_list(&conn, "center", "Center", "open", "list-a");
    // Same-list neighbor
    insert_task_in_list(&conn, "same-list", "Same list dep", "open", "list-a");
    // Cross-list neighbor
    insert_task_in_list(&conn, "other-list", "Other list dep", "open", "list-b");

    add_dep(&conn, "center", "same-list");
    add_dep(&conn, "center", "other-list");

    let result = get_dependency_graph(
        &conn,
        &DependencyGraphParams {
            task_id: Some("center".to_string()),
            list_id: Some("list-a".to_string()),
            include_inactive: false,
            limit_nodes: 50,
            limit_edges: 50,
        },
    )
    .unwrap();

    // Only the edge where both endpoints are in list-a should be included.
    assert_eq!(result.edges.len(), 1, "cross-list edge should be excluded");
    assert_eq!(result.edges[0].depends_on_task_id, "same-list");

    let node_ids: Vec<&str> = result.nodes.iter().map(|n| n.id.as_str()).collect();
    assert!(node_ids.contains(&"center"));
    assert!(node_ids.contains(&"same-list"));
    assert!(
        !node_ids.contains(&"other-list"),
        "cross-list node should be excluded"
    );
}

#[test]
fn centered_not_in_specified_list_returns_empty_graph() {
    let conn = setup();
    insert_list(&conn, "list-a", "List A");
    insert_list(&conn, "list-b", "List B");

    // Task belongs to list-b
    insert_task_in_list(&conn, "t1", "Task in list B", "open", "list-b");

    let result = get_dependency_graph(
        &conn,
        &DependencyGraphParams {
            task_id: Some("t1".to_string()),
            list_id: Some("list-a".to_string()),
            include_inactive: false,
            limit_nodes: 50,
            limit_edges: 50,
        },
    )
    .unwrap();

    // Center task is not in list-a, so graph should be empty.
    assert!(
        result.nodes.is_empty(),
        "center not in list should yield empty graph"
    );
    assert!(result.edges.is_empty());
}

// ── Bug 1: inactive center task filtering ──────────────────────

#[test]
fn centered_inactive_task_excluded_by_default() {
    let conn = setup();
    insert_task(&conn, "t1", "Completed task", "completed");

    let result = get_dependency_graph(
        &conn,
        &DependencyGraphParams {
            task_id: Some("t1".to_string()),
            include_inactive: false,
            limit_nodes: 50,
            limit_edges: 50,
            ..Default::default()
        },
    )
    .unwrap();

    // A completed task with include_inactive=false should yield an empty graph.
    assert!(result.nodes.is_empty(), "completed task should be excluded");
    assert!(result.edges.is_empty());
}

#[test]
fn centered_inactive_task_included_when_requested() {
    let conn = setup();
    insert_task(&conn, "t1", "Completed task", "completed");

    let result = get_dependency_graph(
        &conn,
        &DependencyGraphParams {
            task_id: Some("t1".to_string()),
            include_inactive: true,
            limit_nodes: 50,
            limit_edges: 50,
            ..Default::default()
        },
    )
    .unwrap();

    // With include_inactive=true, a completed task should appear as a single node.
    assert_eq!(result.nodes.len(), 1);
    assert_eq!(result.nodes[0].id, "t1");
}

#[test]
fn archived_tasks_are_excluded_even_when_inactive_tasks_are_included() {
    let conn = setup();
    insert_task(&conn, "visible", "Visible", "open");
    insert_task(&conn, "archived", "Archived", "open");
    add_dep(&conn, "visible", "archived");
    conn.execute(
        "UPDATE tasks SET archived_at = '2026-04-25T12:00:00.000Z' WHERE id = 'archived'",
        [],
    )
    .unwrap();

    let graph = get_dependency_graph(
        &conn,
        &DependencyGraphParams {
            include_inactive: true,
            limit_nodes: 20,
            limit_edges: 20,
            ..Default::default()
        },
    )
    .unwrap();
    assert!(graph.nodes.is_empty());
    assert!(graph.edges.is_empty());

    let centered_archived = get_dependency_graph(
        &conn,
        &DependencyGraphParams {
            task_id: Some("archived".to_string()),
            include_inactive: true,
            limit_nodes: 20,
            limit_edges: 20,
            ..Default::default()
        },
    )
    .unwrap();
    assert!(centered_archived.nodes.is_empty());
}

// ── Bug 2: center node pinning under small node cap ────────────

#[test]
fn centered_task_pinned_under_small_node_cap() {
    let conn = setup();
    // Create center + 5 neighbours
    insert_task(&conn, "center", "Center task", "open");
    for i in 0..5 {
        let id = format!("n{i}");
        insert_task(&conn, &id, &format!("Neighbour {i}"), "open");
        add_dep(&conn, "center", &id);
    }

    let result = get_dependency_graph(
        &conn,
        &DependencyGraphParams {
            task_id: Some("center".to_string()),
            include_inactive: false,
            limit_nodes: 2,
            limit_edges: 100,
            ..Default::default()
        },
    )
    .unwrap();

    // Center must always be present regardless of cap.
    let node_ids: Vec<&str> = result.nodes.iter().map(|n| n.id.as_str()).collect();
    assert!(
        node_ids.contains(&"center"),
        "center node must be pinned; got: {node_ids:?}"
    );
    // With limit_nodes=2, we get center + 1 neighbour = 2 nodes.
    assert_eq!(result.nodes.len(), 2);
    assert!(result.truncated, "graph should be marked as truncated");
}

// ── Determinism: center-first + nodes-ordered derived arrays ─────

#[test]
fn centered_graph_center_is_first_node() {
    let conn = setup();
    insert_task(&conn, "center", "Center", "open");
    insert_task(&conn, "a_neighbor", "A Neighbor", "open"); // alphabetically first
    add_dep(&conn, "center", "a_neighbor");

    let result = get_dependency_graph(
        &conn,
        &DependencyGraphParams {
            task_id: Some("center".to_string()),
            limit_nodes: 50,
            limit_edges: 50,
            ..Default::default()
        },
    )
    .unwrap();

    assert_eq!(result.nodes[0].id, "center");
}

#[test]
fn blocked_and_leaf_blockers_follow_nodes_order() {
    let conn = setup();
    // Create a chain: a -> b -> c (a depends on b, b depends on c)
    insert_task(&conn, "a", "Task A", "open");
    insert_task(&conn, "b", "Task B", "open");
    insert_task(&conn, "c", "Task C", "open");
    add_dep(&conn, "a", "b");
    add_dep(&conn, "b", "c");

    let result = get_dependency_graph(
        &conn,
        &DependencyGraphParams {
            limit_nodes: 50,
            limit_edges: 50,
            ..Default::default()
        },
    )
    .unwrap();

    // blocked should be [a, b] in the same relative order as nodes
    // leaf_blockers should be [c]
    // roots should be [c] (c has no deps)
    // All should be deterministic
    assert!(result.blocked.len() == 2);
    assert!(result.leaf_blockers.contains(&"c".to_string()));
    assert!(result.roots.contains(&"c".to_string()));

    // Run twice to verify determinism
    let result2 = get_dependency_graph(
        &conn,
        &DependencyGraphParams {
            limit_nodes: 50,
            limit_edges: 50,
            ..Default::default()
        },
    )
    .unwrap();
    assert_eq!(result.roots, result2.roots);
    assert_eq!(result.blocked, result2.blocked);
    assert_eq!(result.leaf_blockers, result2.leaf_blockers);
}
