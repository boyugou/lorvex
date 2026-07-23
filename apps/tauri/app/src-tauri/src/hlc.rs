//! HLC (Hybrid Logical Clock) state management for the Tauri app.
//!
//! Holds a process-wide [`SurfaceHlcRuntime`] seeded at app startup
//! from the shared `sync_checkpoints.device_id`. Command handlers call
//! `generate_version_result()` to produce a strictly-monotonic HLC
//! string for each outgoing outbox envelope. Each surface is a separate
//! process, so the shared-state ceiling is per-process; global
//! monotonicity across the device comes from the common device id, the
//! surface-tagged suffix, and strict-greater LWW comparisons.

use lorvex_domain::hlc::{Hlc, HlcSurface};
use lorvex_domain::hlc_session::{HlcSession, HlcStateHandle};
#[cfg(test)]
use lorvex_domain::hlc_state::HlcState;
use lorvex_runtime::{get_or_create_device_id, SurfaceHlcError, SurfaceHlcRuntime};
use rusqlite::Connection;
use std::convert::Infallible;
#[cfg(test)]
use std::sync::Mutex;
use std::sync::OnceLock;
#[cfg(test)]
use std::time::{SystemTime, UNIX_EPOCH};

use crate::error::{AppError, AppResult};

static HLC_RUNTIME: SurfaceHlcRuntime = SurfaceHlcRuntime::new();
static DEVICE_ID: OnceLock<String> = OnceLock::new();

/// Initialize HLC state. Call once during app startup after the DB is ready.
pub fn init_hlc(conn: &Connection) -> AppResult<()> {
    let device_id = get_or_create_device_id(conn).map_err(AppError::from)?;
    HLC_RUNTIME
        .ensure_initialized(device_id.clone(), HlcSurface::App, |state| {
            // Seed past the highest HLC this device has previously
            // persisted under any surface so wall-clock drift between
            // runs can never regress our HLC history (+ #2188).
            // Failure to read is logged and ignored — the app still
            // boots, it just risks an HLC regression that the LWW
            // pipeline will catch on the receiving end.
            if let Err(err) =
                lorvex_store::hlc_seed::seed_hlc_state_from_local_history(conn, &device_id, state)
            {
                log_hlc_seed_failure(conn, err);
            }
            Ok::<(), AppError>(())
        })
        .map_err(app_hlc_error)?;
    let _ = DEVICE_ID.set(device_id);

    // wire the merge_version observer from the apply
    // pipeline (lorvex-sync) into this surface's HlcState. The merge
    // sites in apply::tag and apply::aggregate::recurrence mint a
    // brand-new HLC strictly greater than every participant; without
    // this hook the local clock never sees that mint and a subsequent
    // local edit can lex-order BELOW the merge children, losing LWW
    // at peers. AlreadyInstalled is graceful — under StrictMode dev
    // double-invoke or test harness re-init the slot is already wired.
    register_local_event_observer();

    Ok(())
}

/// Install the process-wide local-event observer that routes
/// `lorvex_sync::hlc::observe_local_event` calls into this surface's
/// `HlcState`. The observer is a `Fn(&Hlc)` so we can't propagate
/// errors out — every failure mode is a downgraded log so the apply
/// transaction never panics on a clock-observation glitch.
fn register_local_event_observer() {
    use lorvex_sync::hlc::{set_local_event_observer, SetObserverOutcome};
    match set_local_event_observer(|merge_hlc| {
        if !HLC_RUNTIME.observe_hlc_if_initialized(merge_hlc) {
            log_hlc_observer_state_unavailable(merge_hlc);
        }
    }) {
        SetObserverOutcome::Installed => {}
        SetObserverOutcome::AlreadyInstalled => {
            // Test harness or hot reload already wired this — no-op
            // intentionally. The first installer wins for the rest
            // of the process lifetime, which is the contract.
        }
    }
}

fn log_hlc_seed_failure(conn: &Connection, error: impl std::fmt::Display) {
    let _ = crate::commands::diagnostics::append_error_log_internal(
        conn,
        "hlc.seed.local_history_failure",
        "HLC local-history seed failed",
        Some(format!("error={error}")),
        Some("warn".to_string()),
    );
}

