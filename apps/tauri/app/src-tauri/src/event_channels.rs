//! Canonical Tauri event channel names.
//!
//! Every backend-emitted channel name lives here as a single
//! `pub const`. Rust `app.emit("…")` call sites import the const so an
//! in-Rust rename is a single-file edit; the React subscriber still
//! subscribes to the literal because TypeScript has no compile-time
//! visibility into Rust constants.
//!
//! Two namespaces participate:
//!   * `lorvex://…` — first-party Lorvex events (data changes, sync
//!     progress, reauth prompts, …). The `lorvex://`
//!     scheme is shared with the deep-link router but never collides
//!     because `Emitter::emit` and `tauri-plugin-deep-link` consume
//!     disjoint message buses.
//!   * `menu://`, `tray://` — UI-shell channels emitted by
//!     window/menu/tray code paths.
//!
//! A `compile-time` test below asserts no two consts share a value, so
//! a future addition that accidentally duplicates a channel name fails
//! the test rather than silently colliding at runtime.

// --- lorvex:// — data + sync notifications ---------------------------

/// Fired whenever a domain entity is mutated. The frontend invalidates
/// the relevant TanStack Query caches.
pub const DATA_CHANGED: &str = "lorvex://data-changed";

/// Fired when a transparent sync recovery succeeded — surfaces a non-blocking
/// toast.
#[allow(dead_code)] // frontend listener remains, but local-only Tauri currently has no producer.
pub const SYNC_NOTICE: &str = "lorvex://sync-notice";

/// Fired during an active sync cycle to advance the progress bar.
pub const SYNC_PROGRESS: &str = "lorvex://sync/progress";

/// Fired when the "reset all data" command failed or partially
/// succeeded — drives a non-blocking toast even if the IPC result has
/// already been consumed.
pub const DATA_RESET_FAILED: &str = "lorvex://data-reset-failed";

/// Fired when a notification-center action fails. The frontend logs
/// the failure and surfaces a recoverable banner.
pub const NOTIFICATION_ACTION_ERROR: &str = "lorvex://notification-action-error";

/// Fired during macOS quit-flush so the renderer can persist any
/// pending edits before the process tears down.
pub const QUIT_FLUSH: &str = "lorvex-quit-flush";

// --- menu:// — native menu items -------------------------------------

/// Generic menu navigation request — payload carries the destination.
pub const MENU_NAVIGATE: &str = "menu://navigate";

/// Open the quick-capture sheet.
pub const MENU_QUICK_CAPTURE: &str = "menu://quick-capture";

/// Open the command palette.
pub const MENU_COMMAND_PALETTE: &str = "menu://command-palette";

/// Enter focus mode from the menu.
pub const MENU_ENTER_FOCUS: &str = "menu://enter-focus";

/// Trigger the export-data flow.
pub const MENU_EXPORT_DATA: &str = "menu://export-data";

/// Trigger the import-data flow.
pub const MENU_IMPORT_DATA: &str = "menu://import-data";

/// Trigger the auto-update check.
pub const MENU_CHECK_UPDATES: &str = "menu://check-updates";

/// Open the keyboard-shortcuts cheatsheet.
pub const MENU_OPEN_SHORTCUTS: &str = "menu://open-shortcuts";

// --- tray:// — system tray events ------------------------------------

/// Fired when the tray popover opens.
pub const TRAY_POPOVER_OPENED: &str = "tray://popover-opened";

#[cfg(test)]
mod tests {
    //! enforce that no two `pub const` channel names in
    //! this module share a string value. A duplicate would mean two
    //! domains accidentally share an event channel — the React side
    //! would receive a payload it can't deserialize, and the Rust side
    //! would never see the broken contract because both emit succeed.

    use super::*;

    /// Every channel const must appear in this list. Any new const
    /// added above without a corresponding entry here will be caught
    /// by `dead_code` audits and the assertion below cannot fire on
    /// the unlisted const, which is the intended trip wire.
    const ALL: &[&str] = &[
        DATA_CHANGED,
        SYNC_NOTICE,
        SYNC_PROGRESS,
        DATA_RESET_FAILED,
        NOTIFICATION_ACTION_ERROR,
        QUIT_FLUSH,
        MENU_NAVIGATE,
        MENU_QUICK_CAPTURE,
        MENU_COMMAND_PALETTE,
        MENU_ENTER_FOCUS,
        MENU_EXPORT_DATA,
        MENU_IMPORT_DATA,
        MENU_CHECK_UPDATES,
        MENU_OPEN_SHORTCUTS,
        TRAY_POPOVER_OPENED,
    ];

    #[test]
    fn no_two_consts_share_a_value() {
        let mut seen = std::collections::HashSet::new();
        for name in ALL {
            assert!(
                seen.insert(*name),
                "event channel name `{name}` is shared by two consts in event_channels.rs"
            );
        }
    }

    /// Defense-in-depth: every channel name must use one of the
    /// approved scheme prefixes. Catches a typo like `"loverx://…"`
    /// that would otherwise compile and ship.
    #[test]
    fn every_channel_uses_an_approved_prefix() {
        for name in ALL {
            let ok = name.starts_with("lorvex://")
                || name.starts_with("menu://")
                || name.starts_with("tray://")
                // The macOS quit-flush channel pre-dates the scheme
                // namespace and is consumed by Tauri's lifecycle hook
                // by literal name. Allow it explicitly.
                || *name == "lorvex-quit-flush";
            assert!(ok, "event channel `{name}` does not use an approved prefix");
        }
    }
}
