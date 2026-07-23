//! Platform-specific default for what happens when the main window is closed.
//!
//! - macOS: Hide to tray (convention: apps stay running after close)
//! - Others: Quit (convention: closing the window = exit the app)

/// The default close action for the current platform.
pub(crate) const fn default_is_hide_to_tray() -> bool {
    #[cfg(target_os = "macos")]
    {
        true
    }

    #[cfg(not(target_os = "macos"))]
    {
        false
    }
}
