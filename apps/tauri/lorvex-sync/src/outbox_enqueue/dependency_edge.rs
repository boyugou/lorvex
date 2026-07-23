//! Wire-shape helpers for `task_dependencies` edge tombstones.
//!
//! Centralizing the payload-builder and composite-PK encoder here
//! keeps Tauri / MCP / CLI callers in lock-step with the apply-side
//! decoder. A single source of truth for the `{task_id}:{depends_on_task_id}`
//! `entity_id` shape and the canonical-row-shape delete payload.

use serde_json::Value;

/// build the canonical delete payload for a removed
/// `task_dependencies` edge.
///
/// The payload mirrors the `task_dependencies` schema exactly
/// (`task_id`, `depends_on_task_id`, `created_at`, `version`) so peers
/// that missed the upsert envelope can reconstruct the row from the
/// tombstone for restore-from-trash flows. Same shape the
/// `enqueue_payload_upsert` of the live edge produces.
///
/// Every surface (Tauri, MCP, CLI) routes through this single
/// payload-builder so the wire payload matches the apply-side
/// expectation in one place. Open-coded `serde_json::json!` literals
/// at each surface would drift (Tauri shipping only `task_id` +
/// `depends_on_task_id` while MCP / CLI carried the full row, etc.)
/// and break peer-side restore-from-trash flows.
pub fn build_dependency_edge_delete_payload(
    edge: &lorvex_workflow::lifecycle::DeletedDependencyEdge,
) -> Value {
    // Delegate to the spb primitive so the upsert (row → payload) and
    // delete (struct → payload) shapes are guaranteed identical
    //.
    let task_id = lorvex_domain::TaskId::from_trusted(edge.task_id.clone());
    let depends_on_task_id = lorvex_domain::TaskId::from_trusted(edge.depends_on_task_id.clone());
    lorvex_store::payload_loaders::task_dependency_payload(
        &task_id,
        &depends_on_task_id,
        &edge.version,
        &edge.created_at,
    )
}

/// Composite primary key encoding for a `task_dependencies` edge in the
/// outbox. Mirrors the `EDGE_TASK_DEPENDENCY` apply-side `entity_id`
/// shape (`{task_id}:{depends_on_task_id}`).
///
/// inlined as a `format!` in three call
/// sites that emitted dependency-edge tombstones; centralized here so
/// the encoding stays in lock-step with the apply-side decoder.
pub fn encode_dependency_edge_entity_id(
    edge: &lorvex_workflow::lifecycle::DeletedDependencyEdge,
) -> String {
    format!("{}:{}", edge.task_id, edge.depends_on_task_id)
}
