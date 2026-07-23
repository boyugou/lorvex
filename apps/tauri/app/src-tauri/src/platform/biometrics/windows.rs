//! Windows Hello biometric authentication via
//! `KeyCredentialManager`. Fails closed on every error path
//! (broker unreachable, Group Policy disabled, no enrollment,
//! contract-violation status codes) so an attacker triggering a
//! broker-side failure cannot bypass the biometric gate the user
//! opted into. Each WinRT `.get()` is wrapped in a hard timeout
//! (#2837) so a wedged broker can't leave the prompt hanging.

/// Persist a Windows Hello diagnostic to error_logs so Settings →
/// Diagnostics surfaces unmapped statuses and broker failures.
/// Packaged Windows builds run with `windows_subsystem=windows` and
/// no console, so `eprintln!`-only diagnostics would be invisible —
/// every unmapped-status branch routes through this helper. Falls
/// through silently when the DB itself is unreachable rather than
/// crash the auth flow, matching the contract used by other platform
/// helpers.

fn log_biometrics_warning(context: &str, message: &str) {
    let detail = format!("{context}: {message}");
    if let Ok(conn) = crate::db::get_conn() {
        let _ = crate::commands::diagnostics::append_error_log_internal(
            &conn,
            "platform.biometrics",
            &detail,
            None,
            Some("warn".to_string()),
        );
    }
}

/// Authenticate the user with Windows Hello via KeyCredentialManager.
/// Returns Ok(true) if authenticated, Ok(false) if the user cancelled or
/// Windows Hello denied the request, Err on unexpected failure or when
/// Windows Hello is unreachable / not enrolled.
///
/// Fail closed when the broker is unreachable or no Hello
/// credential is enrolled: surface the failure as `Err(...)` and
/// the caller keeps the surface locked. The guarantee a user clicks
/// the "lock memory" toggle for is "no one without my fingerprint /
/// PIN can open these notes," so returning `Ok(true)` for a
/// missing broker / missing enrollment would silently bypass the
/// biometric gate the user explicitly opted into. The settings UI
/// shows a remediation copy that points the user at Windows
/// Settings → Sign-in options to enroll Hello.

