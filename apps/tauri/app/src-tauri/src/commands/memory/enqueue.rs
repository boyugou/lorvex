//! Sync-outbox enqueue helpers for the memory subsystem.
//!
//! Each Tauri-side memory mutation enqueues two envelopes — the
//! materialized `memories` row (so peers converge on the LWW state)
//! and the immutable `memory_revisions` snapshot (so the history view
//! is consistent across devices). Centralizing the enqueue logic here
//! keeps the `crud` cores readable and prevents accidental drift in
//! the entity-type / operation pairs the apply-pipeline expects.

use crate::commands::enqueue_to_outbox_typed;
use crate::error::AppError;
use lorvex_domain::naming::{ENTITY_MEMORY, ENTITY_MEMORY_REVISION, OP_DELETE, OP_UPSERT};
use lorvex_store::repositories::{memory_repo, memory_revision_repo};

pub(super) fn enqueue_memory_upsert_snapshot(
    conn: &rusqlite::Connection,
    key: &str,
) -> Result<(), AppError> {
    let entry = memory_repo::get_memory_entry(conn, key)
        .map_err(AppError::from)?
        .ok_or_else(|| AppError::NotFound(format!("Memory entry '{key}' not found")))?;
    let payload = serde_json::to_value(entry).map_err(AppError::from)?;
    enqueue_to_outbox_typed(conn, ENTITY_MEMORY, key, OP_UPSERT, &payload)
}

pub(super) fn enqueue_memory_delete_tombstone(
    conn: &rusqlite::Connection,
    key: &str,
    payload: &serde_json::Value,
) -> Result<(), AppError> {
    enqueue_to_outbox_typed(conn, ENTITY_MEMORY, key, OP_DELETE, payload)
}

pub(super) fn enqueue_memory_revision_snapshot(
    conn: &rusqlite::Connection,
    revision_id: &str,
) -> Result<(), AppError> {
    let revision = memory_revision_repo::get_revision(conn, revision_id)
        .map_err(AppError::from)?
        .ok_or_else(|| AppError::NotFound(format!("Memory revision '{revision_id}' not found")))?;
    let payload = serde_json::to_value(revision).map_err(AppError::from)?;
    enqueue_to_outbox_typed(
        conn,
        ENTITY_MEMORY_REVISION,
        revision_id,
        OP_UPSERT,
        &payload,
    )
}
