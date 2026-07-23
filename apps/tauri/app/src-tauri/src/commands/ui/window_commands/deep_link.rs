//! Main-window deep-link IPC.
//!
//! `open_main_quick_capture` / `open_main_task_detail` re-focus the
//! main window and enqueue a target the renderer will dequeue once it's
//! ready. The renderer drives the queue via the `consume` /
//! `acknowledge` pair so a payload that arrives mid-startup (before the
//! deep-link listener has mounted) is replayed on the renderer's first
//! poll instead of being dropped.

use tauri::Emitter;

use crate::error::{AppError, AppResult};
#[cfg(desktop)]
use crate::window_restore::focus_main_window;

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn open_main_quick_capture(app: tauri::AppHandle) -> Result<(), String> {
    let result = (|| -> AppResult<()> {
        #[cfg(desktop)]
        focus_main_window(&app, "open_main_quick_capture");
        let target = crate::deep_link::DeepLinkTarget::QuickCapture;
        crate::deep_link::enqueue_pending(target.clone());
        app.emit(crate::deep_link::DEEP_LINK_OPEN_EVENT, target.to_payload())
            .map_err(|e| {
                AppError::Internal(format!(
                    "emit {}: {e}",
                    crate::deep_link::DEEP_LINK_OPEN_EVENT
                ))
            })?;
        Ok(())
    })();

    result.map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn open_main_task_detail(app: tauri::AppHandle, task_id: String) -> Result<(), String> {
    // validate UUID shape at the IPC boundary so a
    // malformed id never enters the deep-link queue or rides into the
    // task-detail panel selector on the renderer side. Mirrors the
    // pattern M1 already established for sibling
    // task-id IPC handlers.
    let task_id = crate::commands::shared::validate_uuid_id(&task_id, "task_id")?;
    let result = (|| -> AppResult<()> {
        #[cfg(desktop)]
        focus_main_window(&app, "open_main_task_detail");
        let target = crate::deep_link::DeepLinkTarget::Task { task_id };
        crate::deep_link::enqueue_pending(target.clone());
        app.emit(crate::deep_link::DEEP_LINK_OPEN_EVENT, target.to_payload())
            .map_err(|e| {
                AppError::Internal(format!(
                    "emit {}: {e}",
                    crate::deep_link::DEEP_LINK_OPEN_EVENT
                ))
            })?;
        Ok(())
    })();

    result.map_err(String::from)
}

#[tauri::command]
pub fn consume_pending_deep_link() -> Option<crate::deep_link::DeepLinkTargetPayload> {
    crate::deep_link::take_pending_payload()
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn acknowledge_pending_deep_link(payload: crate::deep_link::DeepLinkTargetPayload) -> bool {
    crate::deep_link::acknowledge_pending_payload(&payload)
}
