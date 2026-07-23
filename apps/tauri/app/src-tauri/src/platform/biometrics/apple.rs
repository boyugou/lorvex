//! macOS biometric authentication via `LAContext`.
//! `DeviceOwnerAuthenticationWithBiometrics` policy maps to Touch ID
//! on macOS. The `DeviceOwnerAuthenticationWithWatch` variant is
//! intentionally NOT used because it would let an Apple Watch unlock by
//! proximity, which is not the gate the user opted into.

fn take_biometric_reply_sender<T>(
    shared: &std::sync::Arc<std::sync::Mutex<Option<T>>>,
) -> Option<T> {
    match shared.lock() {
        Ok(mut guard) => guard.take(),
        Err(poisoned) => poisoned.into_inner().take(),
    }
}

/// Authenticate the user with platform biometrics.
///
/// Returns `Ok(true)` if the user authenticated successfully, or `Err(message)`
/// for every non-success path: user cancellation, fallback, hardware
/// unavailability, and timeout. The macOS `LAContext` API surfaces all of
/// those uniformly as `success=false` with a localized `NSError`, and we
/// currently propagate the message verbatim — the UI rejects the operation
/// the same way regardless of the underlying reason. Issue #2941-L3 left
/// this aligned (matched doc to impl) rather than splitting cancellation
/// into a typed `Ok(false)`; that refactor needs a corresponding caller-side
/// audit and is tracked separately.
///
/// `DeviceOwnerAuthenticationWithWatch` is intentionally NOT used: it would
/// let an Apple Watch unlock by proximity, which is not the gate the user
/// opted into.
pub(crate) async fn authenticate(reason: String) -> Result<bool, String> {
    use block2::RcBlock;
    use objc2_foundation::NSString;
    use objc2_local_authentication::{LAContext, LAPolicy};
    use std::sync::{Arc, Mutex};
    use std::time::Duration;

    // LAContext is thread-safe — evaluatePolicy can be called from any thread.
    // The reply block fires on an internal LA Services queue.
    let (tx, rx) = std::sync::mpsc::channel::<Result<bool, String>>();

    // Spawn onto a blocking thread so the entire biometric flow (including the
    // recv_timeout wait) happens off the Tokio executor, preventing it from
    // being blocked while the user interacts with the Touch ID prompt.
    tauri::async_runtime::spawn_blocking(move || {
        // SAFETY: documented Obj-C class
        // constructor; allocates an autoreleased `LAContext` with no
        // preconditions. The returned `Retained<_>` handles release
        // on drop.
        let ctx_la = unsafe { LAContext::new() };
        let policy = LAPolicy::DeviceOwnerAuthenticationWithBiometrics;

        // SAFETY: `ctx_la` is alive for the call;
        // `canEvaluatePolicy_error` returns a typed
        // `Result<bool, Retained<NSError>>` via objc2's typed wrapper.
        if let Err(e) = unsafe { ctx_la.canEvaluatePolicy_error(policy) } {
            return Err(format!(
                "Touch ID not available: {}",
                e.localizedDescription()
            ));
        }

        let tx = Arc::new(Mutex::new(Some(tx)));
        let reply_block = {
            let tx = tx;
            RcBlock::new(
                move |success: objc2::runtime::Bool, error: *mut objc2_foundation::NSError| {
                    // Panic safety: the LA Services
                    // queue invokes this block; a panic crossing the
                    // Obj-C → Rust boundary is UB on macOS. The body
                    // touches a Mutex (which can be poisoned by a
                    // panic on a different thread) and dereferences
                    // an Obj-C error pointer to call
                    // `localizedDescription` (which can allocate). The
                    // recv side already handles `Disconnected` via a
                    // generic timeout failure, so a swallowed panic
                    // surfaces cleanly to the user.
                    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                        if let Some(sender) = take_biometric_reply_sender(&tx) {
                            if success.as_bool() {
                                let _ = sender.send(Ok(true));
                            } else {
                                let msg = if error.is_null() {
                                    "Authentication failed".to_string()
                                } else {
                                    // SAFETY
                                    // null-checked `NSError *`
                                    // delivered by the LAContext reply
                                    // block; LAContext retains the
                                    // autoreleased error until the
                                    // block returns.
                                    unsafe { (*error).localizedDescription().to_string() }
                                };
                                let _ = sender.send(Err(msg));
                            }
                        }
                    }));
                },
            )
        };

        let reason_ns = NSString::from_str(&reason);
        // SAFETY: `ctx_la`, `reason_ns`, and
        // `reply_block` are all live `Retained<_>` references for
        // the duration of the call. LA Services retains the reply
        // block internally until it has fired.
        unsafe {
            ctx_la.evaluatePolicy_localizedReason_reply(policy, &reason_ns, &reply_block);
        }

        match rx.recv_timeout(Duration::from_secs(30)) {
            Ok(result) => result,
            Err(e) => {
                // Audit: dismiss the still-visible Touch ID prompt so
                // the user isn't stuck staring at a modal whose result
                // the app no longer awaits. `LAContext::invalidate`
                // is the documented way to cancel an in-flight
                // evaluation. Do this regardless of why the recv
                // failed — both Disconnected (sender dropped early)
                // and Timeout leave the prompt hanging.
                // SAFETY: `ctx_la` is alive
                // here; `invalidate()` is the documented LAContext
                // cancellation entry point and has no preconditions
                // beyond a live receiver.
                unsafe {
                    ctx_la.invalidate();
                }
                Err(format!("biometric timeout or channel error: {e}"))
            }
        }
    })
    .await
    .map_err(|e| format!("biometric task join error: {e}"))?
}

#[cfg(test)]
mod tests {
    use super::take_biometric_reply_sender;
    use std::panic::{self, AssertUnwindSafe};
    use std::sync::{Arc, Mutex};

    #[test]
    fn take_biometric_reply_sender_returns_sender_once() {
        let shared = Arc::new(Mutex::new(Some("sender")));

        assert_eq!(take_biometric_reply_sender(&shared), Some("sender"));
        assert_eq!(take_biometric_reply_sender(&shared), None);
    }

    #[test]
    fn take_biometric_reply_sender_recovers_from_poisoned_mutex() {
        let shared = Arc::new(Mutex::new(Some("sender")));
        let shared_for_panic = Arc::clone(&shared);

        let _ = panic::catch_unwind(AssertUnwindSafe(move || {
            let _guard = shared_for_panic.lock().expect("lock shared sender");
            panic!("poison sender mutex");
        }));

        assert_eq!(take_biometric_reply_sender(&shared), Some("sender"));
    }
}
