//! Helpers for stamping locally-authored apply-time writes with the
//! local device's HLC suffix.
//!
//! The apply pipeline runs exclusively inside the Tauri app process
//! (sync transports — filesystem bridge, future providers — live under
//! `app/src-tauri/src/commands/sync_*`), so any merge tombstone minted
//! here is an `HlcSurface::App` write — even though the trigger came
//! from a remote envelope.
//!
//! Without this surface tag, the tombstone inherits the remote peer's
//! suffix, breaking device-id filters in
//! remote device-cursor recording and conflict-log diagnostics
//! (for tag merges; sync apply F2 for recurrence merges).

use lorvex_domain::hlc::HlcSurface;
use lorvex_runtime::device_id_to_hlc_suffix;
use rusqlite::Connection;

/// Read the local device's HLC suffix for use on locally-authored
/// merge tombstones. Returns `None` when the device-id checkpoint is
/// missing; callers fall back to a remote-derived suffix in that case.
pub(super) fn read_local_device_hlc_suffix(conn: &Connection) -> Option<String> {
    let device_id: String = conn
        .query_row(
            "SELECT value FROM sync_checkpoints WHERE key = 'device_id'",
            [],
            |row| row.get::<_, String>(0),
        )
        .ok()?;
    if device_id.is_empty() {
        return None;
    }
    Some(device_id_to_hlc_suffix(&device_id, HlcSurface::App))
}
