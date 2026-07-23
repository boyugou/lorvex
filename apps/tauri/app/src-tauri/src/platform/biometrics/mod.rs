//! Platform-specific biometric authentication.
//!
//! - macOS: Touch ID via LAContext (implemented)
//! - Windows: Windows Hello via KeyCredentialManager (implemented)
//! - Android: BiometricPrompt via JNI (future)
//! - Linux: returns Err — no standard biometric API
//!
//! #3303 P2 split — the previous 582-LOC `biometrics.rs` carried
//! three independent platform arms gated by `#[cfg(target_os)]`
//! attributes. Each backend now lives in its own sibling so the
//! per-platform review surface is bounded:
//!
//!   * `apple` — macOS `LAContext` path + the cfg-agnostic
//!     `take_biometric_reply_sender` poison-tolerant Mutex helper +
//!     its 2 unit tests.
//!   * `windows` — Windows Hello `KeyCredentialManager` path with
//!     hard timeouts on every WinRT `.get()`, fail-closed on broker
//!     / Group Policy / contract-violation status codes, plus the
//!     `log_biometrics_warning` `error_logs` writer.
//!   * `unsupported` — Linux + every other target: typed `Err(...)`
//!     remediation message; no silent `Ok(true)` bypass.
//!
//! `mod.rs` itself owns the `SUPPORTS_BIOMETRIC_LOCK` capability
//! constant and the cfg-dispatched re-export of `authenticate` so
//! every caller still resolves through `platform::biometrics::authenticate`.

#[cfg(target_os = "macos")]
mod apple;
#[cfg(not(any(target_os = "macos", target_os = "windows")))]
mod unsupported;
#[cfg(target_os = "windows")]
mod windows;

#[cfg(target_os = "macos")]
pub(crate) use apple::authenticate;
#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub(crate) use unsupported::authenticate;
#[cfg(target_os = "windows")]
pub(crate) use windows::authenticate;

/// backend constant matching the renderer-side
/// `RUNTIME_PROFILE_DEFINITIONS[<id>].supportsBiometricLock`. Used by
/// the preference write-side guard so a synced
/// `memory_lock_enabled = true` from a macOS peer cannot re-enable
/// the lock UI on a Linux device that has no biometric backend wired
/// up. Kept here so the cfg-selected biometric authenticator and the
/// platform capability flag stay in lock-step in one place.
pub(crate) const SUPPORTS_BIOMETRIC_LOCK: bool =
    cfg!(any(target_os = "macos", target_os = "windows"));
