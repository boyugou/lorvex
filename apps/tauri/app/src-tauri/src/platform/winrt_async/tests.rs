use super::*;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

#[test]
fn run_winrt_with_timeout_returns_ok_on_fast_completion() {
    let value = run_winrt_with_timeout(
        "test_fast",
        Duration::from_secs(5),
        || Ok::<_, windows_core::Error>(42i32),
        || {},
    )
    .expect("fast path should succeed");
    assert_eq!(value, 42);
}

#[test]
fn run_winrt_with_timeout_surfaces_get_failure_as_internal() {
    let err = run_winrt_with_timeout(
        "test_fail",
        Duration::from_secs(5),
        || Err::<i32, _>(windows_core::Error::from_hresult(windows_core::HRESULT(-1))),
        || {},
    )
    .expect_err("WinRT error should propagate");
    let msg = format!("{err}");
    assert!(msg.contains("test_fail"), "label should appear: {msg}");
}

#[test]
fn run_winrt_with_timeout_translates_worker_panic_to_internal_error() {
    // a panic inside the `get` closure must
    // surface as a typed `AppError::Internal` (not the
    // "worker disconnected" fallback) so the renderer's error
    // path can show the panic detail and the platform.diagnostics
    // log can capture the failure mode for triage.
    let err = run_winrt_with_timeout(
        "test_panic",
        Duration::from_secs(5),
        || -> windows_core::Result<i32> {
            panic!("simulated FFI panic");
        },
        || {},
    )
    .expect_err("worker panic should surface");

    match err {
        AppError::Internal(msg) => {
            assert!(msg.contains("test_panic"), "label should appear: {msg}");
            assert!(
                msg.contains("panicked"),
                "panic detail should propagate: {msg}"
            );
        }
        other => panic!("expected AppError::Internal for panic, got {other:?}"),
    }
}

#[test]
fn run_winrt_with_timeout_calls_cancel_and_returns_timeout_on_expiry() {
    let cancel_fired = Arc::new(AtomicBool::new(false));
    let cancel_fired_clone = Arc::clone(&cancel_fired);

    let err = run_winrt_with_timeout(
        "test_timeout",
        Duration::from_millis(50),
        || {
            std::thread::sleep(Duration::from_secs(2));
            Ok::<_, windows_core::Error>(0i32)
        },
        move || {
            cancel_fired_clone.store(true, Ordering::SeqCst);
        },
    )
    .expect_err("slow get should time out");

    match err {
        AppError::Timeout(msg) => {
            assert!(msg.contains("test_timeout"), "got {msg}");
            assert!(
                msg.contains("did not complete"),
                "expected timeout phrasing, got {msg}"
            );
        }
        other => panic!("expected AppError::Timeout, got {other:?}"),
    }
    assert!(
        cancel_fired.load(Ordering::SeqCst),
        "cancel closure must run on timeout to abort the WinRT op"
    );
}
