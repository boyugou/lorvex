//! Process-wide HLC state for the MCP write surface.
//!
//! Holds the shared [`SurfaceHlcRuntime`] every writer path serializes
//! through, the lazy first-init that seeds from local history and wires
//! the merge_version observer, and the [`HlcSession`] adapter used by
//! callers that mint multiple stamps in one mutation.

use lorvex_domain::hlc::HlcSurface;
use lorvex_domain::hlc_session::{HlcSession, HlcStateHandle};
use lorvex_domain::hlc_state::HlcState;
use lorvex_runtime::{SurfaceHlcError, SurfaceHlcRuntime};
use rusqlite::Connection;

use super::get_or_create_sync_device_id;
use crate::error::McpError;

// ─── HLC ─────────────────────────────────────────────────────────────────
//
// the previous per-thread `THREAD_HLC` was unsound under tokio's
// multi-thread runtime. Worker A and Worker B could both generate HLCs
// at the same wall-clock ms from independent lazy-initialized state.
// Whichever worker seeded later saw the earlier worker's already-written
// HLC (via the seed) and advanced past it, but the earlier worker's
// state was stale and on its NEXT generate() produced an HLC strictly
// less than a previously-persisted HLC from the same device. The
// apply-side LWW comparison then dropped the later-but-smaller envelope
// as stale.
//
// Mirror the Tauri app and CLI shape: a process-wide
// `SurfaceHlcRuntime` that all writer paths serialize through. Its
// reset helper lets cfg(test) genuinely un-initialize for tests that
// depend on first-init device-id lookup (e.g. authorizer-denial
// regression tests). In production it initializes once and stays set.

static HLC_RUNTIME: SurfaceHlcRuntime = SurfaceHlcRuntime::new();

#[cfg(test)]
pub(crate) fn reset_thread_hlc_for_tests() {
    HLC_RUNTIME.reset_for_tests();
}

/// Process-wide mutex that any test mutating `HLC_RUNTIME` (via
/// [`reset_thread_hlc_for_tests`] or by relying on lazy first-init
/// behaviour) MUST hold for its entire reset-through-assert window.
///
/// the MCP server test binary runs tests in parallel by default. Two
/// tests racing through `reset_thread_hlc_for_tests` → first-touch
/// `generate_hlc_version` (which lazily reads `sync_checkpoints.device_id`)
/// can interleave so that test A's reset is observed by test B's
/// `generate_hlc_version`, which then initializes `HLC_RUNTIME` from B's
/// connection — bypassing A's authorizer or seeding A with B's device
/// suffix. Closes
/// `generate_hlc_version_surfaces_sync_checkpoint_read_failures` flake
/// (issue #3015). Mirrors the CLI's `hlc_test_mutex()` shape.
#[cfg(test)]
pub(crate) fn hlc_test_mutex() -> &'static std::sync::Mutex<()> {
    use std::sync::{Mutex, OnceLock};
    static M: OnceLock<Mutex<()>> = OnceLock::new();
    M.get_or_init(|| Mutex::new(()))
}

/// Generate a fresh HLC version string, lazily initializing the
/// process-wide HLC state from the sync device ID if needed.
pub(crate) fn generate_hlc_version(conn: &Connection) -> Result<String, McpError> {
    let mut guard = lock_initialized(conn)?;
    Ok(guard.generate().to_string())
}

/// Storage handle backing an [`HlcSession`] on the MCP surface. The
/// caller holds the live `HlcState` mutable borrow inside a `RefCell`
/// so the session can reach it from `with_state` without re-locking
/// the process-wide mutex on every stamp.
struct McpHlcStateHandle<'guard> {
    guard: std::cell::RefCell<&'guard mut HlcState>,
}

impl<'guard> HlcStateHandle for McpHlcStateHandle<'guard> {
    fn generate(&self) -> lorvex_domain::hlc::Hlc {
        let mut state = self.guard.borrow_mut();
        state.generate()
    }
}

