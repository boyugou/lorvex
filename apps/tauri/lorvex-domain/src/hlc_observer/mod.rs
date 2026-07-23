//! Process-wide hook for the apply pipeline (and lower-layer lifecycle
//! ops) to feed locally-minted HLCs back into the caller's `HlcState`.
//!
//! # Why this exists
//!
//! Most HLCs that affect this device's clock state are either generated
//! locally (`HlcState::generate`) or arrive on a peer envelope
//! (`observe_remote_version` → `HlcState::update_on_receive`). A few
//! merge / clear paths are the exception: they mint a brand-new HLC
//! inside the apply transaction (the "merge_version" guaranteed greater
//! than every participant) via direct `Hlc::new(...)` — never through
//! `hlc_state.generate()`. The caller's `HlcState` therefore has no
//! record of having emitted that HLC, and a subsequent local edit on
//! the merge winner can produce a version that lex-orders BELOW the
//! freshly-stamped child rows. Peers then reject the post-merge edit
//! envelope as LWW-stale.
//!
//! # The contract
//!
//! Production callers (Tauri app, MCP server, CLI) install an observer
//! at startup via [`set_local_event_observer`]. Each merge / clear site,
//! after constructing the new HLC, calls [`observe_local_event`]. The
//! observer routes the call to the caller's HlcState as a *local* event
//! — same machinery as `update_on_receive` (advance physical_ms /
//! counter past the supplied HLC) but the device suffix is unchanged,
//! since this device IS the author.
//!
//! Without an installed observer, [`observe_local_event`] is a no-op so
//! unit-test setups (and any caller that doesn't yet wire this in) keep
//! working unchanged. Tests that need to verify the observation use
//! [`with_temporary_observer`] to swap in a capture closure for the
//! duration of one test.
//!
//! Lives in `lorvex-domain` rather than `lorvex-sync` because the
//! lower-layer lifecycle ops in `lorvex-store` (notably the
//! `cancel_series` HLC mint in `lorvex_workflow::lifecycle::cancel`) also
//! need to feed their fresh HLC back into the process-wide clock, and
//! `lorvex-store` cannot depend on `lorvex-sync` (which sits above it).
//! `lorvex-sync::hlc` re-exports the same surface so call sites in
//! `lorvex-sync` can continue importing `lorvex_sync::hlc::*`.
//!
//! # Why the test observer is thread-local
//!
//! The test observer slot is `thread_local!`, not a process-global
//! `Mutex<Option<...>>`.
//! meant that two parallel test threads calling
//! [`with_temporary_observer`] would race regardless of any outer
//! serialization mutex: thread B installing its observer between
//! thread A's helper return and thread A's post-helper assertion
//! would let A's `observe_local_event` fire B's observer instead of
//! the no-op A expected. Even with a serializing mutex around the
//! body() execution, post-helper observations ran outside the lock
//! and could see another thread's installed observer.
//!
//! Thread-local storage eliminates the race structurally: each test
//! thread sees only its own observer state, and parallel tests in
//! `cargo test`'s default thread pool no longer contend for the
//! same slot. Production paths (which call `observe_local_event`
//! from sync apply transactions on the writer thread) hit the
//! global `OBSERVER` `OnceLock` exactly as before.

use crate::hlc::Hlc;
use std::cell::RefCell;
use std::sync::OnceLock;

/// Type alias for the registered observer. Boxed to keep the static
/// container object-safe across the `Fn` types each surface installs.
type LocalEventObserver = Box<dyn Fn(&Hlc) + Send + Sync + 'static>;

/// Process-wide observer slot for production callers. `OnceLock` so
/// the production wiring is a single initialization at startup.
static OBSERVER: OnceLock<LocalEventObserver> = OnceLock::new();

thread_local! {
    /// Per-thread test observer slot. Set/cleared by
    /// [`with_temporary_observer`]; consulted before [`OBSERVER`] by
    /// [`observe_local_event`]. Thread-local rather than process-
    /// global so parallel test threads don't see each other's
    /// installed observers — see the module-level docs for the race
    /// this avoids.
    ///
    /// `RefCell` (rather than `Cell`) because the observer closure
    /// is `Box<dyn Fn>` and we need to borrow it mutably during the
    /// `replace` / `take` swap. `RefCell` is `!Sync` but `thread_local!`
    /// implies single-thread access, so the constraint is satisfied.
    ///
    /// NOT gated on `cfg(test)` because external test crates compile
    /// this lib without `cfg(test)` yet still need a route around the
    /// production OnceLock. Production binaries simply never touch
    /// this slot (they never call `with_temporary_observer`).
    static TEST_OBSERVER: RefCell<Option<LocalEventObserver>> = const { RefCell::new(None) };
}

/// Outcome of attempting to install the process-wide observer.
///
/// The observer slot is a `OnceLock`, so only the first install wins;
/// subsequent attempts surface here so callers (Tauri startup, MCP
/// startup, CLI startup) can detect double-init in development without
/// panicking.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SetObserverOutcome {
    /// First install — the observer is now active for the rest of the
    /// process lifetime.
    Installed,
    /// Slot was already filled by an earlier install; this call is a
    /// no-op. Production wiring is expected to call this exactly once
    /// per process.
    AlreadyInstalled,
}

