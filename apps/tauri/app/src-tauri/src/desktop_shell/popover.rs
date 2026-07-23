use super::*;
use crate::error::AppResult;

pub(super) const POPOVER_WINDOW_LABEL: &str = "popover";
pub(super) const POPOVER_WINDOW_HASH_ROUTE: &str = "index.html#popover";
pub(super) const POPOVER_WINDOW_TITLE: &str = "Lorvex Popover";
pub(super) const POPOVER_WINDOW_WIDTH: f64 = 380.0;
pub(super) const POPOVER_WINDOW_HEIGHT: f64 = 420.0;

fn attach_popover_close_to_hide(app: &tauri::AppHandle, popover: &tauri::WebviewWindow) {
    let app_handle = app.clone();
    popover.on_window_event(move |event| {
        if let tauri::WindowEvent::CloseRequested { api, .. } = event {
            api.prevent_close();
            if let Err(error) = hide_popover_window(app_handle.clone()) {
                append_desktop_shell_log(
                    "warn",
                    "popover.close_to_hide",
                    "popover close-to-hide failed",
                    Some(format!("error={error}")),
                );
            }
        }
    });
}

pub(super) fn ensure_popover_window(app: &tauri::AppHandle) -> AppResult<tauri::WebviewWindow> {
    if let Some(popover) = app.get_webview_window(POPOVER_WINDOW_LABEL) {
        return Ok(popover);
    }

    let popover = tauri::WebviewWindowBuilder::new(
        app,
        POPOVER_WINDOW_LABEL,
        tauri::WebviewUrl::App(POPOVER_WINDOW_HASH_ROUTE.into()),
    )
    .title(POPOVER_WINDOW_TITLE)
    .inner_size(POPOVER_WINDOW_WIDTH, POPOVER_WINDOW_HEIGHT)
    .resizable(false)
    .decorations(false)
    .shadow(false)
    .always_on_top(true)
    .visible(false)
    .build()?;

    attach_popover_close_to_hide(app, &popover);
    Ok(popover)
}

pub(crate) fn install_popover_close_to_hide(app: &tauri::App) {
    let Some(popover) = app.get_webview_window(POPOVER_WINDOW_LABEL) else {
        return;
    };

    let app_handle = app.handle().clone();
    attach_popover_close_to_hide(&app_handle, &popover);
}

/// When the main window gains focus, hide the popover so it doesn't linger.
/// On macOS, `tauri://blur` may not fire reliably for the popover when the user
/// clicks another window **in the same app** (the floating popover keeps its
/// window level and macOS does not always resign key status).  Listening for
/// `Focused(true)` on the main window is the reliable cross-platform path.
pub(crate) fn install_popover_dismiss_on_main_focus(app: &tauri::App) {
    let Some(main) = app.get_webview_window("main") else {
        return;
    };

    let app_handle = app.handle().clone();
    main.on_window_event(move |event| {
        if let tauri::WindowEvent::Focused(true) = event {
            if let Err(error) = hide_popover_window(app_handle.clone()) {
                append_desktop_shell_log(
                    "warn",
                    "popover.dismiss_on_main_focus",
                    "popover dismiss on main focus failed",
                    Some(format!("error={error}")),
                );
            }
        }
    });
}

pub(crate) fn hide_auxiliary_desktop_windows(app: &tauri::AppHandle) {
    if let Err(error) = hide_popover_window(app.clone()) {
        append_desktop_shell_log(
            "warn",
            "popover.auxiliary_hide",
            "auxiliary popover hide failed",
            Some(format!("error={error}")),
        );
    }
}
