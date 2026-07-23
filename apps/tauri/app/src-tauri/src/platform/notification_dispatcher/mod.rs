//! a tiny in-flight counter that wraps every
//! reminder-notification emit so the desktop quit-flush path can wait
//! for outstanding work to drain before calling `app_handle.exit(0)`.
//!
//! The platform notification stack has multiple stages:
//!
//!   1. Renderer schedules a reminder via `tauri-plugin-notification`.
//!   2. The plugin hands the request to the OS notification center
//!      (UN on macOS, Windows ToastNotificationManager on Windows,
//!      libnotify on Linux).
//!   3. On macOS, our `UNUserNotificationCenterDelegate` may emit a
//!      `lorvex://notification-action-error` event back into the
//!      renderer when an action callback fails.
//!
//! Stage (2) is opaque — the OS owns its own queue and we can't
//! drain it. Stages (1) and (3) live in our process and are tracked
//! through an in-flight counter so the quit thread can wait for them
//! to drain. A flat 1-second sleep at quit would let the budget
//! expire while a delegate-emitted event was still being persisted
//! under load (many reminders firing at quit + ε, slow disk on the
//! durable error log, sluggish IPC channel), dropping the
//! diagnostic and any associated follow-up.
//!
//! This module exposes:
//!
//!   * `track_emit(...)` — increments the counter, runs the closure,
//!     decrements unconditionally.
//!   * `wait_for_idle(timeout)` — busy-waits with a tight sleep until
//!     the counter reaches zero or the deadline expires.
//!
//! The dispatcher is process-global and lock-free (`AtomicUsize`); it
//! adds nothing measurable to the hot path of a normal emit.

use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::{Duration, Instant};

static IN_FLIGHT: AtomicUsize = AtomicUsize::new(0);

/// Run `body` while the in-flight counter is incremented. The counter
/// is decremented in a `Drop` guard so a panic inside the body cannot
/// leak the count and stall a future `wait_for_idle`.
pub(crate) fn track_emit<R>(body: impl FnOnce() -> R) -> R {
    struct Guard;
    impl Drop for Guard {
        fn drop(&mut self) {
            IN_FLIGHT.fetch_sub(1, Ordering::SeqCst);
        }
    }
    IN_FLIGHT.fetch_add(1, Ordering::SeqCst);
    let _guard = Guard;
    body()
}

/// Block the calling thread until the in-flight counter is zero or
/// `timeout` elapses. Returns `true` iff the counter reached zero
/// before the timeout. The poll interval is short (~5ms) because this
/// is only ever called from the quit-flush wait, which is itself
/// happening on a dedicated thread that the process is about to tear
/// down — the cost is irrelevant.
pub(crate) fn wait_for_idle(timeout: Duration) -> bool {
    let deadline = Instant::now() + timeout;
    loop {
        if IN_FLIGHT.load(Ordering::SeqCst) == 0 {
            return true;
        }
        if Instant::now() >= deadline {
            return false;
        }
        std::thread::sleep(Duration::from_millis(5));
    }
}

#[cfg(test)]
mod tests;
