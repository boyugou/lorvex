//! Quick-capture popover window hide IPC.

use crate::error::AppResult;

#[cfg(desktop)]
use crate::window_space::{
    apply_auxiliary_window_space_state, AuxiliaryWindowKind, AuxiliaryWindowState,
};
#[cfg(desktop)]
use tauri::Manager;

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn hide_popover_window(app: tauri::AppHandle) -> Result<(), String> {
    let result = (|| -> AppResult<()> {
        #[cfg(desktop)]
        if let Some(popover) = app.get_webview_window("popover") {
            apply_auxiliary_window_space_state(
                &popover,
                AuxiliaryWindowKind::Popover,
                AuxiliaryWindowState::Hidden,
            )?;
            popover.hide()?;
        }

        #[cfg(not(desktop))]
        {
            let _ = app;
        }

        Ok(())
    })();

    result.map_err(String::from)
}
