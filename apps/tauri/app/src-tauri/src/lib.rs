// Tests intentionally use unwrap() / expect() for assertion clarity
// — panics there ARE the failure mode. Mirrors the same shield every
// other workspace crate carries (lorvex-domain, lorvex-store,
// lorvex-sync, lorvex-runtime, lorvex-cli, mcp-server). Without this
// test-time relaxation, the workspace `clippy::unwrap_used = "warn"`
// lint would fire on hundreds of test fixtures under
// `cargo clippy --all-targets -- -D warnings`.
#![cfg_attr(test, allow(clippy::unwrap_used))]

//! Tauri 2 application entry point.
//!
//! `lib.rs` orchestrates the boot pipeline (panic hook → migration
//! gate → plugin chain → setup → handler list → run-event dispatch)
//! but defers each phase to a focused sibling module:
//!
//! - [`bootstrap`]: panic hook + the SQL-migration progress gate
//!   raised before the Tauri builder runs.
//! - [`plugins`]: the cross-platform `.plugin(...)` chain, with
//!   `#[cfg(...)]` gates centralized so this file stays linear.
//! - [`setup_hook`]: the Tauri `setup` callback body — event bus
//!   init, system tray, close-to-hide policies, Spotlight reindex,
//!   startup maintenance.
//! - [`runtime_events`]: `RunEvent::Opened` (deep links) and
//!   `RunEvent::Reopen` (macOS Dock).
//!
//! Even the handler list itself is no longer hand-maintained:
//! `build.rs` walks `src/commands/` and
//! `src/calendar_subscription_sync/`, scrapes every
//! `#[tauri::command]` definition, and emits a handler-registration
//! function into `OUT_DIR` with module-qualified command paths.
//! `commands.rs` `include!`s that function so it can reference its
//! private command modules directly. Adding a new Tauri command is
//! now a 2-place edit (the leaf `#[tauri::command]` definition + an
//! `ipc.ts` wrapper) — the build script regenerates the handler list
//! automatically.

mod bootstrap;
mod calendar_subscription_sync;
mod commands;
mod db;
mod deep_link;
#[cfg(desktop)]
mod desktop_close_policy;
#[cfg(desktop)]
mod desktop_geometry;
#[cfg(desktop)]
mod desktop_shell;
pub(crate) mod error;
mod event_bus;
mod event_channels;
mod hlc;
mod invariants;
// the MCP server is a sidecar binary launched via fork+exec. Android support
// is a future separate runtime, so gate the desktop MCP sidecar out there.
#[cfg(not(target_os = "android"))]
mod mcp_runtime;
mod memory_lock;
#[cfg(desktop)]
mod menu_i18n;
mod platform;
mod plugins;
mod proxy_env;
mod runtime_events;
mod setup_hook;
#[cfg(test)]
mod test_support;
#[cfg(desktop)]
mod tray_geometry;
#[cfg(desktop)]
mod window_restore;
#[cfg(desktop)]
mod window_space;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    bootstrap::install_panic_hook();
    bootstrap::ensure_database_ready();

    let builder = plugins::install_plugins(tauri::Builder::default()).setup(setup_hook::setup_app);
    commands::apply_invoke_handlers(builder)
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(runtime_events::handle_run_event);
}