/// Build an [`HlcSession`] from the MCP server's HLC state and run
/// `f` against it. Per the #3378 contract this is the compatibility
/// shim used until #3369 plumbs a session through the orchestrator;
/// every stamp minted inside `f` shares one lock acquisition, which is
/// the per-mutation lock elimination #3378 targets.
///
/// Lazily initializes `HLC_RUNTIME` on first call (mirroring
/// [`generate_hlc_version`]).
pub(crate) fn with_hlc_session<F, T>(conn: &Connection, f: F) -> Result<T, McpError>
where
    F: FnOnce(&HlcSession<'_>) -> Result<T, McpError>,
{
    let mut guard = lock_initialized(conn)?;
    let handle = McpHlcStateHandle {
        guard: std::cell::RefCell::new(&mut *guard),
    };
    let session = HlcSession::new(&handle);
    f(&session)
}

fn lock_initialized(
    conn: &Connection,
) -> Result<lorvex_runtime::SurfaceHlcGuard<'static>, McpError> {
    if let Ok(guard) = HLC_RUNTIME.lock_existing() {
        return Ok(guard);
    }
    let device_id = get_or_create_sync_device_id(conn)?;
    let guard = HLC_RUNTIME
        .lock_initialized(device_id.clone(), HlcSurface::Mcp, |state| {
            // Seed past the highest HLC this device has previously
            // persisted under any surface (+ #2188). A fresh MCP-server
            // process starts its HLC counter lazily on first write; if a
            // prior MCP-server process, the Tauri app, or the CLI already
            // emitted a later HLC from this device, we must not regress
            // below it.
            if let Err(err) =
                lorvex_store::hlc_seed::seed_hlc_state_from_local_history(conn, &device_id, state)
            {
                let details = err.to_string();
                persist_hlc_seed_warning(conn, &details);
                tracing::warn!(
                    error = %lorvex_domain::diagnostics::redact_diagnostic_text(&details),
                    "MCP failed to seed HLC from local history"
                );
            }
            Ok::<(), McpError>(())
        })
        .map_err(mcp_hlc_error)?;
    register_local_event_observer();
    Ok(guard)
}

fn mcp_hlc_error(error: SurfaceHlcError<McpError>) -> McpError {
    match error {
        SurfaceHlcError::Seed(error) => error,
        SurfaceHlcError::InvalidSuffix(error) => {
            McpError::Internal(format!("HlcState::new rejected derived suffix: {error}"))
        }
        SurfaceHlcError::DifferentIdentity { .. } | SurfaceHlcError::NotInitialized => {
            McpError::Internal(error.to_string())
        }
    }
}

pub(super) fn persist_hlc_seed_warning(conn: &Connection, details: &str) {
    lorvex_store::error_log::append_error_log_best_effort(
        conn,
        "mcp.hlc.seed_local_history_failed",
        "MCP failed to seed HLC from local history",
        Some(details),
        Some("warn"),
    );
}

/// Install the process-wide local-event observer that routes
/// `lorvex_sync::hlc::observe_local_event` calls into the MCP server's
/// `HlcState`. Closes the merge_version → local clock loop opened by
/// the apply pipeline minting a brand-new HLC at tag and recurrence
/// merge sites; without this hook the in-process clock never advances
/// past it and a subsequent local edit can lex-order below the merge
/// children, getting silently dropped at peers under LWW.
///
/// All failure modes (uninit state, poisoned mutex) downgrade to a log
/// line; never panics, never propagates an error — the observer runs
/// inside the apply transaction.
fn register_local_event_observer() {
    use lorvex_sync::hlc::{set_local_event_observer, SetObserverOutcome};
    match set_local_event_observer(|merge_hlc| {
        if !HLC_RUNTIME.observe_hlc_if_initialized(merge_hlc) {
            tracing::error!(
                merge_hlc = %merge_hlc,
                "MCP merge-version observation skipped because HLC state was not initialized"
            );
        }
    }) {
        // `Installed` is the happy path; `AlreadyInstalled` means an
        // earlier first-init in this process (e.g. test harness
        // reset_thread_hlc_for_tests + a subsequent generate) already
        // wired the observer. The OnceLock contract is first-installer-
        // wins, so silently accept either outcome.
        SetObserverOutcome::Installed | SetObserverOutcome::AlreadyInstalled => {}
    }
}
