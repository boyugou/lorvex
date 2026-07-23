//! No-op stubs for platforms without native notification action support.
//!
//! Loaded only when the target is neither macOS nor Windows. The
//! parent module's cfg-dispatch shells route to these so the public
//! surface stays uniform across targets.

pub(super) fn register_notification_categories(_locale: &str) {
    // No-op on platforms without native notification action support.
}

pub(super) fn install_notification_delegate(_app_handle: tauri::AppHandle) {
    // No-op on platforms without native notification action support.
}
