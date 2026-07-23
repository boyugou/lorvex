#[cfg(target_os = "macos")]
use super::append_window_restore_log;
use crate::desktop_geometry::{
    centered_position_on_monitor, rect_overlaps_any_monitor, saturating_u32_to_i32, MonitorRect,
};
use crate::error::{AppError, AppResult};
use crate::window_space::{
    apply_auxiliary_window_space_state, AuxiliaryWindowKind, AuxiliaryWindowState,
};
#[cfg(target_os = "macos")]
use tauri::WebviewWindow;
use tauri::{AppHandle, Manager, WebviewWindow as TauriWebviewWindow};

/// Minimum sane window dimensions. If the persisted
/// geometry comes back below this, the window-state plugin almost
/// certainly captured a degenerate state (e.g. window-saver fired
/// while the window was being hidden / minimized), so we throw it
/// away and re-center on the primary monitor instead. Matches the
/// `min_inner_size` declared in `tauri.conf.json` for the main
/// window with a small safety margin.
const MAIN_WINDOW_MIN_WIDTH: u32 = 320;
const MAIN_WINDOW_MIN_HEIGHT: u32 = 240;
const MAIN_WINDOW_DEFAULT_WIDTH: u32 = 1100;
const MAIN_WINDOW_DEFAULT_HEIGHT: u32 = 720;

/// Sanity-check the persisted main-window geometry: width / height
/// above a sane minimum AND position overlaps SOME currently-attached
/// monitor. If either check fails, reset to a sensible default
/// centered on the primary monitor. See the
/// window-state plugin can persist degenerate state if it samples
/// the window mid-hide / mid-minimize on shutdown, and there is no
/// way for the user to recover a 0×0 or off-screen-only window
/// without editing `window-state.json` by hand.
fn validate_main_window_geometry(app: &AppHandle, window: &TauriWebviewWindow) {
    let Ok(size) = window.outer_size() else {
        return;
    };
    let Ok(pos) = window.outer_position() else {
        return;
    };

    let monitors: Vec<MonitorRect> = match app.available_monitors() {
        Ok(list) => list.iter().map(MonitorRect::from_tauri).collect(),
        Err(_) => return,
    };

    if monitors.is_empty() {
        return;
    }

    let width = saturating_u32_to_i32(size.width);
    let height = saturating_u32_to_i32(size.height);

    let too_small = size.width < MAIN_WINDOW_MIN_WIDTH || size.height < MAIN_WINDOW_MIN_HEIGHT;
    let off_screen = !rect_overlaps_any_monitor(pos.x, pos.y, width, height, &monitors);

    if !too_small && !off_screen {
        return;
    }

    let primary = match app.primary_monitor() {
        Ok(Some(monitor)) => MonitorRect::from_tauri(&monitor),
        _ => match monitors.first().copied() {
            Some(rect) => rect,
            None => return,
        },
    };

    let target_size = if too_small {
        tauri::PhysicalSize::new(MAIN_WINDOW_DEFAULT_WIDTH, MAIN_WINDOW_DEFAULT_HEIGHT)
    } else {
        size
    };
    let centered_size_w = saturating_u32_to_i32(target_size.width);
    let centered_size_h = saturating_u32_to_i32(target_size.height);
    let centered = centered_position_on_monitor(primary, centered_size_w, centered_size_h);

    if too_small {
        let _ = window.set_size(tauri::Size::Physical(target_size));
    }
    let _ = window.set_position(tauri::Position::Physical(centered));

    #[cfg(target_os = "macos")]
    append_window_restore_log(
        "warn",
        "Persisted main window geometry was invalid — reset to centered default",
        Some(format!(
            "size={}x{} pos=({},{}) too_small={} off_screen={}",
            size.width, size.height, pos.x, pos.y, too_small, off_screen
        )),
    );
}

#[cfg(target_os = "macos")]
fn demote_workspace_visibility_with_guard(window: &WebviewWindow, stage: &'static str) -> bool {
    let _ = window.set_visible_on_all_workspaces(false);

    let mut is_visible = window.is_visible().unwrap_or(false);
    let mut is_minimized = window.is_minimized().unwrap_or(false);
    let mut is_focused = window.is_focused().unwrap_or(false);

    if !is_visible || is_minimized || !is_focused {
        append_window_restore_log(
            "warn",
            "Workspace demotion degraded restored main window state",
            Some(format!(
                "stage={stage} visible={is_visible} minimized={is_minimized} focused={is_focused}"
            )),
        );

        let _ = window.set_visible_on_all_workspaces(true);
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();

        is_visible = window.is_visible().unwrap_or(false);
        is_minimized = window.is_minimized().unwrap_or(false);
        is_focused = window.is_focused().unwrap_or(false);

        if !is_visible || is_minimized || !is_focused {
            append_window_restore_log(
                "warn",
                "Workspace demotion recovery failed to restore stable main window state",
                Some(format!(
                    "stage={stage} visible={is_visible} minimized={is_minimized} focused={is_focused}"
                )),
            );
        }
    }

    is_visible && !is_minimized && is_focused
}

