#[cfg(test)]
use super::remote_core::apply_remote_sync_records_with_checkpoint_writer;
#[cfg(test)]
use super::sync_checkpoint::upsert_sync_checkpoint_timestamp_if_newer;
#[cfg(test)]
use super::{ApplyRemoteSyncResult, IncomingSyncRecord, RemoteApplyMode};
#[cfg(test)]
use crate::commands::sync::filesystem_bridge::{
    store_filesystem_bridge_pull_cursor, FilesystemBridgePullCursor,
};
#[cfg(test)]
use crate::error::AppResult;

// production uses
// `apply_remote_sync_records_with_checkpoint_writer` directly. This
// thin wrapper exists only for tests that don't need the full
// closure shape. Gated on `cfg(test)` so production binaries don't
// ship the dead code path.
#[cfg(test)]
pub(crate) fn apply_remote_sync_envelopes_with_filesystem_bridge_cursor(
    conn: &rusqlite::Connection,
    records: Vec<IncomingSyncRecord>,
    synced_ts: &str,
    filesystem_bridge_cursor: Option<&FilesystemBridgePullCursor>,
) -> AppResult<ApplyRemoteSyncResult> {
    apply_remote_sync_records_with_checkpoint_writer(
        conn,
        records,
        synced_ts,
        RemoteApplyMode::BestEffort,
        |conn, _ordered, synced_ts| {
            upsert_sync_checkpoint_timestamp_if_newer(conn, "last_pull_at", synced_ts)?;
            if let Some(cursor) = filesystem_bridge_cursor {
                store_filesystem_bridge_pull_cursor(conn, cursor)?;
            }
            Ok(())
        },
    )
}

// Thin wrapper that gives tests an ergonomic path without threading
// a `None` cursor — the production sync runtime calls
// `apply_remote_sync_envelopes_with_filesystem_bridge_cursor`
// directly. `cfg(test)` keeps the wrapper out of production
// binaries.
#[cfg(test)]
pub(crate) fn apply_remote_sync_envelopes_internal(
    conn: &rusqlite::Connection,
    records: Vec<IncomingSyncRecord>,
    synced_ts: &str,
) -> AppResult<ApplyRemoteSyncResult> {
    apply_remote_sync_envelopes_with_filesystem_bridge_cursor(conn, records, synced_ts, None)
}

// the renderer-facing `apply_remote_sync_envelopes`
// `#[tauri::command]` was deleted. It exposed the apply pipeline to
// the frontend with no production caller — a compromised webview
// could push arbitrary `IncomingSyncRecord`s, race the local-author
// HLC, and bypass the transport-level provenance gating that
// The filesystem bridge and future remote transports enforce. The
// `MAX_APPLY_REMOTE_BATCH_SIZE = 2000` clamp it carried did not
// help — that bound is plenty for targeted corruption.
//
// The filesystem-bridge pull path calls the internal helpers directly.
// Future remote transports should use the same internal entrypoint. Nothing
// else needs the IPC entrypoint.
