//! Non-macOS, non-Windows platforms (Linux): fail closed.
//!
//! Returning `Err(...)` is the honest answer on Linux: there is no
//! Linux biometric backend wired up (polkit / libfprint would
//! require a separate runtime dependency), so the UI presents
//! "biometrics unsupported on this platform; fall back to another
//! auth method". Returning `Ok(true)` would let a user who enabled
//! biometric lock on macOS and synced settings to a Linux peer have
//! the Linux client silently grant access with no biometric check —
//! a false sense of security.
//!
//! The Linux variant of `platform::capabilities` already sets
//! `supports_biometric_lock = false`, so the lock toggle does not
//! appear in Settings. This is a defense-in-depth measure for the
//! cross-device-preference-sync scenario the audit flagged.

pub(crate) async fn authenticate(_reason: String) -> Result<bool, String> {
    Err("biometric authentication is not available on this platform".to_string())
}
