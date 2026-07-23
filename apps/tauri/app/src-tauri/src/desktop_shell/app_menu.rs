use tauri::{
    menu::{
        AboutMetadataBuilder, CheckMenuItemBuilder, Menu, MenuItemBuilder, Submenu, SubmenuBuilder,
    },
    AppHandle, Emitter, Manager, Wry,
};

use super::append_desktop_shell_log;
use crate::event_channels;
use crate::menu_i18n::{self, MenuKey};
use crate::window_restore::focus_main_window;

/// Route every Help-menu URL miss into the diagnostics surface so
/// support-thread triage can distinguish "user didn't click" from
/// "click did nothing". A bare `let _ = tauri_plugin_opener::open_url(...)`
/// would silently swallow opener failures (sandboxed env, missing
/// default browser, malformed URL).
fn open_help_url(_app: &tauri::AppHandle, menu_id: &str, url: &str) {
    if let Err(error) = tauri_plugin_opener::open_url(url, None::<&str>) {
        append_desktop_shell_log(
            "warn",
            "menu.open_help_url",
            "help menu URL open failed",
            Some(format!("menu_id={menu_id} url={url} error={error}")),
        );
    }
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
pub(crate) fn handle_menu_event(app: &tauri::AppHandle, event: tauri::menu::MenuEvent) {
    let id = event.id().as_ref();
    match id {
        // View navigation
        "view_today" | "view_upcoming" | "view_all" | "view_ai_changelog" | "view_calendar"
        | "view_eisenhower" | "view_kanban" | "view_someday" | "view_memory" | "view_review"
        | "view_daily_review" | "view_habits" | "view_dependencies" | "view_recurring" => {
            let view_type = id.strip_prefix("view_").unwrap_or(id);
            let _ = app.emit(event_channels::MENU_NAVIGATE, view_type);
        }
        "settings" => {
            let _ = app.emit(event_channels::MENU_NAVIGATE, "settings");
        }
        // Quick capture (toggle via frontend, not deep link, so Cmd+N can close too)
        "quick_capture" => {
            focus_main_window(app, "menu_quick_capture");
            let _ = app.emit(event_channels::MENU_QUICK_CAPTURE, ());
        }
        "command_palette" => {
            let _ = app.emit(event_channels::MENU_COMMAND_PALETTE, ());
        }
        "enter_focus" => {
            let _ = app.emit(event_channels::MENU_ENTER_FOCUS, ());
        }
        // Always on top — toggle on the main window and sync the menu checkbox
        "toggle_always_on_top" => {
            if let Some(main) = app.get_webview_window("main") {
                let is_on_top = main.is_always_on_top().unwrap_or(false);
                let new_state = !is_on_top;
                let _ = main.set_always_on_top(new_state);
                // Sync the CheckMenuItem to reflect the new state
                if let Some(menu) = app.menu() {
                    sync_always_on_top_menu_item(&menu, new_state);
                }
            }
        }
        "export_data" => {
            let _ = app.emit(event_channels::MENU_EXPORT_DATA, ());
        }
        "import_data" => {
            let _ = app.emit(event_channels::MENU_IMPORT_DATA, ());
        }
        "check_updates" => {
            let _ = app.emit(event_channels::MENU_CHECK_UPDATES, ());
        }
        "open_help" => {
            open_help_url(app, id, "https://github.com/boyugou/ai-native-todo");
        }
        "open_help_getting_started" => {
            open_help_url(
                app,
                id,
                "https://github.com/boyugou/ai-native-todo/blob/main/docs/setup/GETTING_STARTED.md",
            );
        }
        "open_help_mcp_setup" => {
            open_help_url(
                app,
                id,
                "https://github.com/boyugou/ai-native-todo/blob/main/docs/setup/ASSISTANT_MCP_SETUP.md",
            );
        }
        "open_help_shortcuts" => {
            // Emits an event the frontend's existing `?` shortcut
            // listener picks up. The menu entry surfaces the
            // Keyboard Shortcuts panel for users who don't know
            // about the `?` accelerator.
            let _ = app.emit(event_channels::MENU_OPEN_SHORTCUTS, ());
        }
        "open_help_report_issue" => {
            open_help_url(
                app,
                id,
                "https://github.com/boyugou/ai-native-todo/issues/new",
            );
        }
        _ => {}
    }
}

pub(crate) fn build_app_menu(app: &AppHandle<Wry>) -> tauri::Result<Menu<Wry>> {
    let locale = menu_i18n::preferred_locale();
    let t = |key: MenuKey| menu_i18n::t(&locale, key);
    let app_menu = app_submenu(app, &t)?;
    let file_menu = file_submenu(app, &t)?;
    let edit_menu = edit_submenu(app, &t)?;
    let view_menu = view_submenu(app, &t)?;
    let window_menu = window_submenu(app, &t)?;
    let help_menu = help_submenu(app, &t)?;

    Menu::with_items(
        app,
        &[
            &app_menu,
            &file_menu,
            &edit_menu,
            &view_menu,
            &window_menu,
            &help_menu,
        ],
    )
}

fn app_submenu(
    app: &AppHandle<Wry>,
    t: &dyn Fn(MenuKey) -> &'static str,
) -> tauri::Result<Submenu<Wry>> {
    let about_metadata = AboutMetadataBuilder::new()
        .name(Some("Lorvex"))
        .version(Some(env!("CARGO_PKG_VERSION")))
        .copyright(Some("Copyright (c) 2025-2026 Lorvex"))
        .license(Some("Apache-2.0"))
        .build();

    SubmenuBuilder::new(app, t(MenuKey::AppMenu))
        .about(Some(about_metadata))
        .separator()
        .item(&MenuItemBuilder::with_id("check_updates", t(MenuKey::CheckForUpdates)).build(app)?)
        .separator()
        .item(
            &MenuItemBuilder::with_id("settings", t(MenuKey::Settings))
                // CmdOrCtrl+, is the macOS "Preferences"
                // convention, but on Windows users expect Ctrl+; (the
                // Electron convention). Pick the platform-idiomatic
                // binding at compile time — Tauri's accelerator parser
                // doesn't support a runtime-branched string.
                .accelerator(if cfg!(target_os = "macos") {
                    "CmdOrCtrl+,"
                } else {
                    "CmdOrCtrl+;"
                })
                .build(app)?,
        )
        .separator()
        .services()
        .separator()
        .hide()
        .hide_others()
        .show_all()
        .separator()
        .quit()
        .build()
}

fn file_submenu(
    app: &AppHandle<Wry>,
    t: &dyn Fn(MenuKey) -> &'static str,
) -> tauri::Result<Submenu<Wry>> {
    SubmenuBuilder::new(app, t(MenuKey::FileMenu))
        .item(
            &MenuItemBuilder::with_id("quick_capture", t(MenuKey::NewTask))
                .accelerator("CmdOrCtrl+N")
                .build(app)?,
        )
        .separator()
        .item(&MenuItemBuilder::with_id("export_data", t(MenuKey::ExportData)).build(app)?)
        .item(&MenuItemBuilder::with_id("import_data", t(MenuKey::ImportData)).build(app)?)
        .separator()
        .close_window()
        .build()
}

fn edit_submenu(
    app: &AppHandle<Wry>,
    t: &dyn Fn(MenuKey) -> &'static str,
) -> tauri::Result<Submenu<Wry>> {
    // the predefined `.undo()` / `.redo()` builders have no
    // menu IDs, so their accelerators (`⌘Z` / `⇧⌘Z`) route through the
    // native responder chain instead of `handle_menu_event`. We bind
    // `⌘Z` in JS (`DesktopMainWindow.tsx`) for task-level undo, and
    // the JS handler falls back to `document.execCommand('undo')`
    // when focus is inside a text field (see `shouldIgnoreShortcut`
    // in `DesktopMainWindow.tsx`). Keeping the native menu items in
    // place left ambiguous event ordering — `preventDefault` in JS
    // doesn't reliably suppress the responder chain on every
    // WebKit/WebView2 version. Drop the built-in items so ⌘Z is
    // unambiguously owned by the JS layer.
    //
    // `.cut()` / `.copy()` / `.paste()` / `.select_all()` stay — they
    // have no conflicting JS bindings and the native macOS clipboard
    // flow is still the right path.
    SubmenuBuilder::new(app, t(MenuKey::EditMenu))
        .cut()
        .copy()
        .paste()
        .select_all()
        .separator()
        .item(
            &MenuItemBuilder::with_id("command_palette", t(MenuKey::Find))
                .accelerator("CmdOrCtrl+K")
                .build(app)?,
        )
        .build()
}

fn view_submenu(
    app: &AppHandle<Wry>,
    t: &dyn Fn(MenuKey) -> &'static str,
) -> tauri::Result<Submenu<Wry>> {
    // Navigation shortcuts cover every sidebar destination via a
    // derivable end-to-end scheme: primary views occupy the ⌘1–⌘4
    // row, secondary views take ⌘5–⌘0 in a stable order, and the
    // remaining permanent modules get ⌘⇧-letter bindings. The
    // exact mapping is mirrored in `secondaryModules.tsx` (sidebar)
    // and `KeyboardShortcutsPanel.tsx` (reference panel); keep all
    // three in sync.
    //
    // On non-macOS, Ctrl+0 is WebView2's "reset zoom" and gets
    // swallowed before reaching the Tauri menu, so Daily Review
    // routes through a CmdOrCtrl+Shift+0 remap on that platform.
    SubmenuBuilder::new(app, t(MenuKey::ViewMenu))
        // Primary row ⌘1 – ⌘4
        .item(
            &MenuItemBuilder::with_id("view_today", t(MenuKey::Today))
                .accelerator("CmdOrCtrl+1")
                .build(app)?,
        )
        .item(
            &MenuItemBuilder::with_id("view_upcoming", t(MenuKey::Next7Days))
                .accelerator("CmdOrCtrl+2")
                .build(app)?,
        )
        .item(
            &MenuItemBuilder::with_id("view_all", t(MenuKey::AllTasks))
                .accelerator("CmdOrCtrl+3")
                .build(app)?,
        )
        .item(
            &MenuItemBuilder::with_id("view_someday", t(MenuKey::Someday))
                .accelerator("CmdOrCtrl+4")
                .build(app)?,
        )
        .separator()
        // Secondary digit row ⌘5 – ⌘0
        .item(
            &MenuItemBuilder::with_id("view_calendar", t(MenuKey::Calendar))
                .accelerator("CmdOrCtrl+5")
                .build(app)?,
        )
        .item(
            &MenuItemBuilder::with_id("view_eisenhower", t(MenuKey::EisenhowerMatrix))
                .accelerator("CmdOrCtrl+6")
                .build(app)?,
        )
        .item(
            &MenuItemBuilder::with_id("view_kanban", t(MenuKey::KanbanBoard))
                .accelerator("CmdOrCtrl+7")
                .build(app)?,
        )
        .item(
            &MenuItemBuilder::with_id("view_habits", t(MenuKey::Habits))
                .accelerator("CmdOrCtrl+8")
                .build(app)?,
        )
        .item(
            &MenuItemBuilder::with_id("view_daily_review", t(MenuKey::DailyReview))
                .accelerator("CmdOrCtrl+9")
                .build(app)?,
        )
        .separator()
        // Secondary ⌘⇧-letter row
        .item(
            &MenuItemBuilder::with_id("view_memory", t(MenuKey::AiMemory))
                .accelerator("Shift+CmdOrCtrl+M")
                .build(app)?,
        )
        .item(
            &MenuItemBuilder::with_id("view_dependencies", t(MenuKey::Dependencies))
                .accelerator("Shift+CmdOrCtrl+D")
                .build(app)?,
        )
        .item(
            &MenuItemBuilder::with_id("view_ai_changelog", t(MenuKey::AiActivity))
                .accelerator("Shift+CmdOrCtrl+A")
                .build(app)?,
        )
        .item(
            &MenuItemBuilder::with_id("view_review", t(MenuKey::WeeklyReview))
                .accelerator("Shift+CmdOrCtrl+W")
                .build(app)?,
        )
        .item(
            // power-user index of every recurring task
            // rule. ⌘⇧R is otherwise unused in the nav row; the letter
            // cleanly maps to "Recurring".
            &MenuItemBuilder::with_id("view_recurring", t(MenuKey::Recurring))
                .accelerator("Shift+CmdOrCtrl+R")
                .build(app)?,
        )
        .separator()
        .item(
            &MenuItemBuilder::with_id("enter_focus", t(MenuKey::FocusMode))
                .accelerator("Shift+CmdOrCtrl+F")
                .build(app)?,
        )
        .separator()
        .fullscreen()
        .build()
}

fn window_submenu(
    app: &AppHandle<Wry>,
    t: &dyn Fn(MenuKey) -> &'static str,
) -> tauri::Result<Submenu<Wry>> {
    SubmenuBuilder::new(app, t(MenuKey::WindowMenu))
        .minimize()
        .maximize()
        .separator()
        .item(
            &CheckMenuItemBuilder::with_id("toggle_always_on_top", t(MenuKey::AlwaysOnTop))
                .build(app)?,
        )
        .separator()
        .close_window()
        .build()
}

fn help_submenu(
    app: &AppHandle<Wry>,
    t: &dyn Fn(MenuKey) -> &'static str,
) -> tauri::Result<Submenu<Wry>> {
    // Expose the most-asked-for docs directly: Getting Started
    // (first-run), Assistant MCP Setup (core value-prop wiring),
    // Keyboard Shortcuts (emits menu://open-shortcuts so the
    // frontend opens its existing ? panel), and Report an Issue
    // (direct link to the issue tracker). The "Lorvex Help" item
    // stays as the repo-root fallback so a user hunting for the MCP
    // setup guide or the keyboard-shortcut reference has a direct
    // entry point instead of the bare repo homepage.
    SubmenuBuilder::new(app, t(MenuKey::HelpMenu))
        .item(
            &MenuItemBuilder::with_id("open_help_getting_started", t(MenuKey::GettingStarted))
                .build(app)?,
        )
        .item(
            &MenuItemBuilder::with_id("open_help_mcp_setup", t(MenuKey::AssistantMcpSetup))
                .build(app)?,
        )
        .item(
            &MenuItemBuilder::with_id("open_help_shortcuts", t(MenuKey::KeyboardShortcuts))
                .accelerator("CmdOrCtrl+Shift+?")
                .build(app)?,
        )
        .separator()
        .item(
            &MenuItemBuilder::with_id("open_help_report_issue", t(MenuKey::ReportIssue))
                .build(app)?,
        )
        .separator()
        .item(&MenuItemBuilder::with_id("open_help", t(MenuKey::Help)).build(app)?)
        .build()
}

/// Sync the "Always on Top" CheckMenuItem to match the given state.
/// Called from the menu event handler and also exposed for programmatic
/// always-on-top changes (e.g. from IPC commands or window restore).
fn sync_always_on_top_menu_item(menu: &Menu<Wry>, is_on_top: bool) {
    use tauri::menu::MenuItemKind;

    fn walk_items(items: &[MenuItemKind<Wry>], is_on_top: bool) {
        for item in items {
            match item {
                MenuItemKind::Check(check) if check.id().as_ref() == "toggle_always_on_top" => {
                    let _ = check.set_checked(is_on_top);
                    return;
                }
                MenuItemKind::Submenu(sub) => {
                    if let Ok(children) = sub.items() {
                        walk_items(&children, is_on_top);
                    }
                }
                _ => {}
            }
        }
    }

    if let Ok(items) = menu.items() {
        walk_items(&items, is_on_top);
    }
}
