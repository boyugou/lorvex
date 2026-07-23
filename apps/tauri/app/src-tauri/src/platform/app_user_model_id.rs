//! Pin the process's `AppUserModelID` so install/upgrade churn doesn't
//! reset per-app permissions on Windows.
//!
//! Tauri's NSIS bundler emits a per-version install
//! directory under `%LOCALAPPDATA%\Programs\Lorvex\<version>\`, and the
//! shell derives an implicit AppUserModelID from the install path (or
//! the running EXE path) when the application doesn't declare one
//! explicitly. Per-app permissions in
//! "Settings → Privacy & Security → Calendar" — and the calendar
//! broker's per-AUMID consent ledger — key off the AUMID. So when the
//! user upgrades from 1.0.0 → 1.0.1, the AUMID effectively changes,
//! the broker treats Lorvex as a new app, and the user has to re-grant
//! Calendar/Hello access on every update. Pinning the AUMID via
//! [`SetCurrentProcessExplicitAppUserModelID`] early in startup —
//! before any shell or broker call — bypasses the implicit derivation
//! so the consent persists across versions.
//!
//! The chosen AUMID matches the bundle identifier (`com.lorvex.planner`)
//! so it remains stable as long as the identifier is, regardless of
//! which install path the user picked or which direct desktop channel
//! they came from.

#![cfg(target_os = "windows")]

use windows::core::HSTRING;
use windows::Win32::UI::Shell::SetCurrentProcessExplicitAppUserModelID;

/// Stable AppUserModelID. Mirrors the bundle identifier in
/// `tauri.conf.json::identifier`. Keep in lock-step if the identifier
/// is ever renamed — the calendar broker's ledger will reset on the
/// rename, so plan that as a one-time user-visible event.
const APP_USER_MODEL_ID: &str = "com.lorvex.planner";

/// Apply the AUMID to the current process. Call from the Tauri
/// `setup` hook *before* any code reaches into the shell or
/// WinRT broker (badge, jump list, calendar, biometrics) — the
/// AUMID is read on first broker contact and cached for the
/// process lifetime.
pub(crate) fn install() {
    let id = HSTRING::from(APP_USER_MODEL_ID);
    // SAFETY: `SetCurrentProcessExplicitAppUserModelID` accepts any
    // non-null UTF-16 string as the AUMID. The HSTRING owns the
    // backing buffer for the duration of this call. The function
    // either returns S_OK (idempotent on repeat calls with the same
    // ID) or the older Windows hosts that lack the API (Server
    // 2008 R2 and earlier) return E_NOTIMPL, which we silently
    // swallow — those hosts can't run modern WebView2 anyway.
    unsafe {
        let _ = SetCurrentProcessExplicitAppUserModelID(&id);
    }
}
