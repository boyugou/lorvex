//! Backend-enforced lock state for biometric-protected memory commands.
//!
//! This module owns the single source of truth for memory-command
//! authorization: a process-wide [`MemoryLockState`] that flips to
//! `Unlocked { until }` when biometric auth succeeds and is consulted
//! by every memory mutation / query at the IPC entry. The TTL re-locks
//! automatically without needing a ticker.
//!
//! Renderer-only gating (e.g. hiding UI based on a `bool` returned by
//! [`crate::commands::app_services::authenticate_biometrics`]) would
//! be purely cosmetic: a buggy or compromised renderer — or any
//! process speaking to the WebView IPC channel — could call every
//! memory command without ever invoking biometric auth.
//!
//! Key invariants:
//! - The lock is per-process, not per-window. A user authenticating in
//!   one window unlocks every other window for the TTL window. This
//!   matches what the previous renderer-only gate implicitly did.
//! - `Locked` is the default at startup. The user must authenticate
//!   before any memory command (read or write) succeeds.
//! - The TTL is checked lazily on each `require_unlocked()` call. If
//!   `Instant::now() > unlocked_until`, the next call re-locks the
//!   state and returns an error — there is no background ticker.
//! - `lock()` is idempotent and clears any pending TTL.
//! - The mutex is poison-tolerant: a panic in some other thread that
//!   poisons the mutex does NOT permanently lock memory; the recovery
//!   path treats the recovered guard as if it carried the same state.

use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

/// Default unlock window after a successful biometric authentication.
///
/// 5 minutes is a balance between "the user shouldn't have to re-auth
/// every time they look at a memory entry" and "an unattended laptop
/// re-locks before someone walks up to it." Tunable here only — the
/// value isn't a user-facing preference because mixing TTL across
/// devices would weaken the floor.
const DEFAULT_UNLOCK_TTL: Duration = Duration::from_secs(5 * 60);

/// Internal state of the memory lock.
#[derive(Debug, Clone, Copy)]
enum State {
    Locked,
    Unlocked { until: Instant },
}

impl State {
    fn is_unlocked_now(self, now: Instant) -> bool {
        matches!(self, Self::Unlocked { until } if now < until)
    }
}

fn state_handle() -> &'static Mutex<State> {
    static HANDLE: OnceLock<Mutex<State>> = OnceLock::new();
    HANDLE.get_or_init(|| Mutex::new(State::Locked))
}

/// Recovered-on-poison guard accessor. A panic anywhere in the process
/// that poisons the mutex must not permanently lock the memory surface
/// (the user couldn't re-authenticate to recover). Take the inner
/// state verbatim and continue.
fn lock_state<'a>() -> std::sync::MutexGuard<'a, State> {
    match state_handle().lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    }
}

/// Mark the memory surface unlocked for [`DEFAULT_UNLOCK_TTL`] starting
/// now. Called from the biometrics command on a successful auth.
pub fn unlock_for_default_ttl() {
    unlock_for(DEFAULT_UNLOCK_TTL);
}

/// Mark the memory surface unlocked for `ttl` starting now. Exposed as a
/// separate entry primarily for tests; production paths should use
/// [`unlock_for_default_ttl`] to keep the policy in one place.
fn unlock_for(ttl: Duration) {
    let mut guard = lock_state();
    *guard = State::Unlocked {
        until: Instant::now() + ttl,
    };
}

/// Return the lock to its default `Locked` state. Idempotent. Currently
/// only exercised by tests in this module — kept around because the
/// "lazy re-lock on expiry" path also relies on the same primitive
/// and benefits from the explicit-revoke test coverage.
#[cfg(test)]
fn lock() {
    let mut guard = lock_state();
    *guard = State::Locked;
}

/// `true` if the current state is `Unlocked` with `Instant::now()` still
/// inside the TTL window. Re-locks lazily if the window has elapsed.
fn is_unlocked() -> bool {
    let now = Instant::now();
    let mut guard = lock_state();
    if guard.is_unlocked_now(now) {
        return true;
    }
    // Either Locked or expired — collapse expired-Unlocked back to
    // Locked so subsequent observers don't see the stale `until`.
    *guard = State::Locked;
    false
}

/// Guard for memory IPC commands. Returns the canonical
/// `"memory_locked"` error string when the surface is locked, which
/// callers can translate to a user-visible "please re-authenticate"
/// affordance. Production handlers convert via `.map_err(String::from)`
/// at the IPC boundary.
pub fn require_unlocked() -> Result<(), MemoryLocked> {
    if is_unlocked() {
        Ok(())
    } else {
        Err(MemoryLocked)
    }
}

