//! Bounded waits for WinRT `IAsyncOperation::get()` and friends.
//!
//! WinRT's `IAsyncOperation<T>::get()` is a *synchronous* wait that
//! parks the calling thread until the operation completes. On a healthy
//! desktop this is fine — the broker resolves in milliseconds. On
//! corporate-managed boxes (Group Policy spinning up the calendar
//! broker, MDM-locked Hello provisioning, a stuck Windows Hello PIN
//! ceremony) the broker can stall *indefinitely*, and the calling
//! thread is held hostage with no way out. See #2837 for the calendar
//! sync flavor of this bug.
//!
//! [`run_winrt_with_timeout`] runs the blocking `get()` on a
//! detached `std::thread`, applies a hard timeout, and on expiry calls
//! the WinRT operation's `Cancel()` to abort the broker work. The
//! caller must hand us two closures — one that performs `op.get()` and
//! one that performs `op.Cancel()` — because the concrete
//! `IAsyncOperation<T>` type lives in the `windows_future` crate which
//! we don't take a direct dependency on. The closure-pair shape lets
//! every call site clone its operation handle (WinRT interfaces are
//! ref-counted COM pointers) and capture both halves without exposing
//! the generic type parameter to this helper.

#![cfg(target_os = "windows")]

use crate::error::{AppError, AppResult};
use std::sync::mpsc;
use std::time::Duration;

/// Default budget for "this should be a fast broker round-trip" WinRT
/// calls. 30 seconds is comfortably above any healthy WinRT round-trip
/// observed in practice and matches the budget already used by the
/// macOS Touch ID prompt in `biometrics.rs` — keeping a single
/// platform-async timeout knob makes the user-visible "stalled
/// permission prompt" recovery time consistent across operating
/// systems.
pub(crate) const WINRT_DEFAULT_TIMEOUT: Duration = Duration::from_secs(30);

/// Wait for a WinRT `IAsyncOperation::get()` (or compatible blocking
/// async wait) with a hard timeout, calling the supplied `cancel`
/// closure on expiry to abort the operation at the broker level.
///
/// `op_label` is included verbatim in the `AppError::Timeout` message
/// so the user-facing toast and the diagnostic log identify which
/// WinRT operation gave up — important when a single user gesture
/// chains several broker calls (e.g. `RequestStoreAsync` →
/// `FindAppointmentCalendarsAsync` → `FindAppointmentsAsync`) and we
/// need to know which step stalled.
pub(crate) fn run_winrt_with_timeout<G, C, T>(
    op_label: &str,
    timeout: Duration,
    get: G,
    cancel: C,
) -> AppResult<T>
where
    G: FnOnce() -> windows_core::Result<T> + Send + 'static,
    C: FnOnce() + Send + 'static,
    T: Send + 'static,
{
    let (tx, rx) = mpsc::sync_channel::<windows_core::Result<T>>(1);

    // Detached worker thread: WinRT `.get()` parks this thread on a
    // signaler, so we must not run it on the Tokio executor or the
    // IPC dispatch thread. `std::thread::spawn` is fine — the only
    // resource it owns is the operation clone, which is a ref-counted
    // COM pointer that drops naturally when the closure ends.
    //
    // enter a multi-threaded apartment on the worker
    // before invoking the WinRT proxy. Most WinRT APIs are agile
    // (`IAgileObject`) so the cross-thread call is well-defined even
    // without an apartment, but the cancel closure runs on the
    // original (STA) IPC thread on timeout — pairing the two with
    // explicit apartment lifetimes avoids relying on undocumented
    // marshalling fast-paths. A poisoned RPC_E_CHANGED_MODE just
    // means the OS already initialized this thread; the guard's Drop
    // is a no-op in that case.
    // name the thread so a stuck WinRT broker call
    // is identifiable in Process Explorer / WinDbg stacks rather than
    // showing up as an anonymous `std::thread`. The `op_label` is
    // included verbatim because each call site already provides a
    // distinct WinRT operation name (`RequestStoreAsync`,
    // `FindAppointmentsAsync`, etc.) which is exactly the right
    // granularity for "which broker stalled?" diagnostics.
    let thread_name = format!("lorvex-winrt-{op_label}");
    let op_label_for_panic = op_label.to_string();
    std::thread::Builder::new()
        .name(thread_name)
        .spawn(move || {
            // mirror the macOS pattern (#2912)
            // and wrap the WinRT closure in `catch_unwind`. A panic
            // crossing the FFI boundary out of a WinRT property
            // accessor (e.g. inside the user-supplied `get` closure
            // when the broker returns garbage that fails to
            // round-trip the `windows_core` typed wrappers) is
            // undefined behavior on Windows because the OS unwind
            // tables don't extend across the COM proxy. By catching
            // here we (a) keep the apartment guard's Drop reachable
            // so `CoUninitialize` runs, and (b) deliver an error to
            // the receiver so the caller surfaces a typed
            // `Internal` rather than the Disconnected fallback (the
            // sender being dropped without sending was previously
            // the only way the parent could observe a panic, which
            // collapsed all panic causes into a single "worker
            // disconnected" message).
            let _com_guard = crate::platform::com_apartment::ComApartmentGuard::enter_sta();
            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| get()));
            let payload = match result {
                Ok(value) => value,
                Err(panic) => {
                    let detail = if let Some(s) = panic.downcast_ref::<&'static str>() {
                        (*s).to_string()
                    } else if let Some(s) = panic.downcast_ref::<String>() {
                        s.clone()
                    } else {
                        format!("non-string panic payload type_id={:?}", panic.type_id())
                    };
                    Err(windows_core::Error::new(
                        windows_core::HRESULT(-1),
                        format!(
                            "{op_label_for_panic} worker panicked across the WinRT FFI boundary: {detail}"
                        ),
                    ))
                }
            };
            let _ = tx.send(payload);
        })
        .expect("spawn WinRT worker thread");

    match rx.recv_timeout(timeout) {
        Ok(Ok(value)) => Ok(value),
        Ok(Err(e)) => Err(AppError::Internal(format!("{op_label} failed: {e}"))),
        Err(mpsc::RecvTimeoutError::Timeout) => {
            // Aborting the broker work is best-effort. If the WinRT
            // operation already completed between our timeout check
            // and the cancel call, `Cancel()` is a no-op; if the
            // broker is genuinely wedged, this nudges it to return
            // `AsyncStatus::Canceled` so the worker thread doesn't
            // leak forever on a stuck `signaler.wait()`.
            cancel();
            Err(AppError::Timeout(format!(
                "{op_label} did not complete within {}s; cancelled to recover. \
                 If this keeps happening, the OS broker for this operation may \
                 be stalled — check Windows Settings → Privacy & Security and \
                 restart the relevant service.",
                timeout.as_secs()
            )))
        }
        Err(mpsc::RecvTimeoutError::Disconnected) => {
            // The worker thread panicked or dropped the sender before
            // sending. Surface as Internal so the caller's error path
            // distinguishes this from a normal timeout and from a
            // WinRT-reported failure — an unexpected drop usually
            // means the closure panicked across the FFI boundary,
            // which is a bug worth investigating in the diagnostic
            // bundle rather than retrying silently.
            Err(AppError::Internal(format!(
                "{op_label} worker disconnected before reporting a result"
            )))
        }
    }
}

#[cfg(test)]
mod tests;
