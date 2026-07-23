//! Tauri `RunEvent` dispatch.
//!
//! Two events are wired today:
//!
//! - [`tauri::RunEvent::Opened`] — desktop deep-link delivery (macOS
//!   via `CFBundleURLTypes`, Windows via `tauri-plugin-deep-link`).
//!   Each URL is parsed, enqueued for the front-end, and the main
//!   window is brought forward.
//! - [`tauri::RunEvent::Reopen`] — macOS Dock reopen. Routes through
//!   the full restore pipeline so retries / hard-recover stay
//!   available for intermittent races.

#[cfg(desktop)]
use tauri::Emitter;

#[cfg(desktop)]
use crate::deep_link;
#[cfg(desktop)]
use crate::window_restore::focus_main_window;
#[cfg(target_os = "macos")]
use crate::window_restore::focus_primary_window;

/// Handle a single `RunEvent`. The `_app_handle` / `_event` parameters
/// are prefixed with `_` because non-desktop builds don't read them.
pub(crate) fn handle_run_event(_app_handle: &tauri::AppHandle, _event: tauri::RunEvent) {
    // Implicit cancel-on-quit: flip every sync arm's cancel flag so an
    // in-flight filesystem-bridge / snapshot import / export
    // loop unwinds at its next probe instead of dragging shutdown out
    // behind an unbounded network round-trip. Read-side already exists
    // in every long-running loop (see `commands/sync/runtime/cancel_signal.rs`);
    // this is the only production caller for the global hammer.
    if matches!(_event, tauri::RunEvent::Exit) {
        crate::commands::request_cancel_all();
    }

    // Deep link handling: RunEvent::Opened fires on macOS via the
    // registered CFBundleURLTypes (Info.plist). On Windows, this requires
    // `tauri-plugin-deep-link` to register the URL scheme with the OS
    // registry (#1808 — already wired in plugins.rs).
    #[cfg(desktop)]
    if let tauri::RunEvent::Opened { ref urls } = _event {
        let mut needs_main_window = false;
        for url in urls {
            match deep_link::parse_opened_url_result(url) {
                Ok(Some(target)) => {
                    needs_main_window = true;
                    deep_link::enqueue_pending(target.clone());
                    let _ = _app_handle.emit(deep_link::DEEP_LINK_OPEN_EVENT, target.to_payload());
                }
                Ok(None) => {}
                Err(error) => {
                    deep_link::append_deep_link_log(
                        "warn",
                        "opened_url",
                        "ignored malformed deep link URL",
                        Some(format!("url={url} error={error}")),
                    );
                }
            }
        }

        if needs_main_window {
            focus_main_window(_app_handle, "deep_link_opened");
        }
    }

    #[cfg(target_os = "macos")]
    if let tauri::RunEvent::Reopen { .. } = _event {
        // Always route Dock reopen through the full restore pipeline so
        // retries/hard-recover remain available for intermittent races.
        focus_primary_window(_app_handle, "dock_reopen");
    }
}
