//! Per-entity relation sync enqueuers (task_tag, task_dependency,
//! task_reminder, ...). These run alongside a parent mutation's
//! `log_change` call and do NOT bump `local_change_seq` — the parent
//! funnel covers that for the whole write batch.

use lorvex_domain::naming::{
    EDGE_TASK_DEPENDENCY, EDGE_TASK_TAG, ENTITY_TASK_REMINDER, OP_DELETE, OP_UPSERT,
};
use rusqlite::Connection;
use serde_json::{json, Value};

use super::get_or_create_sync_device_id;
use super::is_delete_sync_operation;
use super::outbox::write_to_outbox;
use super::snapshot::{read_current_entity_snapshot, read_current_entity_snapshots};
use crate::error::McpError;

/// Enqueue a sync event for a relation entity (task_tag, task_dependency, etc.)
/// without creating a changelog entry. The parent entity's changelog
/// entry covers the semantic change; this only ensures the relation row
/// is synced independently.
///
/// Callers performing a DELETE-then-enqueue sequence should capture the
/// row snapshot BEFORE the delete and route through
/// [`enqueue_relation_sync_with_snapshot`] instead — by the time this
/// helper runs the row is gone, so it falls back to a degenerate
/// `{"id": entity_id}` payload that peers cannot reconstruct from.
pub(crate) fn enqueue_relation_sync(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    operation: &str,
) -> Result<(), McpError> {
    let snapshot = read_current_entity_snapshot(conn, entity_type, entity_id)?;
    enqueue_relation_sync_with_snapshot(conn, entity_type, entity_id, operation, snapshot)
}

/// Enqueue a sync event for a relation entity using a caller-provided
/// snapshot. Required for the DELETE path so the envelope payload
/// reflects the row's pre-delete state — issue #2818.
pub(crate) fn enqueue_relation_sync_with_snapshot(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    operation: &str,
    snapshot: Option<Value>,
) -> Result<(), McpError> {
    let device_id = get_or_create_sync_device_id(conn)?;

    let sync_operation = if is_delete_sync_operation(operation) {
        OP_DELETE
    } else {
        OP_UPSERT
    };

    // For a non-delete operation `snapshot` may already be Some (the
    // caller had it cached) or None (helper reads it). For delete
    // operations the caller is responsible for capturing the
    // pre-delete snapshot — fall back only as a last resort so a
    // refactor that drops the snapshot doesn't crash the write path.
    let payload = match snapshot {
        Some(value) => value,
        None => read_current_entity_snapshot(conn, entity_type, entity_id)?
            .unwrap_or_else(|| json!({ "id": entity_id })),
    };

    write_to_outbox(
        conn,
        entity_type,
        entity_id,
        sync_operation,
        &payload,
        &device_id,
    )?;
    // This helper does NOT bump `local_change_seq`. Every call site
    // already pairs a parent mutation routed through `log_change`,
    // which bumps once for the whole write batch.
    Ok(())
}

pub(crate) fn enqueue_task_reminder_syncs(
    conn: &Connection,
    reminder_ids: &[String],
) -> Result<(), McpError> {
    if reminder_ids.is_empty() {
        return Ok(());
    }
    let prefetched = read_current_entity_snapshots(conn, ENTITY_TASK_REMINDER, reminder_ids)?;
    for reminder_id in reminder_ids {
        let snapshot = prefetched.get(reminder_id).cloned();
        enqueue_relation_sync_with_snapshot(
            conn,
            ENTITY_TASK_REMINDER,
            reminder_id,
            OP_UPSERT,
            snapshot,
        )?;
    }
    Ok(())
}

pub(crate) fn enqueue_deleted_task_dependency_syncs(
    conn: &Connection,
    edges: &[lorvex_workflow::lifecycle::DeletedDependencyEdge],
) -> Result<(), McpError> {
    // The payload-builder + entity_id encoder live in
    // `lorvex_sync::outbox_enqueue` so this surface, the Tauri
    // `enqueue_deleted_dep_edges`, and the CLI
    // `enqueue_deleted_dependency_edges` all emit byte-identical
    // dependency-edge tombstones.
    for edge in edges {
        let entity_id = lorvex_sync::outbox_enqueue::encode_dependency_edge_entity_id(edge);
        let snapshot = lorvex_sync::outbox_enqueue::build_dependency_edge_delete_payload(edge);
        enqueue_relation_sync_with_snapshot(
            conn,
            EDGE_TASK_DEPENDENCY,
            &entity_id,
            OP_DELETE,
            Some(snapshot),
        )?;
    }
    Ok(())
}

pub(crate) fn enqueue_task_tag_edge_syncs(
    conn: &Connection,
    edges: &[lorvex_workflow::lifecycle::CopiedTagEdge],
) -> Result<(), McpError> {
    // Synthesize the snapshot in-memory from the typed edge struct
    // (which already carries every `task_tags` column —
    // `task_id, tag_id, version, created_at`) instead of re-reading
    // each row out of the DB through `enqueue_relation_sync`.
    for edge in edges {
        let entity_id = format!("{}:{}", edge.task_id, edge.tag_id);
        let snapshot = json!({
            "task_id": edge.task_id,
            "tag_id": edge.tag_id,
            "version": edge.version,
            "created_at": edge.created_at,
        });
        enqueue_relation_sync_with_snapshot(
            conn,
            EDGE_TASK_TAG,
            &entity_id,
            OP_UPSERT,
            Some(snapshot),
        )?;
    }
    Ok(())
}
