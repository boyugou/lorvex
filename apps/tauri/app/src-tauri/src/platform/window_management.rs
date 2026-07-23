//! Platform-specific window management for auxiliary windows.
//!
//! - macOS: NSWindow collection behavior + window levels (implemented)
//! - Windows: Tauri's always_on_top + visible_on_all_workspaces (basic)
//! - Linux: Tauri's always_on_top + visible_on_all_workspaces (basic)
//! - Mobile: no auxiliary window management (single-window navigation)

use tauri::WebviewWindow;

#[cfg(desktop)]
use crate::error::AppError;
use crate::error::AppResult;

/// Apply platform-specific workspace and stacking policy to an auxiliary window.
#[cfg(target_os = "macos")]
pub(crate) fn apply_workspace_policy(
    window: &WebviewWindow,
    visible_on_all_workspaces: bool,
    fullscreen_auxiliary: bool,
) -> AppResult<()> {
    window
        .set_visible_on_all_workspaces(visible_on_all_workspaces)
        .map_err(AppError::from)?;

    set_fullscreen_auxiliary(window, fullscreen_auxiliary)
}

#[cfg(target_os = "macos")]
fn set_fullscreen_auxiliary(window: &WebviewWindow, enabled: bool) -> AppResult<()> {
    use objc2_app_kit::{
        NSFloatingWindowLevel, NSNormalWindowLevel, NSWindow, NSWindowCollectionBehavior,
    };

    let ns_window_ptr = window.ns_window().map_err(AppError::from)?;
    if ns_window_ptr.is_null() {
        return Ok(());
    }

    // NSWindow APIs (`setCollectionBehavior`,
    // `setLevel`, `makeKeyAndOrderFront`) are main-thread-only AppKit
    // calls. Tauri command handlers run on a thread pool, so we must
    // dispatch the unsafe AppKit work to the main thread. Under Debug
    // an off-thread call trips AppKit's threading assertions and aborts
    // the process; under Release it silently corrupts window state
    // (wrong z-order, wrong collection-behavior bits, intermittent UI
    // glitches that look like driver issues).
    //
    // `*mut NSWindow` is `!Send`, but the underlying address is a
    // process-wide pointer that the WebviewWindow keeps alive for the
    // duration of this synchronous dispatch. Send the raw address as
    // `usize` and reconstitute `&NSWindow` on the main thread.
    let ns_window_addr = ns_window_ptr as usize;
    // Bound the rendezvous wait at 2 s and warn-log on timeout so a
    // wedged AppKit main loop (modal dialog, zombie autoresize
    // cycle, hung NSWindow delegate) can't park the calling Tauri
    // IPC pool thread indefinitely. Unbounded `rx.recv()` would let
    // a steady stream of focus-mode toggles exhaust the IPC pool
    // and lock the app up with no diagnostic.
    let (tx, rx) = std::sync::mpsc::sync_channel::<()>(1);

    window
        .run_on_main_thread(move || {
            // SAFETY: We hold a reference to the WebviewWindow on the
            // calling thread for the entire duration of `rx.recv()`
            // below, so the NSWindow at `ns_window_addr` cannot be
            // freed while this closure runs.
            let ns_window: &NSWindow = unsafe { &*(ns_window_addr as *const NSWindow) };
            let mut behavior = ns_window.collectionBehavior();
            if enabled {
                behavior.insert(NSWindowCollectionBehavior::CanJoinAllSpaces);
                behavior.insert(NSWindowCollectionBehavior::FullScreenAuxiliary);
                ns_window.setCollectionBehavior(behavior);
                // Use NSFloatingWindowLevel instead of NSStatusWindowLevel so
                // that the macOS IME candidate window can render above the
                // popover. NSStatusWindowLevel (25) suppresses IME candidate
                // positioning because the text-input system treats it as a
                // non-input status bar.
                ns_window.setLevel(NSFloatingWindowLevel);
                ns_window.makeKeyAndOrderFront(None);
            } else {
                behavior.remove(NSWindowCollectionBehavior::CanJoinAllSpaces);
                behavior.remove(NSWindowCollectionBehavior::FullScreenAuxiliary);
                ns_window.setCollectionBehavior(behavior);
                ns_window.setLevel(NSNormalWindowLevel);
            }
            // Bounded capacity-1: tx never blocks (recv side may
            // have given up on timeout). `try_send` is unnecessary —
            // a single-slot SyncSender is non-blocking once we
            // guarantee no second send.
            let _ = tx.send(());
        })
        .map_err(|e| {
            AppError::Internal(format!(
                "window_management: dispatch to main thread failed: {e}"
            ))
        })?;

    // Block until the main-thread closure completes — but bounded at
    // 2 s. Without this wait, the function returns
    // before the AppKit state changes are visible to the next AppKit
    // call, defeating the explicit ordering the public callers rely
    // on (e.g. set behavior, then immediately re-read it for
    // diagnostics). Without the BOUND, a wedged main loop would hold
    // the IPC pool thread indefinitely.
    match rx.recv_timeout(std::time::Duration::from_secs(2)) {
        Ok(()) => {}
        Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
            if let Ok(conn) = crate::db::get_conn() {
                let _ = crate::commands::diagnostics::append_error_log_internal(
                    &conn,
                    "platform.window_management",
                    "main-thread AppKit dispatch did not complete within 2s; window state may be stale",
                    None,
                    Some("warn".to_string()),
                );
            }
        }
        Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
            // Sender was dropped before sending — the dispatched
            // closure either panicked or was never scheduled. Nothing
            // we can do here; the next AppKit call will surface the
            // stale state if it matters.
        }
    }

    Ok(())
}

/// Windows and Linux: use Tauri's cross-platform always_on_top + visible_on_all_workspaces.
/// For more advanced control:
/// - Windows: IVirtualDesktopManager for virtual desktop pinning (`windows` crate)
/// - Linux: _NET_WM_STATE X11 hints or Wayland layer-shell
#[cfg(any(target_os = "windows", target_os = "linux"))]
pub(crate) fn apply_workspace_policy(
    window: &WebviewWindow,
    visible_on_all_workspaces: bool,
    _fullscreen_auxiliary: bool,
) -> AppResult<()> {
    if visible_on_all_workspaces {
        // Log `set_visible_on_all_workspaces` failures through the
        // same `error_logs` channel the macOS arm uses for
        // dispatch-timeout diagnostics. A failing call on KDE/X11
        // (e.g. WM doesn't honor `_NET_WM_STATE_STICKY`) leaves the
        // auxiliary window stuck on one workspace; a bare `let _ =`
        // swallow would lose the diagnostic entirely because
        // production builds never see stderr.
        if let Err(err) = window.set_visible_on_all_workspaces(visible_on_all_workspaces) {
            if let Ok(conn) = crate::db::get_conn() {
                let _ = crate::commands::diagnostics::append_error_log_internal(
                    &conn,
                    "platform.window_management",
                    "set_visible_on_all_workspaces failed; auxiliary-window state may be missing",
                    Some(err.to_string()),
                    Some("warn".to_string()),
                );
            }
        }
    }
    Ok(())
}

/// Mobile: no auxiliary window management — mobile UIs use single-window navigation.
#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
pub(crate) fn apply_workspace_policy(
    _window: &WebviewWindow,
    _visible_on_all_workspaces: bool,
    _fullscreen_auxiliary: bool,
) -> AppResult<()> {
    Ok(())
}
