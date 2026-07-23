//! Tauri `setup` callback body.
//!
//! Centralized so `lib.rs::run` only needs to wire `.setup(setup_app)`
//! instead of inlining 70+ lines of platform-gated boot wiring.

use tauri::App;

use crate::db;
#[cfg(desktop)]
use crate::desktop_close_policy::install_main_close_to_hide;
#[cfg(desktop)]
use crate::desktop_shell::{
    build_app_menu, hide_auxiliary_desktop_windows, install_popover_close_to_hide,
    install_popover_dismiss_on_main_focus, setup_system_tray,
};
use crate::event_bus;
#[cfg(desktop)]
use crate::menu_i18n;
use crate::platform;

/// Non-desktop runtimes (Android) have no system tray; the
/// desktop tray module is `#[cfg(desktop)]`-gated, so this stub
/// keeps the setup callback platform-agnostic without polluting
/// `desktop_shell` with non-desktop concerns.
#[cfg(not(desktop))]
fn setup_system_tray(_app: &tauri::App) -> tauri::Result<()> {
    Ok(())
}

/// Bind every cross-cutting subsystem the app expects to be wired by
/// the time the first window is shown:
///
/// 1. Event bus app-handle so `event_bus::emit_*` works during setup.
/// 2. Translated notification action categories (locale comes from the
///    user's `language` preference; re-registered on language changes
///    via `commands::preferences::set_preference`).
/// 3. System tray + menu (desktop only).
/// 4. Close-to-hide policies for main / focus / popover.
/// 5. Auxiliary window visibility seed.
/// 6. macOS Spotlight reindex (no-op elsewhere).
/// 7. Pending-inbox drain startup pass.
pub(crate) fn setup_app(app: &mut App) -> Result<(), Box<dyn std::error::Error>> {
    // pin the process's AppUserModelID before
    // anything else touches the shell or broker so per-version install
    // churn doesn't reset Calendar / Hello permissions on every
    // upgrade. Must run before badge / spotlight / windows_calendar
    // make their first WinRT / shell call.
    #[cfg(target_os = "windows")]
    crate::platform::app_user_model_id::install();

    // initialize the DB pool (which runs `init_hlc`
    // synchronously) BEFORE wiring `event_bus::init`. The previous
    // order let the event-bus AppHandle land before HLC was ready;
    // any failure path between `event_bus::init` and the eventual
    // `db::get_db()` call could emit `lorvex://*` events from a process
    // whose HLC had no chance of having initialized — observable as
    // "data-changed" events with stale or missing version stamps. By
    // priming the pool here we guarantee HLC is live for every
    // subsequent emit.
    let _ = db::get_db();

    event_bus::init(app.handle().clone());

    #[cfg(desktop)]
    let startup_locale = menu_i18n::preferred_locale();
    #[cfg(not(desktop))]
    let startup_locale = String::from("en");
    platform::notification_actions::register_notification_categories(&startup_locale);
    platform::notification_actions::install_notification_delegate(app.handle().clone());

    setup_system_tray(app)?;

    #[cfg(desktop)]
    {
        let menu = build_app_menu(app.handle())?;
        app.set_menu(menu)?;
    }

    #[cfg(desktop)]
    install_main_close_to_hide(app);
    #[cfg(desktop)]
    install_popover_close_to_hide(app);
    #[cfg(desktop)]
    install_popover_dismiss_on_main_focus(app);

    #[cfg(desktop)]
    hide_auxiliary_desktop_windows(&app.handle().clone());

    // Index all tasks into macOS Spotlight (no-op on other
    // platforms). Runs on a background thread so app startup is not
    // blocked. On spawn failure (FD exhaustion at boot, ulimit on a
    // sandboxed launch) write a one-line `error_logs` row so a user
    // searching for tasks via Spotlight on macOS isn't left with an
    // empty result and no diagnostic surface. Discarding the spawn
    // error with `.ok()` would lose the signal entirely because
    // production builds discard stderr.
    if let Err(err) = std::thread::Builder::new()
        .name("spotlight-reindex".into())
        .spawn(|| {
            platform::spotlight::reindex_all_tasks();
        })
    {
        crate::commands::diagnostics::append_error_log_best_effort(
            "platform.spotlight",
            "failed to spawn spotlight-reindex thread; tasks will not appear in macOS Spotlight",
            Some(err.to_string()),
            Some("warn".to_string()),
        );
    }

    // parse the FIRST instance's argv for the
    // Jump List `--open-task <id>` deep-link. The single-instance
    // plugin handler only fires on second-instance launches, so a
    // cold-start launch via a Jump List shortcut needs its own
    // entry point. Enqueueing here (after `event_bus::init` so the
    // emit is observable) lets the renderer's `consume_pending_deep_link`
    // poll surface the navigation as soon as the React tree mounts.
    #[cfg(desktop)]
    {
        let argv: Vec<String> = std::env::args().collect();
        if let Some(payload) = crate::plugins::enqueue_open_task_from_argv(&argv) {
            use tauri::Emitter;
            let _ = app
                .handle()
                .emit(crate::deep_link::DEEP_LINK_OPEN_EVENT, payload);
        }
    }

    // kick off the background pending-inbox
    // drain AFTER `init_pool` has
    // definitively completed. Doing this from inside
    // `init_pool` (as the previous code did) would leave
    // the spawned thread blocked on `OnceLock::get_or_init`
    // forever if `init_pool` itself panicked. The `get_db()`
    // calls issued from earlier IPC handler registration
    // guarantee the pool is ready by the time setup
    // reaches this point; we also trigger an explicit
    // get_db() below to make the ordering obvious.
    let _ = db::get_db();
    db::schedule_startup_maintenance();

    Ok(())
}
