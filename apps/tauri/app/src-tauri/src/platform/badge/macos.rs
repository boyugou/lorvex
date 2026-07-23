//! macOS: NSApplication dock tile badge label.
//!
//! Dispatches the dock-tile mutation onto the main thread because
//! Tauri IPC runs on a worker pool and `MainThreadMarker::new()`
//! is the only sound way to obtain an `NSApplication` handle. The
//! main-thread dispatch is the AppKit invariant that lets us hand
//! the badge label to AppKit without touching it from a worker
//! thread.

pub(crate) fn set_count(count: Option<i64>, app: &tauri::AppHandle) -> Result<(), String> {
    use objc2_app_kit::NSApplication;

    // Dispatch to the main thread to safely obtain MainThreadMarker.
    // Tauri IPC commands run on a thread pool, so we cannot assume main-thread.
    let count = count.filter(|v| *v > 0);
    app.run_on_main_thread(move || {
        // SAFETY: This closure runs on the main thread, so MainThreadMarker::new() succeeds.
        let Some(mtm) = objc2::MainThreadMarker::new() else {
            return;
        };
        let ns_app = NSApplication::sharedApplication(mtm);
        let tile = ns_app.dockTile();

        if let Some(n) = count {
            let label = objc2_foundation::NSString::from_str(&n.to_string());
            tile.setBadgeLabel(Some(&label));
        } else {
            tile.setBadgeLabel(None);
        }
    })
    .map_err(|e| format!("badge: failed to dispatch to main thread: {e}"))
}