/// Install the process-wide observer. The first install wins; any
/// subsequent install is a no-op that returns `AlreadyInstalled` so
/// double-init is observable in logs without panicking.
///
/// The observer must be cheap and never panic; it runs inside the
/// apply transaction.
pub fn set_local_event_observer<F>(observer: F) -> SetObserverOutcome
where
    F: Fn(&Hlc) + Send + Sync + 'static,
{
    match OBSERVER.set(Box::new(observer)) {
        Ok(()) => SetObserverOutcome::Installed,
        Err(_) => SetObserverOutcome::AlreadyInstalled,
    }
}

/// Test-only convenience: install a no-op production observer if
/// none is already installed.
///
/// The merge-site `debug_assert!`s in the apply pipeline fire on any
/// dev/test binary that mints a merge HLC without first installing a
/// production observer. Unit tests inside the lib crate are
/// `cfg(test)`-gated past the assert and route through the
/// thread-local `TEST_OBSERVER` slot, but external integration test
/// crates compile the lib WITHOUT `cfg(test)`, so without a wiring
/// step they would trip the assert. This helper gives integration
/// tests a single line of init at module start so production binaries
/// still fail loudly when their startup forgets the wire-up while
/// integration tests stay clean.
///
/// Idempotent: returns `AlreadyInstalled` on subsequent calls because
/// the underlying slot is a `OnceLock`. The no-op observer drops every
/// event; integration tests that care about the event trail should
/// install their own observer via [`set_local_event_observer`] FIRST
/// (the first install wins).
pub fn install_noop_observer_for_tests() -> SetObserverOutcome {
    set_local_event_observer(|_| {})
}

/// Whether the production observer slot has been filled.
///
/// Surfaced so dev-build `debug_assert!`s at the merge sites can fail
/// loudly when a binary forgets to call [`set_local_event_observer`]
/// at startup. The slot is a `OnceLock`, so a non-`None` reading
/// guarantees the observer is wired in for the rest of the process
/// lifetime — there is no path that clears it. Test binaries route
/// through the thread-local `TEST_OBSERVER` slot instead (the merge-
/// site assertions are `cfg(not(test))`-gated, so this helper is only
/// consulted from production / dev binaries).
pub fn production_observer_is_installed() -> bool {
    OBSERVER.get().is_some()
}

/// Notify the registered observer that a *local* HLC has just been
/// minted outside the normal `HlcState::generate` path (e.g. a merge
/// version, or a recurrence-clear HLC during cancel-series). Routes
/// to the thread-local test observer first when one is installed,
/// so tests can verify the merge sites fire without colliding with
/// the production `OnceLock`.
///
/// No-op when no observer is registered. Production binaries never
/// install into `TEST_OBSERVER`, so the test-slot check is a single
/// thread-local borrow returning an empty `Option` — cheap enough
/// to keep on the hot path.
pub fn observe_local_event(hlc: &Hlc) {
    let routed_to_test_observer = TEST_OBSERVER.with(|slot| {
        slot.borrow().as_ref().is_some_and(|observer| {
            observer(hlc);
            true
        })
    });
    if routed_to_test_observer {
        return;
    }
    if let Some(observer) = OBSERVER.get() {
        observer(hlc);
    }
}

/// Test-only helper: run `body` with `observer` temporarily installed,
/// restoring the previous test observer (if any) on drop. The guard
/// shape ensures the slot is cleared even if `body` panics, so
/// subsequent tests start with a clean observer state.
///
/// `observe_local_event` consults the thread-local test observer
/// slot before the production `OBSERVER`, so callers can use this
/// helper to override whatever production observer the binary has
/// lazily installed.
///
/// NOT gated on `cfg(test)` so external test binaries can install
/// their own observer for the duration of one test.
///
/// **Thread-local storage.** The slot is `thread_local!`, so each
/// test thread maintains its own observer chain. Parallel tests in
/// `cargo test`'s default thread pool no longer race for a shared
/// slot — see the module-level docs.
pub fn with_temporary_observer<F, G, R>(observer: F, body: G) -> R
where
    F: Fn(&Hlc) + Send + Sync + 'static,
    G: FnOnce() -> R,
{
    struct Guard {
        previous: Option<LocalEventObserver>,
    }
    impl Drop for Guard {
        fn drop(&mut self) {
            // Restore whatever observer (if any) was installed in
            // this thread's slot before we entered. `take()`
            // empties our `previous` field so we don't double-
            // restore in pathological re-entrant cases.
            let restored = self.previous.take();
            TEST_OBSERVER.with(|slot| {
                *slot.borrow_mut() = restored;
            });
        }
    }

    let previous = TEST_OBSERVER.with(|slot| slot.borrow_mut().replace(Box::new(observer)));
    let _guard = Guard { previous };
    body()
}

#[cfg(test)]
mod tests;