pub(crate) async fn authenticate(_reason: String) -> Result<bool, String> {
    // `reason` is the user-visible prompt
    // string macOS surfaces via `LAContext::evaluatePolicy`. Windows
    // Hello has no equivalent caller-supplied reason — the system
    // displays its own broker-driven copy ("Verify your identity for
    // Lorvex" derived from the AUMID + bundle name). The argument is
    // accepted for cross-platform symmetry and intentionally
    // ignored here.
    use crate::platform::winrt_async::{run_winrt_with_timeout, WINRT_DEFAULT_TIMEOUT};
    use windows::Security::Credentials::{
        KeyCredentialCreationOption, KeyCredentialManager, KeyCredentialStatus,
    };

    // All Windows Hello calls are blocking WinRT async — run them off the
    // Tokio executor to avoid stalling the event loop. Each WinRT
    // `.get()` is additionally wrapped in a hard timeout (#2837) so a
    // wedged Windows Hello broker — Group Policy, MDM provisioning, a
    // stuck PIN ceremony — cannot leave the user's biometric prompt
    // hanging forever; on expiry the operation is cancelled at the
    // WinRT layer and we report a typed timeout error to the caller.
    tauri::async_runtime::spawn_blocking(move || {
        // 1. Check whether Windows Hello is available on this device.
        //
        // a broker-side failure here (Group Policy
        // disabling KeyCredentialManager, MDM provisioning glitch,
        // missing TPM driver, etc.) MUST surface as a typed `Err(...)`
        // so the caller keeps the locked surface locked. The earlier
        // implementation (#2968-M4) returned `Ok(true)` here to avoid
        // locking out users on hosts where Windows Hello was
        // unreachable; that lockout-prevention reasoning is
        // out-weighed by the security guarantee the user opted into:
        // an attacker triggering a broker-side failure (e.g. by
        // spawning a Group Policy override before the prompt) would
        // otherwise auto-unlock the surface without ever presenting
        // a biometric prompt.
        let is_supported_op = match KeyCredentialManager::IsSupportedAsync() {
            Ok(op) => op,
            Err(e) => {
                // pattern-match the HRESULT to
                // distinguish a transient broker outage (the call
                // could not even dispatch — typically because
                // `KeyCredentialManager` is disabled by Group Policy
                // or the broker process crashed) from a host that
                // genuinely doesn't support Windows Hello. Both fail
                // closed (the security guarantee is the same), but
                // the user-facing remediation differs: "enroll Hello"
                // vs "ask your IT admin to allow it" vs "this device
                // has no compatible hardware". The renderer can show
                // the right banner copy based on the message prefix.
                let raw = e.code().0 as u32;
                let facility = (raw >> 16) & 0x1FFF;
                // FACILITY_GROUP_POLICY = 0x14 — any HRESULT whose
                // facility bits are 0x14 originated in a Group Policy
                // enforcement path, regardless of the specific code.
                const FACILITY_GROUP_POLICY: u32 = 0x14;
                // E_NOTIMPL (0x80004001) — the broker itself reports
                // the API is not implemented (older SKUs, Server Core
                // without the credential broker).
                const E_NOTIMPL: u32 = 0x8000_4001;
                let detail = if facility == FACILITY_GROUP_POLICY {
                    format!(
                        "Windows Hello is disabled by Group Policy on \
                         this device (HRESULT 0x{raw:08X}). Contact \
                         your IT administrator to enable the \
                         credential broker, or disable the memory \
                         lock in Settings → Privacy. The biometric \
                         gate is failing closed."
                    )
                } else if raw == E_NOTIMPL {
                    format!(
                        "Windows Hello is not available on this \
                         Windows edition (HRESULT 0x{raw:08X}). \
                         Disable the memory lock in Settings → \
                         Privacy, or use a Windows edition that \
                         ships the credential broker. The biometric \
                         gate is failing closed."
                    )
                } else {
                    format!(
                        "Windows Hello broker is unreachable \
                         (HRESULT 0x{raw:08X}: {e}). The biometric \
                         gate is failing closed; restart the device \
                         to recover the broker, or enroll Windows \
                         Hello in Settings → Sign-in options."
                    )
                };
                log_biometrics_warning(
                    "Windows Hello IsSupportedAsync unavailable; failing closed",
                    &format!("HRESULT 0x{raw:08X}: {e}"),
                );
                return Err(detail);
            }
        };
        let is_supported_op_for_cancel = is_supported_op.clone();
        let is_supported_op_for_get = is_supported_op;
        let available = run_winrt_with_timeout(
            "Windows Hello KeyCredentialManager.IsSupportedAsync",
            WINRT_DEFAULT_TIMEOUT,
            move || is_supported_op_for_get.get(),
            move || {
                let _ = is_supported_op_for_cancel.Cancel();
            },
        )
        .map_err(|e| e.to_string())?;

        if !available {
            // no Windows Hello enrollment. Previously
            // we returned `Ok(true)` here as a usability concession.
            // That is a bypass: a user who opts into the memory lock
            // expects the app to refuse access until biometrics
            // verifies them, not to silently let everyone in because
            // Hello isn't enrolled. Surface the unavailability as a
            // typed Err so the renderer can present a remediation
            // banner ("enroll Windows Hello to unlock memory") rather
            // than silently dropping the gate.
            log_biometrics_warning(
                "Windows Hello not enrolled; failing closed",
                "KeyCredentialManager.IsSupportedAsync returned false",
            );
            return Err(
                "Windows Hello is not enrolled on this device. Open Settings → \
                 Sign-in options to enroll, then re-try. The memory lock will \
                 stay engaged until biometrics is configured."
                    .to_string(),
            );
        }

        // 2. Try to open an existing credential for the Lorvex
        //    application identity. If one doesn't exist yet, create it
        //    (this triggers Windows Hello enrollment UI on first use).
        //
        // Use the bundle identifier `com.lorvex.planner` (matching
        // the pinned AUMID — see `platform::app_user_model_id`) so
        // the broker's per-AUMID consent ledger and the
        // per-credential enrollment record share one stable
        // namespace. A free-form display string ("Lorvex") would
        // collide with any other vendor that happens to ship a
        // credential under the same name AND drift away from the
        // AUMID, forcing the user to re-authenticate after AUMID
        // changes.
        const HELLO_CREDENTIAL_ID: &str = "com.lorvex.planner";
        let open_op = KeyCredentialManager::OpenAsync(
            &windows::core::HSTRING::from(HELLO_CREDENTIAL_ID),
        )
        .map_err(|e| format!("Windows Hello OpenAsync failed: {e}"))?;
        let open_op_for_cancel = open_op.clone();
        let open_op_for_get = open_op;
        let open_result = run_winrt_with_timeout(
            "Windows Hello KeyCredentialManager.OpenAsync",
            WINRT_DEFAULT_TIMEOUT,
            move || open_op_for_get.get(),
            move || {
                let _ = open_op_for_cancel.Cancel();
            },
        )
        .map_err(|e| e.to_string())?;

        match open_result
            .Status()
            .map_err(|e| format!("OpenAsync status error: {e}"))?
        {
            KeyCredentialStatus::Success => {
                // Credential exists — request a sign operation to verify the user.
                let credential = open_result
                    .Credential()
                    .map_err(|e| format!("Failed to get credential: {e}"))?;

                // RequestSignAsync with an empty buffer triggers the Windows Hello
                // verification prompt (PIN / fingerprint / face) without actually
                // signing any payload.
                //
                // `Buffer::Create(0)` constructs a
                // zero-capacity `IBuffer`, not a null pointer.
                // `KeyCredential::RequestSignAsync` reads `buffer.Length()`
                // to size the data-to-sign, so a zero-length buffer
                // produces a "verify-only" prompt: the broker drives the
                // biometric ceremony, the kernel signs the empty payload,
                // and the resulting signature value is irrelevant —
                // success/failure of the prompt is what we inspect via
                // `KeyCredentialOperationResult::Status()`. Documented
                // here because "Create(0) is intentional" is subtle —
                // a reader would otherwise assume an oversight. See
                // <https://learn.microsoft.com/en-us/uwp/api/windows.security.credentials.keycredential.requestsignasync>.
                let buffer = windows::Storage::Streams::Buffer::Create(0)
                    .map_err(|e| format!("Failed to create empty buffer: {e}"))?;

                let sign_op = credential
                    .RequestSignAsync(&buffer)
                    .map_err(|e| format!("RequestSignAsync failed: {e}"))?;
                let sign_op_for_cancel = sign_op.clone();
                let sign_op_for_get = sign_op;
                let sign_result = run_winrt_with_timeout(
                    "Windows Hello KeyCredential.RequestSignAsync",
                    WINRT_DEFAULT_TIMEOUT,
                    move || sign_op_for_get.get(),
                    move || {
                        let _ = sign_op_for_cancel.Cancel();
                    },
                )
                .map_err(|e| e.to_string())?;

                match sign_result
                    .Status()
                    .map_err(|e| format!("Sign status error: {e}"))?
                {
                    KeyCredentialStatus::Success => Ok(true),
                    KeyCredentialStatus::UserCanceled => Ok(false),
                    other => {
                        log_biometrics_warning(
                            "Windows Hello sign returned unmapped status",
                            &format!("{other:?}"),
                        );
                        Ok(false)
                    }
                }
            }
            KeyCredentialStatus::CredentialAlreadyExists => {
                // Fail closed. `OpenAsync` returning
                // `CredentialAlreadyExists` is a contract violation
                // (the WinRT docs reserve this status for
                // `RequestCreateAsync`), and the user has NOT been
                // challenged for biometrics — neither a PIN ceremony
                // nor a fingerprint touch happened. Treating a
                // contract-violation status as success would let a
                // buggy or spoofed broker (or a future SDK change
                // re-routing the status code) bypass the biometric
                // gate the user opted into. Surface a typed error so
                // the renderer can show a remediation banner instead
                // of unlocking the protected surface silently.
                log_biometrics_warning(
                    "Windows Hello OpenAsync returned unexpected CredentialAlreadyExists; failing closed",
                    "OpenAsync should never return this status per WinRT contract",
                );
                Err(
                    "Windows Hello returned an unexpected status \
                     (`CredentialAlreadyExists` from `OpenAsync`). The biometric gate \
                     is failing closed; restart the app or sign out and back in to \
                     reset the credential broker."
                        .to_string(),
                )
            }
            KeyCredentialStatus::NotFound => {
                // No credential yet — create one. This prompts Windows Hello setup
                // for the Lorvex credential.
                //
                // Use the same bundle-id constant `HELLO_CREDENTIAL_ID`
                // for `RequestCreateAsync` as `OpenAsync` above so
                // the create- and open-side keys agree. Passing the
                // user-visible `reason` string here would key the
                // persisted credential on whatever localized prompt
                // the renderer last sent, drifting away from the
                // AUMID and forcing a re-enrollment on every
                // reason-string change.
                let create_op = KeyCredentialManager::RequestCreateAsync(
                    &windows::core::HSTRING::from(HELLO_CREDENTIAL_ID),
                    KeyCredentialCreationOption::FailIfExists,
                )
                .map_err(|e| format!("RequestCreateAsync failed: {e}"))?;
                let create_op_for_cancel = create_op.clone();
                let create_op_for_get = create_op;
                let create_result = run_winrt_with_timeout(
                    "Windows Hello KeyCredentialManager.RequestCreateAsync",
                    WINRT_DEFAULT_TIMEOUT,
                    move || create_op_for_get.get(),
                    move || {
                        let _ = create_op_for_cancel.Cancel();
                    },
                )
                .map_err(|e| e.to_string())?;

                match create_result
                    .Status()
                    .map_err(|e| format!("Create status error: {e}"))?
                {
                    KeyCredentialStatus::Success => Ok(true),
                    KeyCredentialStatus::CredentialAlreadyExists => {
                        // Fail closed. When `RequestCreateAsync`
                        // returns `CredentialAlreadyExists` (e.g.
                        // because another thread or process created
                        // the credential between the `OpenAsync`
                        // probe and our `RequestCreateAsync`) the
                        // broker did NOT prompt the user for
                        // biometrics — the create attempt short-
                        // circuited because the credential already
                        // existed. The user never touched the
                        // fingerprint sensor or entered the PIN, so
                        // returning `Ok(true)` would bypass the
                        // gate. Surface a typed error so the renderer
                        // can show the remediation copy and the user
                        // can re-trigger the auth flow, which on the
                        // next pass hits the `OpenAsync` +
                        // `RequestSignAsync` happy path that DOES
                        // prompt for biometrics.
                        log_biometrics_warning(
                            "Windows Hello RequestCreateAsync race; credential exists but no biometric prompt fired — failing closed",
                            "another process created the credential between probe and create",
                        );
                        Err(
                            "Windows Hello credential already exists but no biometric \
                             challenge was completed. Re-try to verify with biometrics."
                                .to_string(),
                        )
                    }
                    KeyCredentialStatus::UserCanceled => Ok(false),
                    other => {
                        log_biometrics_warning(
                            "Windows Hello create returned unmapped status",
                            &format!("{other:?}"),
                        );
                        Ok(false)
                    }
                }
            }
            KeyCredentialStatus::UserCanceled => Ok(false),
            other => {
                log_biometrics_warning(
                    "Windows Hello open returned unmapped status",
                    &format!("{other:?}"),
                );
                Ok(false)
            }
        }
    })
    .await
    .map_err(|e| format!("biometric task join error: {e}"))?
}
