//! Per-arm cancellation signals for long-running sync commands.
//!
//! Sharing a single `OnceLock<Arc<AtomicBool>>` across filesystem-bridge
//! sync, snapshot import, and snapshot export would conflate independent
//! features (a user clicking "Cancel" during filesystem sync would also
//! cancel a concurrent snapshot import), make `Drop` unable to tell which arm armed the
//! flag (the outer guard's `false` could be reset by an inner
//! guard's drop), and let a stale, scope-less `cancel_sync` IPC
//! cancel a brand-new run started by a different code path.
//!
//! Design — one signal per arm:
//!   * [`SyncKind`] tags the arms that own a long-running sync
//!     loop. The discriminant is what the IPC accepts as its scope
//!     parameter.
//!   * Each kind has its own `OnceLock<Arc<AtomicBool>>` keyed off
//!     `SyncKind::index`. Arming kind A does not affect kind B's
//!     flag, so concurrent runs of different kinds cancel
//!     independently.
//!   * [`CancelGuard`] carries the kind it armed; drop only resets
//!     that kind's flag. Nested arming of the same kind is rare in
//!     practice (one IPC handler owns each arm), but if it happens
//!     the inner guard re-clears the same arm's flag — that's still
//!     correct because both guards belong to the same arm.
//!   * [`request_cancel_for`] flips a specific arm's flag. The
//!     [`request_cancel_all`] helper exists for the global "stop
//!     everything" hammer for legacy `cancel_sync` callers.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, OnceLock};

/// One discriminant per long-running sync arm.
///
/// New arms must add a variant here AND a slot in `signal_for`. The
/// match is exhaustive in `signal_for` so the compiler enforces the
/// invariant — a future arm cannot ship without its own slot.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SyncKind {
    /// Filesystem-bridge collect / push / pull cycle.
    FilesystemBridge,
    /// `data_snapshot::import` long-running restore.
    SnapshotImport,
    /// `data_snapshot::export` long-running write.
    SnapshotExport,
}

impl SyncKind {
    /// Every kind variant returns a stable 0..N index used as the
    /// slot index in the per-arm signal table. Adding a kind requires
    /// bumping `KIND_COUNT` and giving the new kind its own index.
    const fn index(self) -> usize {
        match self {
            Self::FilesystemBridge => 0,
            Self::SnapshotImport => 1,
            Self::SnapshotExport => 2,
        }
    }

    /// Iterate every kind. Lets `request_cancel_all` and friends
    /// fan out without hardcoding the variant set.
    const fn all() -> &'static [SyncKind] {
        &[
            Self::FilesystemBridge,
            Self::SnapshotImport,
            Self::SnapshotExport,
        ]
    }
}

const KIND_COUNT: usize = 3;

/// Per-arm signal table. Each slot is lazily initialized on first
/// access. The `Arc` is kept (rather than a raw `&'static
/// AtomicBool`) because the audit spec calls for `Arc<AtomicBool>`
/// — easier for subagent dispatchers to trace the type signature
/// across the helper boundary.
fn signal_for(kind: SyncKind) -> &'static Arc<AtomicBool> {
    static SIGNALS: OnceLock<[Arc<AtomicBool>; KIND_COUNT]> = OnceLock::new();
    let slots = SIGNALS.get_or_init(|| std::array::from_fn(|_| Arc::new(AtomicBool::new(false))));
    &slots[kind.index()]
}

/// Cheap probe for I/O loops scoped to a single arm. Returns `true`
/// once `request_cancel_for(kind)` has been called for the
/// currently-armed run of that arm.
pub(crate) fn is_cancelled_for(kind: SyncKind) -> bool {
    signal_for(kind).load(Ordering::Relaxed)
}

/// Flip a specific arm's flag to true. Idempotent.
///
/// Called from the `cancel_sync` Tauri command (the user-visible
/// "Cancel" button on the Settings → Sync in-flight indicator) and
/// from the `RunEvent::Exit` lifecycle hook (implicit cancel-on-quit
/// via [`request_cancel_all`]). The cancel takes effect at the next
/// `is_cancelled_for(kind)` probe inside the targeted sync loop.
pub(super) fn request_cancel_for(kind: SyncKind) {
    signal_for(kind).store(true, Ordering::Relaxed);
}

/// "Stop everything" hammer used by the app-quit lifecycle hook. Flips
/// every arm's flag so any in-flight filesystem-bridge / snapshot-import /
/// snapshot-export loop aborts at its next probe
/// rather than dragging shutdown out behind an unbounded network round
/// trip. Tests also use this to exercise the multi-arm flag-spread
/// invariant.
pub(crate) fn request_cancel_all() {
    for kind in SyncKind::all() {
        request_cancel_for(*kind);
    }
}

/// Handle accessor — pins the `Arc<AtomicBool>` shape the audit spec
/// requires. Currently only tests need to hold a raw `Arc`; production
/// callers go through `is_cancelled_for` / `request_cancel_for`.
#[cfg(test)]
fn shared_handle_for(kind: SyncKind) -> Arc<AtomicBool> {
    signal_for(kind).clone()
}

