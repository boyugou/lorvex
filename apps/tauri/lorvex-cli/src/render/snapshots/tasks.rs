//! Snapshot coverage for `render_task_section`,
//! `render_task_collection`, `render_task_detail`, and
//! `render_task_action_result`.

use super::super::*;
use super::fixtures::*;
use crate::cli::OutputFormat;
use crate::models::{DependencyGraphEdge, DependencyGraphNode, DependencyGraphSnapshot};

fn fixture_dep_node(id: &str, title: &str, status: &str, list: &str) -> DependencyGraphNode {
    DependencyGraphNode {
        id: id.to_string(),
        title: title.to_string(),
        status: status.to_string(),
        priority: None,
        due_date: None,
        planned_date: None,
        list_id: list.to_string(),
    }
}

/// Two-root graph with a shared dependent so the tree renders both
/// branches without duplicating subtree state. Edge `A -> B` reads
/// "A depends on B" — the renderer inverts that into "B blocks A" so
/// children of B include A.
fn fixture_dependency_graph() -> DependencyGraphSnapshot {
    DependencyGraphSnapshot {
        limit_nodes: 50,
        limit_edges: 50,
        node_count: 4,
        edge_count: 3,
        nodes: vec![
            fixture_dep_node("task-root-a", "Design API", "open", "list-work"),
            fixture_dep_node("task-root-b", "Write spec", "open", "list-work"),
            fixture_dep_node("task-child", "Implement endpoint", "open", "list-work"),
            fixture_dep_node("task-grandchild", "Ship release", "open", "list-work"),
        ],
        edges: vec![
            DependencyGraphEdge {
                from: "task-child".to_string(),
                to: "task-root-a".to_string(),
            },
            DependencyGraphEdge {
                from: "task-child".to_string(),
                to: "task-root-b".to_string(),
            },
            DependencyGraphEdge {
                from: "task-grandchild".to_string(),
                to: "task-child".to_string(),
            },
        ],
        roots: vec!["task-root-a".to_string(), "task-root-b".to_string()],
        blocked: vec!["task-child".to_string(), "task-grandchild".to_string()],
        leaf_blockers: vec!["task-root-a".to_string(), "task-root-b".to_string()],
        truncated: false,
    }
}

#[test]
fn render_task_section_empty() {
    let out = render_task_section("Focus tasks", &[]);
    snapshot!(out);
}

#[test]
fn render_task_section_multiple() {
    let out = render_task_section("Focus tasks", &fixture_task_list_items());
    snapshot!(out);
}

#[test]
fn render_task_collection_text_empty() {
    let out = render_task_collection("Today", db_path(), vec![], OutputFormat::Text)
        .expect("render text");
    snapshot!(out);
}

#[test]
fn render_task_collection_text_single() {
    let out = render_task_collection(
        "Today",
        db_path(),
        vec![fixture_task_alpha()],
        OutputFormat::Text,
    )
    .expect("render text");
    snapshot!(out);
}

#[test]
fn render_task_collection_text_multiple() {
    let out = render_task_collection("Today", db_path(), fixture_tasks(), OutputFormat::Text)
        .expect("render text");
    snapshot!(out);
}

#[test]
fn render_task_collection_json_empty() {
    let out = render_task_collection("Today", db_path(), vec![], OutputFormat::Json)
        .expect("render json");
    snapshot_json!(out);
}

#[test]
fn render_task_collection_json_multiple() {
    let out = render_task_collection("Today", db_path(), fixture_tasks(), OutputFormat::Json)
        .expect("render json");
    snapshot_json!(out);
}

#[test]
fn render_task_detail_full() {
    let task = fixture_task_row_full();
    let out = render_task_detail(&task, db_path(), Some("Work"));
    snapshot!(out);
}

#[test]
fn render_task_detail_minimal() {
    let task = fixture_task_row_minimal();
    let out = render_task_detail(&task, db_path(), None);
    snapshot!(out);
}

#[test]
fn render_task_action_result_text() {
    let out = render_task_action_result(
        "task.complete",
        "task-alpha",
        "Ship feature",
        db_path(),
        OutputFormat::Text,
    )
    .expect("render text");
    snapshot!(out);
}

#[test]
fn render_dependency_graph_snapshot_text_tree() {
    let snapshot = fixture_dependency_graph();
    let out = render_dependency_graph_snapshot(db_path(), &snapshot, OutputFormat::Text)
        .expect("render text");
    snapshot!(out);
}

#[test]
fn render_dependency_graph_snapshot_text_empty() {
    let snapshot = DependencyGraphSnapshot {
        limit_nodes: 50,
        limit_edges: 50,
        node_count: 0,
        edge_count: 0,
        nodes: Vec::new(),
        edges: Vec::new(),
        roots: Vec::new(),
        blocked: Vec::new(),
        leaf_blockers: Vec::new(),
        truncated: false,
    };
    let out = render_dependency_graph_snapshot(db_path(), &snapshot, OutputFormat::Text)
        .expect("render text");
    snapshot!(out);
}

#[test]
fn render_task_action_result_json() {
    let out = render_task_action_result(
        "task.complete",
        "task-alpha",
        "Ship feature",
        db_path(),
        OutputFormat::Json,
    )
    .expect("render json");
    snapshot_json!(out);
}
