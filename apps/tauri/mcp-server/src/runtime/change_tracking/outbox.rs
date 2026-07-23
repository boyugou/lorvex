//! Low-level outbox writers shared by `log_change`, the changelog
//! enqueue helper, and the per-entity relation enqueue helpers.

use lorvex_domain::naming::OP_DELETE;
use lorvex_sync::outbox_enqueue::{
    enqueue_payload_delete, enqueue_payload_upsert, OutboxWriteContext,
};
use rusqlite::Connection;
use serde_json::Value;

use super::hlc::generate_hlc_version;
use crate::error::McpError;

/// Write a sync event to `sync_outbox`. The row is immediately
/// dispatchable — sync push picks it up on the next cycle.
pub(super) fn write_to_outbox(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    sync_operation: &str,
    payload: &Value,
    device_id: &str,
) -> Result<(), McpError> {
    let version = generate_hlc_version(conn)?;
    let ctx = OutboxWriteContext {
        version: &version,
        device_id,
    };

    if sync_operation == OP_DELETE {
        enqueue_payload_delete(conn, entity_type, entity_id, payload, ctx)
    } else {
        enqueue_payload_upsert(conn, entity_type, entity_id, payload, ctx)
    }
    .map_err(|e| {
        McpError::Internal(format!(
            "outbox enqueue failed for {entity_type}/{entity_id}: {e}"
        ))
    })
}