#[cfg(target_os = "macos")]
fn verify_restored_main_window(
    window: &WebviewWindow,
    stage: &'static str,
    warning_message: &str,
    workspace_demote_stage: &'static str,
) -> bool {
    let mut is_visible = window.is_visible().unwrap_or(false);
    let mut is_minimized = window.is_minimized().unwrap_or(false);
    let mut is_focused = window.is_focused().unwrap_or(false);

    if !is_focused {
        let _ = window.set_always_on_top(true);
        let _ = window.set_focus();
        let _ = window.set_always_on_top(false);
        is_visible = window.is_visible().unwrap_or(false);
        is_minimized = window.is_minimized().unwrap_or(false);
        is_focused = window.is_focused().unwrap_or(false);
    }

    if !is_visible || is_minimized || !is_focused {
        append_window_restore_log(
            "warn",
            warning_message,
            Some(format!(
                "stage={stage} visible={is_visible} minimized={is_minimized} focused={is_focused}"
            )),
        );
        return false;
    }

    demote_workspace_visibility_with_guard(window, workspace_demote_stage)
}

pub(crate) fn restore_main_window_direct(app: &AppHandle) -> AppResult<()> {
    #[cfg(target_os = "macos")]
    if let Err(error) = app.show() {
        append_window_restore_log(
            "warn",
            "App show failed while restoring main window",
            Some(format!("stage=restore_main_direct error={error}")),
        );
    }

    let Some(window) = app.get_webview_window("main") else {
        return Err(AppError::NotFound("Main window not found".to_string()));
    };

    #[cfg(target_os = "macos")]
    let _ = window.set_visible_on_all_workspaces(true);

    window.show()?;
    window.unminimize()?;
    window.set_focus()?;

    // now that the window is on-screen and unminimized,
    // re-validate its persisted geometry. If the window-state plugin
    // restored a degenerate size or an off-screen position (e.g. an
    // external display was unplugged between sessions), reset to a
    // centered default on the primary monitor. Done AFTER `show()` so
    // the size/position reads reflect what the OS actually applied,
    // not what was queued up pre-display.
    validate_main_window_geometry(app, &window);

    Ok(())
}

fn hide_popover_for_window_restore(app: &AppHandle) {
    if let Some(popover) = app.get_webview_window("popover") {
        let _ = apply_auxiliary_window_space_state(
            &popover,
            AuxiliaryWindowKind::Popover,
            AuxiliaryWindowState::Hidden,
        );
        let _ = popover.hide();
    }
}

pub(in crate::window_restore) fn restore_main_window_once(app: &AppHandle) -> bool {
    hide_popover_for_window_restore(app);

    if let Err(error) = restore_main_window_direct(app) {
        append_window_restore_log(
            "warn",
            "Main window restore failed",
            Some(format!("stage=restore_once error={error}")),
        );
    }

    if let Some(_window) = app.get_webview_window("main") {
        #[cfg(target_os = "macos")]
        {
            return verify_restored_main_window(
                &_window,
                "restore_once",
                "Main window not fully restored after restore attempt",
                "restore_once_workspace_demote",
            );
        }

        #[cfg(not(target_os = "macos"))]
        {
            return true;
        }
    }

    false
}

#[cfg(target_os = "macos")]
pub(in crate::window_restore) fn hard_recover_main_window(app: &AppHandle) {
    hide_popover_for_window_restore(app);

    if let Err(error) = restore_main_window_direct(app) {
        append_window_restore_log(
            "error",
            "Main window hard-recover restore failed",
            Some(format!("stage=hard_recover error={error}")),
        );
    }

    let Some(window) = app.get_webview_window("main") else {
        append_window_restore_log(
            "error",
            "Main window hard-recover failed because main window is missing",
            Some("stage=hard_recover".to_string()),
        );
        return;
    };

    #[cfg(target_os = "macos")]
    {
        let _ = verify_restored_main_window(
            &window,
            "hard_recover",
            "Main window hard-recover incomplete",
            "hard_recover_workspace_demote",
        );
    }
}