/// RAII guard that arms a specific arm's cancel flag.
///
/// Construction clears the flag for the supplied arm so a stale
/// cancel from a prior run cannot poison a new run. Drop clears the
/// flag for the same arm — different arms' flags are NOT touched.
#[must_use = "drop the guard when the sync run finishes"]
pub(crate) struct CancelGuard {
    kind: SyncKind,
}

impl CancelGuard {
    /// Arm a specific sync arm. Drop only clears this arm's flag —
    /// concurrent runs of OTHER arms are unaffected.
    pub(crate) fn arm(kind: SyncKind) -> Self {
        signal_for(kind).store(false, Ordering::Relaxed);
        Self { kind }
    }
}

impl Drop for CancelGuard {
    fn drop(&mut self) {
        signal_for(self.kind).store(false, Ordering::Relaxed);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    /// Per-arm signals are still process-global (one slot per kind),
    /// so concurrent test runs of the same kind would race. Serialize
    /// every test that touches the signals behind this mutex.
    static TEST_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn guard_clears_flag_on_drop() {
        let _serialize = TEST_LOCK
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let guard = CancelGuard::arm(SyncKind::FilesystemBridge);
        request_cancel_for(SyncKind::FilesystemBridge);
        assert!(is_cancelled_for(SyncKind::FilesystemBridge));
        drop(guard);
        assert!(!is_cancelled_for(SyncKind::FilesystemBridge));
    }

    #[test]
    fn fresh_arm_clears_stale_flag() {
        let _serialize = TEST_LOCK
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        signal_for(SyncKind::FilesystemBridge).store(true, Ordering::Relaxed);
        let _guard = CancelGuard::arm(SyncKind::FilesystemBridge);
        assert!(!is_cancelled_for(SyncKind::FilesystemBridge));
    }

    /// per-arm scoping. A cancel request for one arm
    /// must NOT flip a concurrently-armed sibling arm.
    #[test]
    fn cancel_for_one_kind_does_not_flip_another() {
        let _serialize = TEST_LOCK
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let _fs_guard = CancelGuard::arm(SyncKind::FilesystemBridge);
        let _import_guard = CancelGuard::arm(SyncKind::SnapshotImport);

        request_cancel_for(SyncKind::FilesystemBridge);

        assert!(is_cancelled_for(SyncKind::FilesystemBridge));
        assert!(
            !is_cancelled_for(SyncKind::SnapshotImport),
            "concurrent SnapshotImport must not see a filesystem sync cancel"
        );
    }

    /// outer guard's drop only clears its OWN arm's
    /// flag. An inner guard for a different arm dropping must not
    /// reset the outer arm's flag — the previous global-flag design
    /// had this bug (inner drop reset the shared flag, outer guard
    /// then probed `false` even though the user had requested cancel
    /// for the outer arm).
    #[test]
    fn inner_guard_drop_does_not_clear_outer_arm() {
        let _serialize = TEST_LOCK
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let _outer = CancelGuard::arm(SyncKind::FilesystemBridge);
        request_cancel_for(SyncKind::FilesystemBridge);
        assert!(is_cancelled_for(SyncKind::FilesystemBridge));

        {
            let _inner = CancelGuard::arm(SyncKind::SnapshotImport);
            // inner drops here
        }

        assert!(
            is_cancelled_for(SyncKind::FilesystemBridge),
            "outer arm's cancel must survive inner arm's drop"
        );
    }

    #[test]
    fn request_cancel_all_flips_every_arm() {
        let _serialize = TEST_LOCK
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        for kind in SyncKind::all() {
            let _g = CancelGuard::arm(*kind);
        }
        // All flags clear after re-arming
        for kind in SyncKind::all() {
            assert!(!is_cancelled_for(*kind));
        }
        request_cancel_all();
        for kind in SyncKind::all() {
            assert!(is_cancelled_for(*kind));
        }
        // Manual cleanup so subsequent tests start clean
        for kind in SyncKind::all() {
            signal_for(*kind).store(false, Ordering::Relaxed);
        }
    }

    #[test]
    fn shared_handle_observes_cancel() {
        let _serialize = TEST_LOCK
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let _guard = CancelGuard::arm(SyncKind::FilesystemBridge);
        let handle = shared_handle_for(SyncKind::FilesystemBridge);
        assert!(!handle.load(Ordering::Relaxed));
        request_cancel_for(SyncKind::FilesystemBridge);
        assert!(handle.load(Ordering::Relaxed));
    }

    #[test]
    fn any_cancelled_probe_returns_true_when_any_arm_set() {
        let _serialize = TEST_LOCK
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        for kind in SyncKind::all() {
            let _g = CancelGuard::arm(*kind);
        }
        assert!(!SyncKind::all().iter().any(|k| is_cancelled_for(*k)));
        request_cancel_for(SyncKind::SnapshotExport);
        assert!(SyncKind::all().iter().any(|k| is_cancelled_for(*k)));
        // cleanup
        for kind in SyncKind::all() {
            signal_for(*kind).store(false, Ordering::Relaxed);
        }
    }
}
