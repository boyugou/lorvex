//! filesystem-bridge lease heartbeat.
//!
//! The fs-bridge sync owner lease has a 30 s TTL. The orchestrator in
//! [`super::runtime`] already calls `renew_sync_owner_now` between the
//! coarse phase boundaries (Phase A read → B push → C record → D pull →
//! E apply), but the push and pull *I/O loops themselves* can outlast a
//! single TTL window on a slow shared folder (USB stick, throttled
//! network share with packet loss). When a single phase
//! exceeds 30 s, the sibling-device steal predicate in
//! [`lorvex_runtime::sync_owner::try_acquire_sync_owner`] flips and a
//! peer can lift the lease while we still believe we hold it.
//!
//! This module provides a thread-local heartbeat that the per-iteration
//! work loops in [`super::runtime`] and [`super::collection`] tick once
//! per file. The first tick after the configured threshold (~10 s,
//! one-third of the 30 s TTL) opens a short-lived DB connection and
//! issues `renew_sync_owner_now`. If the lease has been lost or has
//! already expired, the tick returns an error so the calling loop can
//! abort cleanly instead of finishing work under a stale lease and then
//! racing the rightful new owner at flush time.
//!
//! The thread-local design lets us thread the heartbeat through
//! pre-existing function signatures (`phase_push_to_filesystem`,
//! `collect_remote_filesystem_bridge_envelopes`) without churn — tests
//! that invoke those functions directly never install the guard, so
//! `tick()` is a cheap no-op for them. The guard is RAII-scoped to the
//! lease-holding section so a panic during sync I/O cannot leak a
//! hot-armed heartbeat into a later, lease-less invocation on the same
//! thread (Tauri's command dispatcher reuses worker threads).

use std::cell::RefCell;
use std::time::{Duration, Instant};

#[cfg(test)]
use crate::error::AppError;
use crate::error::AppResult;

/// Default cadence for in-loop renewals — well under the 30 s TTL so a
/// single late tick still leaves comfortable margin before expiry.
pub(super) const DEFAULT_HEARTBEAT_INTERVAL: Duration = Duration::from_secs(10);

thread_local! {
    static LEASE_HEARTBEAT: RefCell<Option<HeartbeatState>> = const { RefCell::new(None) };
}

struct HeartbeatState {
    /// When the next tick is allowed to perform a renewal. Until this
    /// instant elapses, [`tick`] is a no-op.
    next_due_at: Instant,
    interval: Duration,
    /// Boxed renewer — production wires this to
    /// [`super::runtime::renew_filesystem_bridge_lease_or_abort`]; tests
    /// that exercise the heartbeat itself can install a deterministic
    /// closure that bumps a counter.
    renew: Box<dyn FnMut() -> AppResult<()>>,
}

/// RAII guard that installs a heartbeat for the current thread and
/// clears it on drop. Construct immediately after acquiring the
/// fs-bridge lease and before entering any phase whose I/O loop should
/// honor in-loop renewals.
pub(super) struct HeartbeatGuard {
    /// Marker so the guard is `!Send` (heartbeat lives in a
    /// thread-local and must not leak to another thread).
    _marker: std::marker::PhantomData<*const ()>,
}

impl HeartbeatGuard {
    pub(super) fn install<F>(interval: Duration, renew: F) -> Self
    where
        F: FnMut() -> AppResult<()> + 'static,
    {
        LEASE_HEARTBEAT.with(|cell| {
            let mut slot = cell.borrow_mut();
            // refuse to silently overwrite a previously
            // installed heartbeat — a re-entrant install would leave the
            // outer scope's drop clearing the inner scope's heartbeat
            // and the inner scope running with no renewals at all.
            assert!(
                slot.is_none(),
                "lease_heartbeat: nested HeartbeatGuard::install on the same thread is not supported",
            );
            *slot = Some(HeartbeatState {
                next_due_at: Instant::now() + interval,
                interval,
                renew: Box::new(renew),
            });
        });
        Self {
            _marker: std::marker::PhantomData,
        }
    }
}

impl Drop for HeartbeatGuard {
    fn drop(&mut self) {
        LEASE_HEARTBEAT.with(|cell| {
            *cell.borrow_mut() = None;
        });
    }
}

