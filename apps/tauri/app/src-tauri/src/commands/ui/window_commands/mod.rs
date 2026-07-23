//! `window_commands` — UI-shell window-management Tauri IPC handlers.
//!
//! Split out of the prior single-file `window_commands.rs` for #3303 so
//! each handler family lives in its own module. Sibling submodules:
//!
//!   * `tray` — tray icon visibility (with desktop-close-action
//!     preflight that prevents hiding the tray while the close button
//!     is configured to "hide to tray").
//!   * `popover` — quick-capture popover hide.
//!   * `deep_link` — main-window deep-link IPC (open-by-target,
//!     consume + acknowledge pending payload).
//!   * `native_effects` — Windows 11 Mica material + immersive
//!     dark-mode title-bar attribute, gated behind a real `RtlGetVersion`
//!     probe so Win10 hosts don't hard-error on the DWM call.
//!
//! Re-exports are flattened so `commands.rs` keeps the same public
//! surface (each `#[tauri::command]` resolves through the same name in
//! the `commands` barrel that `lib.rs` `generate_handler!` references).

pub(crate) mod deep_link;
pub(crate) mod native_effects;
pub(crate) mod popover;
pub(crate) mod tray;

pub use popover::hide_popover_window;
