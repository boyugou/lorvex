//! `cancel_sync` Tauri command — user-visible "Cancel" button for a
//! long-running sync arm.
//!
//! The read-side spans the filesystem-bridge runtime and snapshot
//! import/export — every loop probes
//! [`super::cancel_signal::is_cancelled_for`] each iteration and
//! aborts cleanly when set. This command is the write-side that
//! flips the flag and scopes the cancel to a single [`SyncKind`], so
//! a stale UI button cannot interrupt a sibling arm that started
//! independently.

use super::cancel_signal::{request_cancel_for, SyncKind};

/// Flip the cancel flag for `kind`. The targeted sync loop observes
/// the flag at its next iteration boundary and unwinds cleanly,
/// dropping its [`super::cancel_signal::CancelGuard`] which clears
/// the flag for the next run. No-op when no run of `kind` is in
/// flight — the flag is reset by `CancelGuard::arm` on the next
/// arming, so a stale `true` cannot leak into a future run.
#[tauri::command]
pub fn cancel_sync(kind: SyncKind) -> Result<(), String> {
    request_cancel_for(kind);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::super::cancel_signal::{is_cancelled_for, CancelGuard};
    use super::*;

    /// Smoke test: the IPC entry point flips the targeted arm's flag
    /// from `false` to `true`. Sibling arms must not be affected —
    /// the per-arm scoping is what makes this command safe for the
    /// "Cancel" button on the Settings → Sync indicator (a stale
    /// click during a filesystem sync must not abort a concurrent
    /// snapshot import).
    #[test]
    fn cancel_sync_flips_only_targeted_arm() {
        let _fs = CancelGuard::arm(SyncKind::FilesystemBridge);
        let _imp = CancelGuard::arm(SyncKind::SnapshotImport);
        cancel_sync(SyncKind::FilesystemBridge).expect("cancel_sync");
        assert!(is_cancelled_for(SyncKind::FilesystemBridge));
        assert!(!is_cancelled_for(SyncKind::SnapshotImport));
    }
}
