#[cfg(target_os = "macos")]
use std::sync::atomic::{AtomicBool, Ordering};

#[cfg(target_os = "macos")]
static WINDOW_RESTORE_IN_FLIGHT: AtomicBool = AtomicBool::new(false);
#[cfg(target_os = "macos")]
static WINDOW_RESTORE_PENDING: AtomicBool = AtomicBool::new(false);

/// the `compare_exchange`
/// here is the canonical "single-writer election" pattern. Two
/// concurrent reactivation triggers (Spaces switch + tray click +
/// dock-icon click landing in the same OS event tick) all race the
/// same CAS; exactly one returns `Ok` and runs the restore session,
/// the rest see `Err` and either drop or set the pending flag.
/// `Ordering::SeqCst` on both success and failure orderings is
/// deliberate even though the failure path could be `Acquire` —
/// macOS reactivation triggers are rare, so the marginal `dmb ish`
/// cost is irrelevant, and the symmetric `SeqCst` keeps the
/// race-correctness reasoning trivial: every reader observes the
/// same global linearization of "in-flight bit set/cleared" events.
#[cfg(target_os = "macos")]
pub(super) fn claim_window_restore_in_flight() -> bool {
    WINDOW_RESTORE_IN_FLIGHT
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_ok()
}

#[cfg(target_os = "macos")]
pub(super) fn release_window_restore_in_flight() {
    WINDOW_RESTORE_IN_FLIGHT.store(false, Ordering::SeqCst);
}

#[cfg(target_os = "macos")]
pub(super) fn mark_window_restore_pending() {
    WINDOW_RESTORE_PENDING.store(true, Ordering::SeqCst);
}

#[cfg(target_os = "macos")]
pub(super) fn take_window_restore_pending() -> bool {
    WINDOW_RESTORE_PENDING.swap(false, Ordering::SeqCst)
}
