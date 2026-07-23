use super::popover::ensure_popover_window;
use super::*;
use crate::error::{AppError, AppResult};
use crate::event_channels;
use crate::menu_i18n::{self, MenuKey};
use rusqlite::{Connection, OptionalExtension};

fn parse_menu_bar_icon_visible(raw: &str) -> Option<bool> {
    lorvex_domain::parse_json_bool_preference(Some(raw))
}

fn requested_tray_visibility_from_conn(conn: &Connection) -> AppResult<Option<bool>> {
    let raw = conn
        .query_row(
            "SELECT value FROM device_state WHERE key = ?1",
            rusqlite::params![lorvex_domain::preference_keys::DEV_MENU_BAR_ICON_VISIBLE],
            |row| row.get::<_, String>(0),
        )
        .optional()?;

    match raw {
        Some(value) => parse_menu_bar_icon_visible(&value)
            .map(Some)
            .ok_or_else(|| {
                AppError::Validation(
                    "menu_bar_icon_visible device_state must be a JSON boolean".to_string(),
                )
            }),
        None => Ok(None),
    }
}

pub(crate) fn setup_system_tray(app: &tauri::App) -> tauri::Result<()> {
    let locale = menu_i18n::preferred_locale();
    let open_item =
        MenuItemBuilder::with_id("open", menu_i18n::t(&locale, MenuKey::Open)).build(app)?;
    let capture_item = MenuItemBuilder::with_id(
        "quick_capture",
        menu_i18n::t(&locale, MenuKey::QuickCapture),
    )
    .build(app)?;
    let quit_item =
        MenuItemBuilder::with_id("quit", menu_i18n::t(&locale, MenuKey::Quit)).build(app)?;
    let menu = MenuBuilder::new(app)
        .items(&[&open_item, &capture_item, &quit_item])
        .build()?;

    // the macOS NSStatusItem renders the tooltip
    // string as the VoiceOver accessibility label — without it, VO
    // announces a generic "menu extra" with no app context and the
    // tray icon is effectively invisible to assistive-tech users.
    // "Lorvex" is the brand name (intentionally not localized) so VO
    // reads the same on every locale; longer descriptive labels
    // would noise-flood the menu-extras row VO sweeps left-to-right.
    let mut tray_builder = TrayIconBuilder::with_id("lorvex-tray")
        .menu(&menu)
        .tooltip("Lorvex")
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id().as_ref() {
            "open" => focus_primary_window(app, "tray_menu_open"),
            "quick_capture" => {
                focus_main_window(app, "tray_menu_quick_capture");
                let target = crate::deep_link::DeepLinkTarget::QuickCapture;
                crate::deep_link::enqueue_pending(target.clone());
                let _ = app.emit(crate::deep_link::DEEP_LINK_OPEN_EVENT, target.to_payload());
            }
            "quit" => {
                hide_auxiliary_desktop_windows(app);
                app.exit(0);
            }
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            // Handle both single-click and double-click on the tray icon.
            // Without handling DoubleClick explicitly, macOS performs its default
            // behavior of activating the main window on double-click.
            let rect = match event {
                TrayIconEvent::Click {
                    button: MouseButton::Left,
                    button_state: MouseButtonState::Up,
                    rect,
                    ..
                } => rect,
                TrayIconEvent::DoubleClick {
                    button: MouseButton::Left,
                    rect,
                    ..
                } => rect,
                _ => return,
            };

            let app = tray.app_handle();

            // Debounce: ignore clicks within 300ms of the last show to prevent
            // double-click flicker (Click -> show, DoubleClick -> immediate hide).
            //
            // `Ordering::Relaxed`
            // is correct here. The tray-icon callback runs on the OS
            // event-loop thread; a torn read of `LAST_SHOW_MS` would at
            // worst skip the debounce for a single tick (causing one
            // legitimate flicker) and a torn store would at worst hold
            // the debounce open for one extra tick. There is no shared
            // state whose visibility we need to order against this
            // counter, so a stronger ordering would buy nothing and
            // adds an unnecessary fence on the OS-callback hot path.
            use std::sync::atomic::{AtomicU64, Ordering};
            static LAST_SHOW_MS: AtomicU64 = AtomicU64::new(0);
            let now_ms = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64;

            let popover = match ensure_popover_window(app) {
                Ok(popover) => popover,
                Err(error) => {
                    append_desktop_shell_log(
                        "warn",
                        "tray.popover_ensure",
                        "tray popover ensure failed",
                        Some(format!("error={error}")),
                    );
                    return;
                }
            };

            // Toggle: if the popover is already visible, hide it.
            // Note: we check visibility only (not focus) because on macOS the
            // popover loses focus as soon as the user clicks the tray icon,
            // making an is_focused() check unreliable for toggle purposes.
            let is_visible = popover.is_visible().unwrap_or(false);
            if is_visible {
                // Don't hide if we just showed (prevents double-click flicker)
                let last_show = LAST_SHOW_MS.load(Ordering::Relaxed);
                if now_ms.saturating_sub(last_show) < 300 {
                    return;
                }
                if let Err(error) = hide_popover_window(app.clone()) {
                    append_desktop_shell_log(
                        "warn",
                        "tray.popover_hide",
                        "tray popover hide failed",
                        Some(format!("error={error}")),
                    );
                }
                return;
            }

            let source_rect = if let Some(r) = tray.rect().ok().flatten() {
                r
            } else {
                rect
            };
            let (tray_x, tray_y, tray_width, tray_height) = rect_to_physical_bounds(source_rect);
            let tray_anchor_x = tray_x + (tray_width / 2);
            let tray_anchor_y = tray_y + (tray_height / 2);

            // Use physical-coordinate containment check instead of
            // monitor_from_point (which expects logical coords on macOS,
            // causing wrong-monitor selection on Retina displays).
            let (popover_x, popover_y) = if let Some(monitor) =
                find_monitor_containing_physical_point(app, tray_anchor_x, tray_anchor_y)
            {
                let scale = monitor.scale_factor();
                clamp_tray_popover_position_to_monitor(
                    tray_x,
                    tray_y,
                    tray_width,
                    tray_height,
                    monitor.position().to_owned(),
                    monitor.size().to_owned(),
                    scale,
                )
            } else {
                (
                    (tray_x + tray_width
                        - TRAY_POPOVER_LOGICAL_WIDTH
                        - TRAY_POPOVER_LOGICAL_X_MARGIN)
                        .max(0),
                    (tray_y + tray_height + TRAY_POPOVER_LOGICAL_Y_MARGIN).max(0),
                )
            };

            let _ = popover.set_position(tauri::Position::Physical(tauri::PhysicalPosition::new(
                popover_x, popover_y,
            )));
            let _ = apply_auxiliary_window_space_state(
                &popover,
                AuxiliaryWindowKind::Popover,
                AuxiliaryWindowState::Presented,
            );
            // Activate the app process so the popover appears on the current
            // Space even when another app is fullscreen or Lorvex is backgrounded.
            #[cfg(target_os = "macos")]
            let _ = app.show();
            if let Err(error) = popover.show() {
                append_desktop_shell_log(
                    "warn",
                    "tray.popover_show",
                    "tray popover show failed",
                    Some(format!("error={error}")),
                );
                return;
            }
            LAST_SHOW_MS.store(now_ms, Ordering::Relaxed);
            let _ = popover.unminimize();
            let _ = popover.set_focus();
            let _ = app.emit(event_channels::TRAY_POPOVER_OPENED, ());
        });

    // macOS: monochrome template icon (inverts automatically for light/dark menu bar)
    // Linux: colored app icon — template icons have black fill, invisible on Ubuntu's
    //        default dark GNOME panel. Colored icon is visible on both light/dark panels.
    // Windows: colored app icon
    #[cfg(target_os = "macos")]
    {
        tray_builder = tray_builder
            .icon(tauri::include_image!("icons/menubar-template_44.png"))
            .icon_as_template(true);
    }
    #[cfg(not(target_os = "macos"))]
    {
        tray_builder = tray_builder.icon(tauri::include_image!("icons/128x128.png"));
    }

    let tray = tray_builder.build(app)?;
    let requested_tray_visible = {
        let Ok(pool) = db::get_db() else {
            return Ok(());
        };
        let conn = match pool.read_lock_result() {
            Ok(conn) => conn,
            Err(error) => {
                append_desktop_shell_log(
                    "warn",
                    "tray.visibility_read_lock",
                    "tray visibility preference read failed; falling back to visible tray icon",
                    Some(format!("error={error}")),
                );
                return Ok(());
            }
        };
        match requested_tray_visibility_from_conn(&conn) {
            Ok(Some(value)) => value,
            Ok(None) => true,
            Err(error) => {
                append_desktop_shell_log(
                    "warn",
                    "tray.visibility_preference",
                    "tray visibility preference invalid; falling back to visible tray icon",
                    Some(format!(
                        "key={} error={error}",
                        lorvex_domain::preference_keys::DEV_MENU_BAR_ICON_VISIBLE
                    )),
                );
                true
            }
        }
    };
    let tray_visible = if matches!(
        resolve_desktop_close_action(),
        DesktopCloseAction::HideToTray
    ) {
        true
    } else {
        requested_tray_visible
    };
    let _ = tray.set_visible(tray_visible);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{parse_menu_bar_icon_visible, requested_tray_visibility_from_conn};
    use crate::error::AppError;

    use crate::test_support::test_conn;

    #[test]
    fn parse_menu_bar_icon_visible_requires_json_bool() {
        assert_eq!(parse_menu_bar_icon_visible("true"), Some(true));
        assert_eq!(parse_menu_bar_icon_visible("false"), Some(false));
        assert_eq!(parse_menu_bar_icon_visible("\"true\""), None);
        assert_eq!(parse_menu_bar_icon_visible("1"), None);
    }

    #[test]
    fn requested_tray_visibility_from_conn_reads_canonical_device_state() {
        let conn = test_conn();
        conn.execute(
            "INSERT INTO device_state (key, value) VALUES (?1, ?2)",
            rusqlite::params![
                lorvex_domain::preference_keys::DEV_MENU_BAR_ICON_VISIBLE,
                "false"
            ],
        )
        .expect("insert tray visibility device state");

        assert_eq!(
            requested_tray_visibility_from_conn(&conn).expect("read tray visibility"),
            Some(false)
        );
    }

    #[test]
    fn requested_tray_visibility_from_conn_rejects_malformed_device_state() {
        let conn = test_conn();
        conn.execute(
            "INSERT INTO device_state (key, value) VALUES (?1, ?2)",
            rusqlite::params![
                lorvex_domain::preference_keys::DEV_MENU_BAR_ICON_VISIBLE,
                "\"false\""
            ],
        )
        .expect("insert malformed tray visibility device state");

        let error = requested_tray_visibility_from_conn(&conn)
            .expect_err("malformed tray visibility should fail");
        match error {
            AppError::Validation(message) => {
                assert!(
                    message.contains("menu_bar_icon_visible"),
                    "unexpected error: {message}"
                );
            }
            other => panic!("expected validation error, got {other:?}"),
        }
    }
}
