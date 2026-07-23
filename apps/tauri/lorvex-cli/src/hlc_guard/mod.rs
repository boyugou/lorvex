//! Process-wide HLC state for the CLI.
//!
//! A CLI invocation can perform multiple writes within a single millisecond
//! (log_cli_changelog + create_task + reminder enqueue, etc.). Each needs a
//! strictly-increasing HLC so LWW comparisons at peers resolve ordering
//! correctly. The previous pattern of `HlcState::new(suffix).generate()` at
//! every call site rebuilt the counter from zero every time, so a burst of
//! N writes in the same ms produced N identical HLC strings — guaranteeing
//! peers would treat later writes as duplicates and drop them.
//!
//! A process-wide `SurfaceHlcRuntime` initializes on first use keyed
//! off the device id while still allowing tests to reset state between
//! isolated temp databases.

use lorvex_domain::hlc::HlcSurface;
use lorvex_domain::hlc_session::HlcStateHandle;
use lorvex_domain::hlc_state::HlcState;
use lorvex_runtime::{get_or_create_device_id, SurfaceHlcError, SurfaceHlcRuntime};
use rusqlite::Connection;

use crate::error::CliError;

// `SurfaceHlcRuntime` intentionally keeps resettable process-wide
// state. With OnceLock, the first CLI integration test that wrote
// baked the HLC suffix + counter high-water into every subsequent test
// in the same binary; per-test tempdbs with different device_ids
// silently picked up the old suffix. Mirrors the mcp-server pattern.
static HLC_RUNTIME: SurfaceHlcRuntime = SurfaceHlcRuntime::new();

fn cli_hlc_error(error: SurfaceHlcError<CliError>) -> CliError {
    match error {
        SurfaceHlcError::Seed(error) => error,
        SurfaceHlcError::InvalidSuffix(error) => {
            CliError::Internal(format!("HlcState::new rejected derived suffix: {error}"))
        }
        SurfaceHlcError::DifferentIdentity { .. } | SurfaceHlcError::NotInitialized => {
            CliError::Internal(error.to_string())
        }
    }
}

fn lock_initialized(
    conn: &Connection,
) -> Result<lorvex_runtime::SurfaceHlcGuard<'static>, CliError> {
    if let Ok(guard) = HLC_RUNTIME.lock_existing() {
        return Ok(guard);
    }
    let device_id = get_or_create_device_id(conn)?;
    let guard = HLC_RUNTIME
        .lock_initialized(device_id.clone(), HlcSurface::Cli, |state| {
            // Seed past the highest HLC this device has previously
            // persisted under **any** surface (+ #2188). A failed seed
            // is a hard correctness failure for the CLI process; a
            // subsequent write could otherwise silently lose LWW.
            lorvex_store::hlc_seed::seed_hlc_state_from_local_history(conn, &device_id, state)
                .map(|_| ())
                .map_err(|err| {
                    CliError::Internal(format!(
                        "failed to seed HLC from local history: {err} \
                         (writes would risk silent LWW loss; aborting)"
                    ))
                })
        })
        .map_err(cli_hlc_error)?;
    register_local_event_observer();
    Ok(guard)
}

/// Install the process-wide local-event observer that routes
/// `lorvex_sync::hlc::observe_local_event` calls into the CLI's
/// `HlcState`. Closes the merge_version → local clock loop opened by
/// when an apply transaction (e.g. `lorvex sync`,
/// or any CLI mutation that immediately drives an apply) merges a
/// duplicate tag or recurrence aggregate, it mints a brand-new HLC
/// strictly greater than every participant; this observer makes the
/// CLI's in-process clock advance past it so the next CLI write does
/// not regress.
///
/// All failure modes (uninit state — impossible here since we install
/// after `*guard = Some(fresh)`; poisoned mutex; nonexistent state on
/// a different code path) downgrade to a log line. The observer runs
/// inside the apply transaction and must not panic.
fn register_local_event_observer() {
    use lorvex_sync::hlc::{set_local_event_observer, SetObserverOutcome};
    match set_local_event_observer(|merge_hlc| {
        if !HLC_RUNTIME.observe_hlc_if_initialized(merge_hlc) {
            eprintln!(
                "[cli:hlc] merge_version observation skipped: HLC state not initialized \
                 (this should be impossible after lock_initialized — version {merge_hlc})"
            );
        }
    }) {
        // `Installed` is the happy path; `AlreadyInstalled` means an
        // earlier CLI invocation in this test binary, or a sibling
        // surface (Tauri / MCP) running in the same process, already
        // wired the observer. First-install wins, so silently accept
        // either outcome.
        SetObserverOutcome::Installed | SetObserverOutcome::AlreadyInstalled => {}
    }
}

