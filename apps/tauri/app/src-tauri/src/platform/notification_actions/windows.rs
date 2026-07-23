//! Windows notification action stubs.
//!
//! Toast rich actions (Complete / Snooze) on Windows require a WinRT
//! `ToastNotificationManager` emission path AND a COM-registered
//! `INotificationActivationCallback` (CLSID in the registry via NSIS +
//! correct AUMID). We don't ship either today, so:
//!
//! - Rich action buttons WOULD NOT WORK even if we emitted the XML —
//!   the OS has no CLSID to call back into our process.
//! - Emitting XML without the callback would add buttons that silently
//!   no-op when tapped, which is worse UX than plain toasts.
//!
//! Windows task reminders therefore fall back to plain
//! `@tauri-apps/plugin-notification` toasts with no Complete/Snooze.
//! This file holds the no-op stubs the cross-platform notification
//! registration layer calls into on Windows. Wiring the WinRT + CLSID
//! path is the prerequisite for adding any real action-dispatch code.

pub(super) fn register_notification_categories(_locale: &str) {
    // Windows: no-op. Category-based action registration is a
    // macOS UserNotifications idiom; Windows toasts declare actions
    // inline per-toast, which this codebase doesn't emit (see the
    // file-level comment above).
}

pub(super) fn install_notification_delegate(_app_handle: tauri::AppHandle) {
    // Windows: no-op. See file-level comment — no COM activation
    // dispatcher to install.
    //
    // the full WinRT integration would require:
    //
    //   1. A `ToastNotificationManager::CreateToastNotifier(aumid)`
    //      surface that emits XML toasts with `<actions>` declared
    //      inline (Windows toasts cannot use category-based action
    //      registration the way macOS UserNotifications does).
    //   2. An `INotificationActivationCallback` COM object registered
    //      under the app's CLSID so Action Center button clicks route
    //      back into the running Tauri process via COM activation.
    //   3. A manifest entry in the Start Menu shortcut declaring the
    //      AUMID and ToastActivatorCLSID (set by the NSIS installer).
    //
    // Without that stack, reminders fall through to plain
    // `@tauri-apps/plugin-notification` toasts with no Complete/Snooze
    // affordance — see the file-level comment for the rationale why
    // the speculative scaffolding was removed under CLAUDE.md rule #11.
    //
    // Record the build-time deviation through error_logs /
    // Diagnostics (source `platform.notification_actions`, level
    // `info`) so the capability gap is observable in support
    // bundles. `eprintln!` would go nowhere on Tauri release
    // binaries because `windows_subsystem = "windows"` removes the
    // console.
    if let Ok(conn) = crate::db::get_conn() {
        let _ = crate::commands::diagnostics::append_error_log_internal(
            &conn,
            "platform.notification_actions",
            "Windows rich notification actions (Complete/Snooze on toast) are not supported \
             in this build; reminders display as plain toasts. Requires WinRT \
             ToastNotificationManager + COM INotificationActivationCallback wiring \
             (out of scope for).",
            None,
            Some("info".to_string()),
        );
    }
}

// No Windows-specific handler module: a future COM integration
// should refactor the `cfg` gate on `macos_delegate::handle_*` (or
// extract the platform-agnostic body into a shared helper) rather
// than re-declaring platform-specific stubs here. Pre-refactor the
// Windows module had speculative stubs + zero callers; it was
// deleted under CLAUDE.md rule #11.