/// Sentinel error returned by [`require_unlocked`] when the memory
/// surface is locked. Carries no payload — callers either translate to
/// a string at the IPC boundary or match on the sentinel for typed
/// flow control.
///
/// `#[must_use]` so a caller cannot accidentally
/// discard the locked sentinel and proceed to read or modify memory
/// entries. Every production handler either propagates the error via
/// `?` / `String::from` at the IPC boundary or matches on it
/// explicitly; a stray `let _ = require_unlocked();` would silently
/// bypass the biometric gate the user opted into.
#[must_use = "MemoryLocked sentinel must not be discarded — propagate via `?` \
              or convert to a typed error at the IPC boundary"]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MemoryLocked;

impl std::fmt::Display for MemoryLocked {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(
            "memory_locked: biometric authentication required before \
             reading or modifying memory entries",
        )
    }
}

impl std::error::Error for MemoryLocked {}

#[cfg(test)]
mod tests {
    use super::*;

    /// Each test must hold this guard for its whole body so the
    /// process-wide [`state_handle`] static cannot interleave with
    /// another test running in parallel under cargo's default
    /// `--test-threads`. The earlier version of this suite relied on
    /// `lock()` at the top of each test, but that left a window
    /// between `unlock_for(Duration::from_millis(1))` and the
    /// subsequent `is_unlocked()` check during which a concurrent
    /// `unlock_for_default_ttl_unlocks` test could flip the state to
    /// a long-TTL unlock — causing the TTL-expiry assertion to fail
    /// intermittently.
    static SERIAL: Mutex<()> = Mutex::new(());

    fn serial<R>(f: impl FnOnce() -> R) -> R {
        let guard = match SERIAL.lock() {
            Ok(g) => g,
            // A poisoned mutex still lets us proceed — the prior
            // test's panic already printed its failure.
            Err(p) => p.into_inner(),
        };
        // Reset to the default `Locked` state at the head of every
        // test so we exercise the documented startup behavior.
        lock();
        let result = f();
        drop(guard);
        result
    }

    #[test]
    fn defaults_to_locked() {
        serial(|| {
            assert!(!is_unlocked());
            assert_eq!(require_unlocked(), Err(MemoryLocked));
        });
    }

    #[test]
    fn unlock_for_default_ttl_unlocks() {
        serial(|| {
            unlock_for_default_ttl();
            assert!(is_unlocked());
            assert!(require_unlocked().is_ok());
        });
    }

    #[test]
    fn ttl_expiry_re_locks_lazily() {
        serial(|| {
            // Poll with exponential backoff up to a generous
            // ceiling so a slow wake on CPU-pinned CI runners
            // (scheduler quantum pushing wake-up past the
            // assertion) never produces a false negative. The test
            // asserts the property (lazy re-lock after TTL) without
            // pinning a specific timing budget — a fixed 1 ms TTL
            // with a 5 ms sleep would flake.
            unlock_for(Duration::from_millis(1));
            let deadline = std::time::Instant::now() + Duration::from_millis(500);
            let mut backoff = Duration::from_millis(2);
            while is_unlocked() && std::time::Instant::now() < deadline {
                std::thread::sleep(backoff);
                backoff = (backoff * 2).min(Duration::from_millis(64));
            }
            assert!(!is_unlocked(), "expired unlock must lazily re-lock");
            assert_eq!(require_unlocked(), Err(MemoryLocked));
        });
    }

    #[test]
    fn explicit_lock_revokes_pending_unlock() {
        serial(|| {
            unlock_for(Duration::from_secs(60));
            assert!(is_unlocked());
            lock();
            assert!(!is_unlocked());
            assert_eq!(require_unlocked(), Err(MemoryLocked));
        });
    }

    #[test]
    fn double_lock_is_idempotent() {
        serial(|| {
            lock();
            lock();
            assert!(!is_unlocked());
        });
    }

    #[test]
    fn double_unlock_extends_window() {
        serial(|| {
            // the previous 50/10/80ms timing race
            // had only 30ms of cushion for the second unlock to
            // shadow the first, which under sanitizer or coverage
            // instrumentation regularly missed. Use larger absolute
            // values so the second unlock has comfortably more than
            // a scheduler quantum of headroom; the property under
            // test (extension semantics) does not care about the
            // exact magnitudes.
            unlock_for(Duration::from_millis(150));
            std::thread::sleep(Duration::from_millis(30));
            unlock_for(Duration::from_secs(60));
            // Original 150ms window would have expired ~120ms from
            // now; the second unlock must overwrite it.
            std::thread::sleep(Duration::from_millis(250));
            assert!(is_unlocked(), "second unlock must extend the TTL window");
        });
    }
}