fn log_hlc_observer_state_unavailable(merge_hlc: &Hlc) {
    log_hlc_observer_state_unavailable_with_logger(merge_hlc, log_hlc_observer_issue_best_effort);
}

fn log_hlc_observer_state_unavailable_with_logger(
    merge_hlc: &Hlc,
    logger: impl FnOnce(&str, &str, String),
) {
    logger(
        "hlc.observer.state_unavailable",
        "HLC merge-version observation skipped because state is unavailable",
        format!("version={merge_hlc}"),
    );
}

fn log_hlc_malformed_remote_version(version: &str, error: impl std::fmt::Display) {
    log_hlc_malformed_remote_version_with_logger(
        version,
        error,
        log_hlc_observer_issue_best_effort,
    );
}

fn log_hlc_malformed_remote_version_with_logger(
    version: &str,
    error: impl std::fmt::Display,
    logger: impl FnOnce(&str, &str, String),
) {
    logger(
        "hlc.observer.malformed_remote_version",
        "HLC remote-version observation ignored malformed version",
        format!("version={version:?}; error={error}"),
    );
}

fn log_hlc_observer_issue_best_effort(source: &str, message: &str, details: String) {
    crate::commands::diagnostics::try_append_error_log_best_effort(
        source,
        message,
        Some(details),
        Some("warn".to_string()),
    );
}

fn app_hlc_error(error: SurfaceHlcError<AppError>) -> AppError {
    match error {
        SurfaceHlcError::Seed(error) => error,
        SurfaceHlcError::InvalidSuffix(error) => {
            AppError::Internal(format!("HlcState::new rejected derived suffix: {error}"))
        }
        SurfaceHlcError::DifferentIdentity {
            existing_device_id,
            requested_device_id,
            ..
        } => AppError::Internal(format!(
            "HLC already initialized for a different device_id (was '{existing_device_id}', now '{requested_device_id}')"
        )),
        SurfaceHlcError::NotInitialized => AppError::Internal("HLC not initialized".to_string()),
    }
}

fn app_hlc_infallible(error: &SurfaceHlcError<Infallible>) -> AppError {
    AppError::Internal(error.to_string())
}

pub fn device_id_result() -> AppResult<&'static str> {
    resolve_device_id(DEVICE_ID.get())
}

/// Generate a fresh HLC version string using the global HLC state.
///
/// Panics if HLC has not been initialized.
#[cfg(test)]
pub fn generate_version() -> String {
    generate_version_result().expect("HLC not initialized")
}

pub fn generate_version_result() -> AppResult<String> {
    HLC_RUNTIME
        .generate_version()
        .map_err(|error| app_hlc_infallible(&error))
}

/// Bump local HLC state past an observed remote HLC.
///
/// the sync apply pipeline must update the local clock on
/// every inbound envelope. Without this, `HlcState::generate()` can
/// produce an HLC strictly less than the largest remote HLC already
/// present in the local DB, which opens a window for stale local
/// writes to lose LWW against pre-existing remote rows even though
/// they were authored "after" the remote in wall-clock order.
///
/// Malformed version strings are logged and ignored — they belong to
/// the apply pipeline's own error-reporting path (malformed envelopes
/// are rejected with `InvalidVersion` before their `version` ever
/// reaches us). Uninitialized HLC state is likewise non-fatal: this
/// only runs on sync paths, which are guarded by `init_hlc` having
/// completed.
pub fn observe_remote_version(version: &str) {
    let _ = HLC_RUNTIME.observe_remote_version_str(version, |version, error| {
        log_hlc_malformed_remote_version(version, error);
    });
}

#[cfg(test)]
fn observe_remote_version_in_state(state: Option<&Mutex<HlcState>>, version: &str) {
    let Some(state) = state else { return };
    let parsed = match Hlc::parse(version) {
        Ok(h) => h,
        Err(err) => {
            log_hlc_malformed_remote_version(version, err);
            return;
        }
    };
    let wall_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    let mut guard = match state.lock() {
        Ok(g) => g,
        Err(poisoned) => {
            // Lock-poisoning means a prior HLC user panicked. Recover
            // the guard so sync doesn't permanently stall on HLC
            // observation — generate()'s own lock attempt will surface
            // the poisoning to the actual write path.
            poisoned.into_inner()
        }
    };
    guard.update_on_receive(&parsed, wall_ms);
}