/// Generate the next HLC version for this CLI process, initializing the
/// shared state on first call. Returns the HLC as a wire-format string.
pub(crate) fn next_hlc_version(conn: &Connection) -> Result<String, CliError> {
    let mut guard = lock_initialized(conn)?;
    Ok(guard.generate().to_string())
}

/// Owning guard that deref's to the initialized `HlcState`. Used by
/// long-running transactions in `commands::mutate` effects that enqueue many envelopes
/// under a single lock scope, guaranteeing they share the same counter
/// run.
pub(crate) struct SharedHlcGuard(lorvex_runtime::SurfaceHlcGuard<'static>);

impl std::ops::Deref for SharedHlcGuard {
    type Target = HlcState;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl std::ops::DerefMut for SharedHlcGuard {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.0
    }
}

/// Storage handle that backs an `HlcSession` on the CLI surface.
/// Holds the long-scoped guard so the session's stamps share a single
/// lock acquisition for the whole top-level mutation.
///
/// This is the canonical CLI-side adapter: every CLI mutation that
/// drives an `HlcSession` wraps its `&mut HlcState` here (typically
/// obtained from [`lock_shared`]) so stamps share one acquisition of
/// the storage mutex.
pub(crate) struct CliHlcStateHandle<'guard> {
    guard: std::cell::RefCell<&'guard mut HlcState>,
}

impl<'guard> CliHlcStateHandle<'guard> {
    /// Wrap a borrowed `&mut HlcState` so it can back an `HlcSession`.
    /// The guard typically comes from a [`lock_shared`] /
    /// [`lock_initialized`] call earlier in the same transaction.
    pub(crate) const fn new(state: &'guard mut HlcState) -> Self {
        Self {
            guard: std::cell::RefCell::new(state),
        }
    }
}

impl<'guard> HlcStateHandle for CliHlcStateHandle<'guard> {
    fn generate(&self) -> lorvex_domain::hlc::Hlc {
        let mut state = self.guard.borrow_mut();
        state.generate()
    }
}

/// Acquire a long-scoped guard around the shared HLC state. Prefer
/// this over repeated `next_hlc_version` calls when one transaction
/// performs many `enqueue_entity_upsert` calls and needs one lock held
/// across the whole body.
pub(crate) fn lock_shared(conn: &Connection) -> Result<SharedHlcGuard, CliError> {
    let guard = lock_initialized(conn)?;
    Ok(SharedHlcGuard(guard))
}

/// reset the process-wide HLC state so a subsequent test
/// (or a subsequent test case in the same binary) starts fresh. Must
/// be called at the start of any test that seeds its own device_id.
#[cfg(test)]
pub(crate) fn reset_hlc_state_for_tests() {
    HLC_RUNTIME.reset_for_tests();
}

/// serializes any test that mutates `HLC_RUNTIME` (via
/// [`reset_hlc_state_for_tests`] or by seeding a non-default device
/// id in its setup). The CLI test binary runs tests in parallel by
/// default; without this guard, two threads can interleave reset →
/// seed → reset → seed → first-thread's `next_hlc_version` reading
/// the second thread's device id. Hold the lock for the entire
/// reset-through-assert window.
#[cfg(test)]
pub(crate) fn hlc_test_mutex() -> &'static std::sync::Mutex<()> {
    use std::sync::{Mutex, OnceLock};
    static M: OnceLock<Mutex<()>> = OnceLock::new();
    M.get_or_init(|| Mutex::new(()))
}

#[cfg(test)]
mod tests;