/// Per-iteration tick. Cheap when a heartbeat is not installed (tests)
/// or when the interval has not yet elapsed. When the interval has
/// elapsed the tick invokes the installed renewer; on success the
/// next-due timestamp is advanced from `now` so a long renewal does not
/// immediately re-fire on the next call. On renewal failure the error
/// is propagated and the heartbeat slot is cleared so subsequent ticks
/// do not retry against an already-lost lease.
pub(super) fn tick() -> AppResult<()> {
    let action = LEASE_HEARTBEAT.with(|cell| -> Option<AppResult<()>> {
        let mut slot = cell.borrow_mut();
        let state = slot.as_mut()?;
        if Instant::now() < state.next_due_at {
            return Some(Ok(()));
        }
        let result = (state.renew)();
        match &result {
            Ok(()) => {
                state.next_due_at = Instant::now() + state.interval;
            }
            Err(_) => {
                // Drop the heartbeat so a later tick on the same thread
                // doesn't keep retrying a lease the runtime crate has
                // already told us is dead.
                *slot = None;
            }
        }
        Some(result)
    });
    action.unwrap_or(Ok(()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    #[test]
    fn tick_is_noop_when_no_guard_installed() {
        // Different thread to guarantee no leftover state from other tests.
        std::thread::spawn(|| {
            for _ in 0..1_000 {
                tick().expect("tick without guard must be a no-op");
            }
        })
        .join()
        .unwrap();
    }

    #[test]
    fn tick_renews_after_interval_elapses() {
        std::thread::spawn(|| {
            let counter = Arc::new(AtomicUsize::new(0));
            let counter_clone = counter.clone();
            let _guard = HeartbeatGuard::install(Duration::from_millis(20), move || {
                counter_clone.fetch_add(1, Ordering::SeqCst);
                Ok(())
            });

            // Immediately ticking should not renew — interval not elapsed.
            tick().expect("tick must succeed");
            assert_eq!(counter.load(Ordering::SeqCst), 0);

            // bumped from 30ms to 60ms so the wait
            // is solidly above the typical scheduler quantum and CI
            // jitter window. The interval gate the test arms is 20ms
            // (`HeartbeatGuard::install(Duration::from_millis(20), …)`)
            // — 60ms is comfortably 3× that and removes a known flake
            // class without slowing the suite meaningfully.
            std::thread::sleep(Duration::from_millis(60));
            tick().expect("tick after interval must succeed");
            assert_eq!(counter.load(Ordering::SeqCst), 1);

            // Without sleeping again the next tick must NOT renew.
            tick().expect("tick must succeed");
            assert_eq!(counter.load(Ordering::SeqCst), 1);

            // bumped from 30ms to 60ms so the wait
            // is solidly above the typical scheduler quantum and CI
            // jitter window. The interval gate the test arms is 20ms
            // (`HeartbeatGuard::install(Duration::from_millis(20), …)`)
            // — 60ms is comfortably 3× that and removes a known flake
            // class without slowing the suite meaningfully.
            std::thread::sleep(Duration::from_millis(60));
            tick().expect("tick after second interval must succeed");
            assert_eq!(counter.load(Ordering::SeqCst), 2);
        })
        .join()
        .unwrap();
    }

    #[test]
    fn tick_propagates_renewal_failure_and_disarms_heartbeat() {
        std::thread::spawn(|| {
            let counter = Arc::new(AtomicUsize::new(0));
            let counter_clone = counter.clone();
            let _guard = HeartbeatGuard::install(Duration::from_millis(0), move || {
                counter_clone.fetch_add(1, Ordering::SeqCst);
                Err(AppError::Internal("lease lost".to_string()))
            });

            // First tick must surface the error from the renewer.
            let err = tick().expect_err("first tick must propagate renewal failure");
            assert!(err.to_string().contains("lease lost"));
            assert_eq!(counter.load(Ordering::SeqCst), 1);

            // After failure the heartbeat is disarmed — subsequent ticks
            // must not re-call the renewer.
            for _ in 0..5 {
                tick().expect("post-failure ticks must be no-op");
            }
            assert_eq!(counter.load(Ordering::SeqCst), 1);
        })
        .join()
        .unwrap();
    }

    #[test]
    #[should_panic(expected = "nested HeartbeatGuard::install")]
    fn nested_install_panics() {
        // Same thread on purpose — the assertion guards against
        // accidental nesting on a single worker thread.
        let _outer = HeartbeatGuard::install(Duration::from_secs(1), || Ok(()));
        let _inner = HeartbeatGuard::install(Duration::from_secs(1), || Ok(()));
    }

    #[test]
    fn drop_clears_heartbeat_so_next_install_succeeds() {
        std::thread::spawn(|| {
            {
                let _g = HeartbeatGuard::install(Duration::from_secs(1), || Ok(()));
            }
            // After scope exit a fresh install must work.
            let _g = HeartbeatGuard::install(Duration::from_secs(1), || Ok(()));
        })
        .join()
        .unwrap();
    }
}
