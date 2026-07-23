//! High-level "read snapshot + enqueue upsert" entry point used by
//! the MCP server, the Tauri app, and the CLI as the canonical
//! shared write core after any entity mutation.

use rusqlite::Connection;

use lorvex_domain::hlc_state::HlcState;

use super::context::OutboxWriteContext;
use super::error::EnqueueError;
use super::payload::enqueue_payload_upsert;
use super::snapshot::read_entity_payload_snapshot;

/// Read an entity's current state and enqueue it to the sync outbox.
///
/// This is the "shared write core" enqueue function. Both the MCP server and
/// the Tauri app should call this after any entity mutation instead of their
/// own enqueue code.
///
/// Steps:
/// 1. Read current entity snapshot from DB
/// 2. Canonicalize the JSON payload
/// 3. Generate an HLC version
/// 4. Build a `SyncEnvelope`
/// 5. Enqueue coalesced (replaces any pending unsynced entry for same entity)
pub fn enqueue_entity_upsert(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    hlc_state: &mut HlcState,
    device_id: &str,
) -> Result<(), EnqueueError> {
    let payload = read_entity_payload_snapshot(conn, entity_type, entity_id)?;
    let version = hlc_state.generate().to_string();
    enqueue_payload_upsert(
        conn,
        entity_type,
        entity_id,
        &payload,
        OutboxWriteContext {
            version: &version,
            device_id,
        },
    )
}
