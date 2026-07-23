//! RAII guard semantics for `try_acquire_sync_owner_with_guard` and
//! the wall-clock variant: drop-runs-release, explicit-release-disarms,
//! contended-acquire-returns-none, panic-during-handler-still-releases,
//! and the FnOnce one-shot contract.

use super::support::*;

/// the RAII guard returned by
/// `try_acquire_sync_owner_with_guard` must invoke its release
/// closure when dropped, even if the caller never explicitly
/// releases. Captures the bug class where every transport
/// reimplemented its own `*LeaseGuard` and a panic between
/// acquire and guard install pinned the lease.
#[test]
fn guard_drop_invokes_release_closure() {
    use std::sync::{Arc, Mutex};

    let conn = test_conn();
    let release_calls: Arc<Mutex<Vec<(String, String)>>> = Arc::new(Mutex::new(Vec::new()));
    let release_calls_for_closure = Arc::clone(&release_calls);

    {
        let guard = try_acquire_sync_owner_with_guard(
            &conn,
            "sync_transport",
            "desktop_app",
            1_000,
            500,
            move |name, owner| {
                release_calls_for_closure
                    .lock()
                    .unwrap()
                    .push((name.to_string(), owner.to_string()));
            },
            noop_release_panic_hook(),
        )
        .expect("acquire with guard")
        .expect("guard returned for fresh lease");
        assert_eq!(guard.lease_name(), "sync_transport");
        assert_eq!(guard.owner_id(), "desktop_app");
        // Drop happens at end of block.
    }

    let calls = release_calls.lock().unwrap();
    assert_eq!(
        *calls,
        vec![("sync_transport".to_string(), "desktop_app".to_string())],
        "guard drop must invoke release exactly once"
    );
}

/// Explicit `release()` consumes the guard so its `Drop` no
/// longer fires the closure — must match the contract that
/// `release` is the canonical one-shot path.
#[test]
fn guard_explicit_release_disarms_drop() {
    use std::sync::{Arc, Mutex};

    let conn = test_conn();
    let calls: Arc<Mutex<usize>> = Arc::new(Mutex::new(0));
    let calls_for_closure = Arc::clone(&calls);

    let guard = try_acquire_sync_owner_with_guard(
        &conn,
        "filesystem_bridge",
        "desktop_app",
        1_000,
        500,
        move |_, _| {
            *calls_for_closure.lock().unwrap() += 1;
        },
        noop_release_panic_hook(),
    )
    .expect("acquire")
    .expect("guard returned");

    guard.release();

    // Out-of-scope drop must NOT increment again.
    assert_eq!(*calls.lock().unwrap(), 1, "release fires the closure once");
}

/// When the lease is already held by someone else, the guard
/// helper must return Ok(None) so the caller's `let Some(...)
/// else` branch fires the skip path.
#[test]
fn guard_returns_none_when_lease_held_by_other() {
    let conn = test_conn();
    try_acquire_sync_owner(&conn, "sync_transport", "rival", 1_000, 500).expect("seed rival");

    let result = try_acquire_sync_owner_with_guard(
        &conn,
        "sync_transport",
        "desktop_app",
        1_100,
        500,
        |_, _| panic!("release closure must not run when acquire failed"),
        noop_release_panic_hook(),
    )
    .expect("acquire");
    assert!(result.is_none());
}

/// the RAII guard must release
/// its lease even when the caller panics between acquire and a
/// graceful `release()`. Without this contract, every panic
/// inside a `with_lease(..)`-style block would orphan the lease
/// row until its TTL expires, and the next process would
/// false-positive a "rival owner active" skip.
///
/// The test acquires a guard inside `catch_unwind`, panics, and
/// confirms (a) the panic propagates faithfully and (b) the
/// release closure ran exactly once during unwinding.
#[test]
fn guard_drop_releases_lease_when_caller_panics() {
    use std::sync::{Arc, Mutex};

    let release_calls: Arc<Mutex<Vec<(String, String)>>> = Arc::new(Mutex::new(Vec::new()));
    let release_calls_for_closure = Arc::clone(&release_calls);

    let panic_payload = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let conn = test_conn();
        let _guard = try_acquire_sync_owner_with_guard(
            &conn,
            "sync_transport",
            "desktop_app",
            1_000,
            500,
            move |name, owner| {
                release_calls_for_closure
                    .lock()
                    .unwrap()
                    .push((name.to_string(), owner.to_string()));
            },
            noop_release_panic_hook(),
        )
        .expect("acquire with guard")
        .expect("guard returned for fresh lease");
        panic!("simulated handler panic between acquire and release");
    }));

    let payload = panic_payload.expect_err("panic must propagate to caller");
    let message = payload
        .downcast_ref::<&'static str>()
        .map(|s| (*s).to_string())
        .or_else(|| payload.downcast_ref::<String>().cloned())
        .unwrap_or_default();
    assert!(
        message.contains("simulated handler panic"),
        "panic payload should round-trip, got: {message}"
    );

    let calls = release_calls.lock().unwrap();
    assert_eq!(
        *calls,
        vec![("sync_transport".to_string(), "desktop_app".to_string())],
        "panic must still drop the guard, which must invoke release exactly once"
    );
}

/// the release closure runs at most once.
/// The type system enforces this (`FnOnce`), but pin the
/// observable behavior so a future refactor that replaces the
/// guard's internal `Option<Box<dyn FnOnce>>` with something
/// that allows multiple invocations gets caught.
#[test]
fn release_closure_runs_at_most_once_across_explicit_release_and_drop() {
    use std::sync::{Arc, Mutex};

    let conn = test_conn();
    let calls: Arc<Mutex<usize>> = Arc::new(Mutex::new(0));
    let calls_for_closure = Arc::clone(&calls);

    let guard = try_acquire_sync_owner_with_guard(
        &conn,
        "sync_transport",
        "app",
        1_000,
        500,
        move |_, _| {
            *calls_for_closure.lock().unwrap() += 1;
        },
        noop_release_panic_hook(),
    )
    .expect("acquire")
    .expect("guard");

    // Explicit release consumes the guard.
    guard.release();

    // The guard is gone; nothing can fire the closure a second time.
    assert_eq!(
        *calls.lock().unwrap(),
        1,
        "FnOnce contract: closure must run exactly once"
    );
}

/// the wall-clock-free guard helper acquires
/// using the runtime's internal clock and returns an RAII guard
/// whose Drop releases the lease. The release closure must fire
/// at scope exit just like the explicit-clock variant.
#[test]
fn try_acquire_sync_owner_with_guard_now_acquires_and_releases() {
    use std::sync::{Arc, Mutex};

    let conn = test_conn();
    let release_calls: Arc<Mutex<usize>> = Arc::new(Mutex::new(0));
    let release_calls_for_closure = Arc::clone(&release_calls);

    {
        let _guard = try_acquire_sync_owner_with_guard_now(
            &conn,
            "sync_transport",
            "desktop_app",
            500,
            move |_, _| {
                *release_calls_for_closure.lock().unwrap() += 1;
            },
            noop_release_panic_hook(),
        )
        .expect("acquire via wall clock")
        .expect("guard returned for fresh lease");
    }

    assert_eq!(
        *release_calls.lock().unwrap(),
        1,
        "guard drop must invoke release exactly once"
    );
}