/// Storage handle that backs an [`HlcSession`] on the Tauri surface.
/// Constructed only after `init_hlc` / `ensure_hlc_for_test` has
/// populated the shared runtime.
struct AppHlcStateHandle;

impl HlcStateHandle for AppHlcStateHandle {
    fn generate(&self) -> Hlc {
        HLC_RUNTIME
            .generate_hlc()
            .expect("AppHlcStateHandle constructed only after init_hlc / ensure_hlc_for_test")
    }
}

/// Build an [`HlcSession`] from the Tauri surface's HLC storage and run
/// `f` against it.
///
/// Contract: every top-level Tauri command that performs writes wraps
/// its repository calls in a single `with_hlc_session(|s| …)` closure
/// so all version stamps emitted inside one mutation come from the
/// same session. Reusing one session amortizes the HLC lock
/// acquisition across every row written by the mutation instead of
/// paying it per call.
pub fn with_hlc_session<F, T>(f: F) -> AppResult<T>
where
    F: FnOnce(&HlcSession<'_>) -> AppResult<T>,
{
    HLC_RUNTIME
        .device_id()
        .map_err(|error| app_hlc_infallible(&error))?;
    let handle = AppHlcStateHandle;
    let session = HlcSession::new(&handle);
    f(&session)
}

/// Try to get the device ID, returning `None` if HLC has not been initialized.
///
/// Use this in code paths (like outbox writes) that need to check whether
/// the HLC has been initialized.
pub fn try_device_id() -> Option<&'static str> {
    DEVICE_ID.get().map(std::string::String::as_str)
}

fn resolve_device_id(device_id: Option<&String>) -> AppResult<&str> {
    device_id
        .map(String::as_str)
        .ok_or_else(|| AppError::Internal("device ID not initialized".to_string()))
}

#[cfg(test)]
fn generate_version_from_state(state: Option<&Mutex<HlcState>>) -> AppResult<String> {
    let state = state.ok_or_else(|| AppError::Internal("HLC not initialized".to_string()))?;
    // Symmetry with `observe_remote_version_in_state`: recover from a
    // poisoned lock rather than rejecting. HLC monotonicity matters
    // more than poison-fail-fast — a panic in a prior HLC user
    // shouldn't permanently break LWW correctness on this device.
    // Internal HlcState invariants are restored every time generate()
    // is called (it ignores past wall-clock and re-stamps from the
    // current SystemTime).
    //
    // the poison-recovery is
    // load-bearing for the every-write hot path. The HLC mutex is
    // taken on every Tauri command that mutates an entity; if a single
    // panic in a sibling caller rendered the HLC permanently
    // unusable, every subsequent write would wedge on a poisoned
    // lock. The `HlcState::generate` contract re-derives all
    // monotonicity invariants from `SystemTime::now()` plus the
    // persisted suffix, so observing partial state from a panicking
    // prior caller cannot produce a non-monotonic version.
    let mut guard = state
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    Ok(guard.generate().to_string())
}

