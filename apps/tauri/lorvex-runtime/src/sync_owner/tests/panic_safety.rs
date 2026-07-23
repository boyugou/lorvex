//! Panic safety in `Drop` and explicit `release()`. The release
//! closure and the `ReleasePanicHook` are both swallowed inside
//! `catch_unwind` so a misbehaving transport cannot crash the
//! process during unwind, and the hook receives the lease/owner/
//! message tuple verbatim.

use super::support::*;

/// a release closure that panics during `Drop`
/// must not propagate — propagating from `Drop` while the stack
/// is already unwinding from another panic would trigger the
/// double-panic rule and abort the process. This test fires a
/// panicking release closure during normal scope exit (single
/// panic) and confirms the program stays alive.
#[test]
fn drop_swallows_panic_in_release_closure() {
    let conn = test_conn();
    // Scope so the guard drops while we still have the conn.
    {
        let _guard = try_acquire_sync_owner_with_guard(
            &conn,
            "sync_transport",
            "desktop_app",
            1_000,
            500,
            |_, _| panic!("simulated transport panic in release closure"),
            noop_release_panic_hook(),
        )
        .expect("acquire")
        .expect("guard returned");
        // _guard drops here. Without the catch_unwind in Drop,
        // this would unwind out of the block and the test
        // process would abort if any sibling drop also panicked.
    }
    // If the panic propagated, this point would never be
    // reached — control would have unwound out of the test.
    // Reaching here at all is the assertion.
}

/// Companion to `drop_swallows_panic_in_release_closure`: the
/// double-panic case. The caller is already unwinding from its
/// own panic when the guard's `Drop` fires; if the release
/// closure also panics and the drop doesn't catch it, the
/// process aborts. We use `catch_unwind` to recover the outer
/// panic and assert the test process survived.
#[test]
fn drop_during_unwind_does_not_double_panic() {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let conn = test_conn();
        let _guard = try_acquire_sync_owner_with_guard(
            &conn,
            "sync_transport",
            "desktop_app",
            1_000,
            500,
            |_, _| panic!("release closure panics during outer unwind"),
            noop_release_panic_hook(),
        )
        .expect("acquire")
        .expect("guard returned");
        panic!("outer panic — drop fires while we are already unwinding");
    }));
    // `catch_unwind` returns `Err` with the *outer* panic payload.
    // If the inner Drop panic had escaped, the process would have
    // aborted instead of returning Err here.
    let payload = result.expect_err("outer panic must surface");
    let message = payload
        .downcast_ref::<&'static str>()
        .map(|s| (*s).to_string())
        .or_else(|| payload.downcast_ref::<String>().cloned())
        .unwrap_or_default();
    assert!(
        message.contains("outer panic"),
        "the surfaced panic must be the original outer one, got: {message}"
    );
}

/// A panicking release closure must route the panic message through
/// the required `on_release_panic` hook. This matters in production
/// where process stderr may be redirected away from operator
/// visibility, so the hook is the only signal an orphan-lease alert
/// can use to reach the structured-log sink.
#[test]
fn release_panic_hook_receives_lease_owner_and_message() {
    use std::sync::{Arc, Mutex};
    let captures: Arc<Mutex<Vec<(String, String, String)>>> = Arc::new(Mutex::new(Vec::new()));
    let captures_for_hook = Arc::clone(&captures);
    let hook: ReleasePanicHook = Arc::new(move |lease_name, owner_id, message| {
        captures_for_hook.lock().unwrap().push((
            lease_name.to_string(),
            owner_id.to_string(),
            message.to_string(),
        ));
    });
    let conn = test_conn();
    {
        let _guard = try_acquire_sync_owner_with_guard(
            &conn,
            "sync_transport",
            "desktop_app",
            1_000,
            500,
            |_, _| panic!("simulated transport panic — captured by hook"),
            hook,
        )
        .expect("acquire")
        .expect("guard returned");
        // _guard drops here, panicking release closure routes
        // through the hook, hook records the entry, no eprintln.
    }

    let recorded = captures.lock().unwrap();
    assert_eq!(recorded.len(), 1, "hook fired exactly once");
    assert_eq!(recorded[0].0, "sync_transport");
    assert_eq!(recorded[0].1, "desktop_app");
    assert!(
        recorded[0].2.contains("simulated transport panic"),
        "hook received panic message verbatim: {:?}",
        recorded[0].2
    );
}

#[test]
fn drop_swallows_panic_in_release_panic_hook() {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let conn = test_conn();
        let hook: ReleasePanicHook = std::sync::Arc::new(|_, _, _| {
            panic!("release panic hook failed");
        });
        let _guard = try_acquire_sync_owner_with_guard(
            &conn,
            "sync_transport",
            "desktop_app",
            1_000,
            500,
            |_, _| panic!("simulated release-time panic"),
            hook,
        )
        .expect("acquire")
        .expect("guard returned");
    }));

    assert!(
        result.is_ok(),
        "Drop must swallow both release closure and release panic hook panics"
    );
}

/// Explicit `release()` must mirror the same panic-safety
/// contract. A caller who reaches for `release()` instead of
/// letting the guard fall out of scope expects identical
/// observable behaviour.
#[test]
fn explicit_release_swallows_panic_in_closure() {
    let conn = test_conn();
    let guard = try_acquire_sync_owner_with_guard(
        &conn,
        "sync_transport",
        "desktop_app",
        1_000,
        500,
        |_, _| panic!("simulated release-time panic"),
        noop_release_panic_hook(),
    )
    .expect("acquire")
    .expect("guard returned");
    // Should not propagate — symmetry with the Drop path.
    guard.release();
}

#[test]
fn explicit_release_swallows_panic_in_release_panic_hook() {
    let conn = test_conn();
    let hook: ReleasePanicHook = std::sync::Arc::new(|_, _, _| {
        panic!("release panic hook failed");
    });
    let guard = try_acquire_sync_owner_with_guard(
        &conn,
        "sync_transport",
        "desktop_app",
        1_000,
        500,
        |_, _| panic!("simulated release-time panic"),
        hook,
    )
    .expect("acquire")
    .expect("guard returned");

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        guard.release();
    }));

    assert!(
        result.is_ok(),
        "explicit release must swallow both release closure and release panic hook panics"
    );
}
