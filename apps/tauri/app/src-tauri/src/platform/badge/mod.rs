//! Platform-specific app badge / dock-tile management.
//!
//! - macOS: NSApplication dock tile badge label
//! - Windows: ITaskbarList3 overlay icon
//! - Linux: Unity launcher entry via D-Bus (future)
//! - Android: handled by tauri-plugin-notification badge count
//!
//! #3303 P2 split — the previous 573-LOC `badge.rs` carried three
//! independent platform arms gated by `#[cfg(target_os)]` attributes.
//! Each backend now lives in its own sibling so per-platform reviews
//! (especially the 494-LOC Windows COM/GDI ceremony) read top-to-
//! bottom without scrolling past unrelated cfg arms:
//!
//!   * `macos` — NSApplication dock-tile badge label, dispatched
//!     onto the AppKit main thread.
//!   * `windows` — ITaskbarList3 overlay icon, full DIB-section /
//!     icon-rendering pipeline marshalled onto the window's owning
//!     thread to avoid `RPC_E_WRONG_THREAD`.
//!   * `unsupported` — Linux + every other target: no-op (mobile
//!     uses the notification plugin's built-in badge).

#[cfg(target_os = "macos")]
mod macos;
#[cfg(not(any(target_os = "macos", target_os = "windows")))]
mod unsupported;
#[cfg(target_os = "windows")]
mod windows;

#[cfg(target_os = "macos")]
pub(crate) use macos::set_count;
#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub(crate) use unsupported::set_count;
#[cfg(target_os = "windows")]
pub(crate) use windows::set_count;