/// Ensure HLC is initialized for test environments.
///
/// Uses a test-only device ID and HLC state. Idempotent — safe to call
/// from multiple tests running in the same process.
#[cfg(test)]
pub fn ensure_hlc_for_test() {
    let _ = DEVICE_ID.set("test-device-00000000".to_string());
    let _ = HLC_RUNTIME.ensure_initialized(
        "test-device-00000000".to_string(),
        HlcSurface::App,
        |_state| Ok::<(), AppError>(()),
    );
    // keep the test path symmetric with `init_hlc` so
    // tests that exercise the merge_version observation contract
    // don't need a separate setup helper. First-install wins.
    register_local_event_observer();
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    #[test]
    fn resolve_device_id_rejects_uninitialized_state() {
        let error = resolve_device_id(None).expect_err("missing device id should fail");
        match error {
            AppError::Internal(message) => assert!(message.contains("device ID not initialized")),
            other => panic!("expected internal error, got {other:?}"),
        }
    }

    #[test]
    fn generate_version_from_state_rejects_uninitialized_state() {
        let error = generate_version_from_state(None).expect_err("missing HLC state should fail");
        match error {
            AppError::Internal(message) => assert!(message.contains("HLC not initialized")),
            other => panic!("expected internal error, got {other:?}"),
        }
    }

    #[test]
    fn generate_version_from_state_recovers_from_poisoned_lock() {
        // HLC monotonicity matters more than poison-fail-fast: if a
        // prior holder panicked, callers must still be able to emit
        // versions. Mirrors the recovery policy in
        // observe_remote_version_in_state.
        let state = Arc::new(Mutex::new(
            HlcState::new("deadbeefdeadbeef".to_string()).unwrap(),
        ));
        let state_for_thread = Arc::clone(&state);
        let _ = std::thread::spawn(move || {
            let _guard = state_for_thread.lock().expect("lock HLC state");
            panic!("poison HLC lock");
        })
        .join();

        let version = generate_version_from_state(Some(&state))
            .expect("poisoned HLC state should recover, not reject");
        assert!(!version.is_empty());
        assert!(version.contains('_'));
    }

    #[test]
    fn generate_version_from_state_returns_hlc_string() {
        let state = Mutex::new(HlcState::new("deadbeefdeadbeef".to_string()).unwrap());
        let version =
            generate_version_from_state(Some(&state)).expect("initialized HLC state should work");
        assert!(!version.is_empty());
        assert!(version.contains('_'));
    }

    #[test]
    fn observe_remote_version_bumps_state_past_remote() {
        // after observing a remote HLC far ahead of local
        // wall clock, the next generated HLC must strictly exceed it.
        let state = Mutex::new(HlcState::new("10ca100100000001".to_string()).unwrap());
        let remote_version = "9999999999999_0050_de0070e100000001";
        observe_remote_version_in_state(Some(&state), remote_version);

        let next = generate_version_from_state(Some(&state)).expect("generate after observation");
        let next_hlc = lorvex_domain::hlc::Hlc::parse(&next).expect("parse generated");
        let remote_hlc = lorvex_domain::hlc::Hlc::parse(remote_version).expect("parse remote");
        assert!(
            next_hlc > remote_hlc,
            "local HLC {next} must exceed observed remote {remote_version}"
        );
    }

    #[test]
    fn observe_remote_version_ignores_malformed_string() {
        // Malformed versions must not poison the state.
        let state = Mutex::new(HlcState::new("10ca100100000001".to_string()).unwrap());
        observe_remote_version_in_state(Some(&state), "not-a-valid-hlc");
        observe_remote_version_in_state(Some(&state), "");
        let guard = state.lock().expect("lock state");
        assert_eq!(guard.last_physical_ms(), 0);
        assert_eq!(guard.counter(), 0);
    }

    #[test]
    fn observe_remote_version_without_init_is_noop() {
        observe_remote_version_in_state(None, "1000000000000_0000_72656d6f74653031");
    }

    #[test]
    fn observer_advances_global_state_past_observed_merge_version() {
        // after the global HLC state has been initialized
        // (whether via `init_hlc` or `ensure_hlc_for_test`, both of
        // which call `register_local_event_observer`), an
        // `observe_local_event` call from the apply pipeline must
        // advance the in-process state past the observed HLC. The
        // next `generate_version_result` therefore returns a string
        // strictly greater than the observed merge_version.
        ensure_hlc_for_test();

        // Far-future HLC the local clock cannot otherwise reach, so
        // the assertion is robust to any prior test in this binary
        // having already advanced the shared HLC runtime.
        let merge_hlc = lorvex_domain::hlc::Hlc::new(9_999_999_999_990, 0, "ffffffffffffffff")
            .expect("canonical 16-hex suffix");
        lorvex_sync::hlc::observe_local_event(&merge_hlc);

        let after = generate_version_result().expect("generate after observation");
        let after_hlc = lorvex_domain::hlc::Hlc::parse(&after).expect("generated HLC parses");
        assert!(
            after_hlc > merge_hlc,
            "post-observation generate {after} must exceed merge_version {merge_hlc}"
        );
    }

    #[test]
    fn observer_install_is_idempotent_across_repeat_inits() {
        // The OnceLock-backed observer slot returns AlreadyInstalled
        // on every call after the first. Calling `ensure_hlc_for_test`
        // multiple times (which registers the observer each time) must
        // therefore not panic — exercises the AlreadyInstalled branch
        // of `register_local_event_observer`.
        ensure_hlc_for_test();
        ensure_hlc_for_test();
        ensure_hlc_for_test();
        // Sanity: state is still functional after the repeated installs.
        let v = generate_version_result().expect("generate after repeat installs");
        assert!(!v.is_empty());
    }

    #[test]
    fn runtime_device_id_helper_persists_identity() {
        let conn = Connection::open_in_memory().expect("open in-memory db");
        conn.execute(
            "CREATE TABLE sync_checkpoints (key TEXT PRIMARY KEY, value TEXT NOT NULL) STRICT",
            [],
        )
        .expect("create sync checkpoints");

        let first = get_or_create_device_id(&conn).expect("create device id");
        let second = get_or_create_device_id(&conn).expect("reuse device id");

        assert_eq!(first, second);
        // HLC device suffix widened from 8 to 16 hex
        // chars (32 → 64 bits) so cross-device birthday collisions
        // remain vanishingly rare at realistic install scales.
        assert_eq!(
            lorvex_runtime::device_id_to_hlc_suffix(&first, HlcSurface::App).len(),
            16
        );
    }

    #[test]
    fn log_hlc_seed_failure_persists_structured_diagnostic() {
        let conn = crate::test_support::test_conn();

        log_hlc_seed_failure(&conn, "seed failed: fixture");

        let row: (String, String, String, String) = conn
            .query_row(
                "SELECT source, level, message, details
                 FROM error_logs
                 WHERE source = 'hlc.seed.local_history_failure'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .expect("read HLC seed diagnostic");

        assert_eq!(row.0, "hlc.seed.local_history_failure");
        assert_eq!(row.1, "warn");
        assert_eq!(row.2, "HLC local-history seed failed");
        assert!(row.3.contains("seed failed: fixture"));
    }

    #[test]
    fn hlc_observer_issue_persists_structured_diagnostic_with_redaction() {
        let conn = crate::test_support::test_conn();

        log_hlc_malformed_remote_version_with_logger(
            "Authorization: Bearer eyJhbGciOi.deadbeef.xyz",
            "parse failed",
            |source, message, details| {
                let _ = crate::commands::diagnostics::append_error_log_internal(
                    &conn,
                    source,
                    message,
                    Some(details),
                    Some("warn".to_string()),
                );
            },
        );

        let row: (String, String, String, String) = conn
            .query_row(
                "SELECT source, level, message, details
                 FROM error_logs
                 WHERE source = 'hlc.observer.malformed_remote_version'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .expect("read HLC observer diagnostic");

        assert_eq!(row.0, "hlc.observer.malformed_remote_version");
        assert_eq!(row.1, "warn");
        assert_eq!(
            row.2,
            "HLC remote-version observation ignored malformed version"
        );
        assert!(row.3.contains("version="));
        assert!(row.3.contains("error=parse failed"));
        assert!(!row.3.contains("eyJhbGciOi.deadbeef.xyz"));
        assert!(row.3.contains("[REDACTED]"));
    }

    #[test]
    fn hlc_observer_state_unavailable_source_is_persisted() {
        let conn = crate::test_support::test_conn();
        let merge_hlc =
            Hlc::parse("1234567890000_0000_deadbeefdeadbeef").expect("fixture HLC must parse");

        log_hlc_observer_state_unavailable_with_logger(&merge_hlc, |source, message, details| {
            let _ = crate::commands::diagnostics::append_error_log_internal(
                &conn,
                source,
                message,
                Some(details),
                Some("warn".to_string()),
            );
        });

        let row: (String, String, String, String) = conn
            .query_row(
                "SELECT source, level, message, details
                 FROM error_logs
                 WHERE source = 'hlc.observer.state_unavailable'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .expect("read HLC observer state diagnostic");

        assert_eq!(row.0, "hlc.observer.state_unavailable");
        assert_eq!(row.1, "warn");
        assert_eq!(
            row.2,
            "HLC merge-version observation skipped because state is unavailable"
        );
        assert_eq!(row.3, "version=1234567890000_0000_deadbeefdeadbeef");
    }
}
