use crate::{db, desktop_shell::hide_auxiliary_desktop_windows, error::AppError, event_channels};
use rusqlite::{Connection, OptionalExtension};
use std::sync::atomic::AtomicU8;
use tauri::Manager;

const DESKTOP_CLOSE_ACTION_PREFERENCE_KEY: &str =
    lorvex_domain::preference_keys::DEV_DESKTOP_CLOSE_ACTION;
const DESKTOP_CLOSE_ACTION_QUIT: &str = "quit";
const DESKTOP_CLOSE_ACTION_HIDE_TO_TRAY: &str = "hide_to_tray";
const DESKTOP_CLOSE_ACTION_CACHE_UNKNOWN: u8 = 0;
const DESKTOP_CLOSE_ACTION_CACHE_QUIT: u8 = 1;
const DESKTOP_CLOSE_ACTION_CACHE_HIDE_TO_TRAY: u8 = 2;
const DESKTOP_CLOSE_POLICY_LOG_SOURCE: &str = "desktop.close_policy";
/// `Ordering::Relaxed` is
/// load-bearing for the cache reader — every store and load is an
/// independent observation and the cache value carries no
/// happens-before contract with any sibling state. The fallback
/// chain (cache → DB read → default) is structured so a stale or
/// torn read can only delay the right answer by one
/// `resolve_desktop_close_action` call, not produce an incorrect
/// close behavior. A stronger ordering would only pay for a
/// pointless `dmb ish` on aarch64 every time a window-close event
/// queries this surface.
static DESKTOP_CLOSE_ACTION_CACHE: AtomicU8 = AtomicU8::new(DESKTOP_CLOSE_ACTION_CACHE_UNKNOWN);

fn append_desktop_close_policy_log_with_conn(
    conn: &Connection,
    level: &str,
    message: &str,
    details: Option<String>,
) -> Result<(), String> {
    crate::commands::diagnostics::append_diagnostic_log_with_conn(
        conn,
        DESKTOP_CLOSE_POLICY_LOG_SOURCE,
        level,
        message,
        details,
    )
}

fn append_desktop_close_policy_log(level: &str, message: &str, details: Option<String>) {
    let Ok(conn) = db::get_conn() else {
        return;
    };
    let _ = append_desktop_close_policy_log_with_conn(&conn, level, message, details);
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum DesktopCloseAction {
    Quit,
    HideToTray,
}

const fn desktop_close_action_to_cache_value(action: DesktopCloseAction) -> u8 {
    match action {
        DesktopCloseAction::Quit => DESKTOP_CLOSE_ACTION_CACHE_QUIT,
        DesktopCloseAction::HideToTray => DESKTOP_CLOSE_ACTION_CACHE_HIDE_TO_TRAY,
    }
}

const fn desktop_close_action_from_cache_value(value: u8) -> Option<DesktopCloseAction> {
    match value {
        DESKTOP_CLOSE_ACTION_CACHE_QUIT => Some(DesktopCloseAction::Quit),
        DESKTOP_CLOSE_ACTION_CACHE_HIDE_TO_TRAY => Some(DesktopCloseAction::HideToTray),
        _ => None,
    }
}

fn cache_desktop_close_action(action: DesktopCloseAction) {
    DESKTOP_CLOSE_ACTION_CACHE.store(
        desktop_close_action_to_cache_value(action),
        std::sync::atomic::Ordering::Relaxed,
    );
}

fn read_cached_desktop_close_action() -> Option<DesktopCloseAction> {
    desktop_close_action_from_cache_value(
        DESKTOP_CLOSE_ACTION_CACHE.load(std::sync::atomic::Ordering::Relaxed),
    )
}

const fn default_desktop_close_action() -> DesktopCloseAction {
    if crate::platform::close_policy::default_is_hide_to_tray() {
        DesktopCloseAction::HideToTray
    } else {
        DesktopCloseAction::Quit
    }
}

/// Typed parse outcomes for the `dev_desktop_close_action`
/// preference. The discriminated union keeps the closed failure set
/// explicit so `resolve_desktop_close_action` can surface a typed
/// reason that telemetry can pivot on without stringly-typed
/// substring matching. Collapsing every failure mode (non-JSON
/// garbage, JSON-but-not-a-string, valid JSON string outside the
/// `quit`/`hide_to_tray` allowlist) into a single `None` would erase
/// the signal that distinguishes "device_state row was vandalized"
/// from "an old client wrote a value we never recognized."
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ParseDesktopCloseActionError {
    /// The raw value was not a canonical JSON string (e.g. `quit`,
    /// `true`, `42`, malformed JSON, or a JSON-string-of-a-JSON-string).
    NotCanonicalJsonString,
    /// The JSON string parsed cleanly but is not in the
    /// `quit`/`hide_to_tray` allowlist. Distinct from
    /// `NotCanonicalJsonString` because a DB write that round-trips
    /// through `serde_json` (e.g. a future canonicalization pass) can
    /// land here without indicating tampering.
    UnknownAction,
}

impl ParseDesktopCloseActionError {
    pub(crate) const fn as_str(self) -> &'static str {
        match self {
            ParseDesktopCloseActionError::NotCanonicalJsonString => "not_canonical_json_string",
            ParseDesktopCloseActionError::UnknownAction => "unknown_action",
        }
    }
}

impl std::fmt::Display for ParseDesktopCloseActionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

fn parse_desktop_close_action(
    raw: &str,
) -> Result<DesktopCloseAction, ParseDesktopCloseActionError> {
    let candidate = lorvex_domain::parse_json_string_preference(Some(raw))
        .ok_or(ParseDesktopCloseActionError::NotCanonicalJsonString)?;

    match candidate.as_str() {
        DESKTOP_CLOSE_ACTION_QUIT => Ok(DesktopCloseAction::Quit),
        DESKTOP_CLOSE_ACTION_HIDE_TO_TRAY => Ok(DesktopCloseAction::HideToTray),
        _ => Err(ParseDesktopCloseActionError::UnknownAction),
    }
}

fn resolve_desktop_close_action_from_conn(
    conn: &Connection,
    fallback: DesktopCloseAction,
) -> Result<DesktopCloseAction, String> {
    let raw = conn
        .query_row(
            "SELECT value FROM device_state WHERE key = ?1",
            rusqlite::params![DESKTOP_CLOSE_ACTION_PREFERENCE_KEY],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(AppError::from)
        .map_err(String::from)?;

    match raw {
        Some(value) => parse_desktop_close_action(&value).map_err(|reason| {
            // surface the typed reason instead of
            // collapsing every failure mode to a single string. The
            // caller's `eprintln!` line still includes the literal
            // `desktop_close_action` token so existing log greps hit,
            // and the typed reason gives operators a stable
            // discriminator for triage without substring matching.
            format!("desktop_close_action device_state must be a canonical JSON string ({reason})")
        }),
        None => Ok(fallback),
    }
}

pub(crate) fn resolve_desktop_close_action() -> DesktopCloseAction {
    let fallback = default_desktop_close_action();
    let cached = read_cached_desktop_close_action();
    let Ok(pool) = db::get_db() else {
        return cached.unwrap_or(fallback);
    };
    let conn = match pool.read_lock_result() {
        Ok(conn) => conn,
        Err(error) => {
            append_desktop_close_policy_log(
                "warn",
                "desktop close action read failed; using cached/default fallback",
                Some(format!("error={error}")),
            );
            return cached.unwrap_or(fallback);
        }
    };

    let resolved_result = resolve_desktop_close_action_from_conn(&conn, fallback);
    drop(conn);
    let resolved = match resolved_result {
        Ok(value) => value,
        Err(error) => {
            append_desktop_close_policy_log(
                "warn",
                "desktop close action invalid; using cached/default fallback",
                Some(format!(
                    "key={DESKTOP_CLOSE_ACTION_PREFERENCE_KEY} error={error}"
                )),
            );
            cached.unwrap_or(fallback)
        }
    };
    cache_desktop_close_action(resolved);
    resolved
}

pub(crate) fn install_main_close_to_hide(app: &tauri::App) {
    let Some(main) = app.get_webview_window("main") else {
        return;
    };

    let main_clone = main.clone();
    let app_handle = app.handle().clone();
    main.on_window_event(move |event| {
        if let tauri::WindowEvent::CloseRequested { api, .. } = event {
            api.prevent_close();
            match resolve_desktop_close_action() {
                DesktopCloseAction::HideToTray => {
                    if let Some(tray) = app_handle.tray_by_id("lorvex-tray") {
                        let _ = tray.set_visible(true);
                    }
                    hide_auxiliary_desktop_windows(&app_handle);
                    let _ = main_clone.hide();
                }
                DesktopCloseAction::Quit => {
                    // coordinated shutdown. Prior to this
                    // hook, `app_handle.exit(0)` tore down the webview
                    // process instantly — pending debounced writes in
                    // the renderer (focus-mode elapsed time)
                    // fire-and-forget
                    // their IPC on unmount, so the Rust side of the
                    // call raced process death and was routinely
                    // truncated. Emit `lorvex-quit-flush` so the
                    // frontend's `quitFlush` registry can drain, then
                    // wait up to ~1 s before exiting. 1 s comfortably
                    // covers the 600–800 ms debounce windows the
                    // audit flagged and a round-trip.
                    use tauri::Emitter;
                    let handle = app_handle.clone();
                    // best-effort emit of the
                    // quit-flush trigger. If the IPC channel is
                    // already torn down (the user dismissed the
                    // window mid-quit, the renderer crashed, etc.),
                    // the 1-second wait below still runs and the
                    // process exits cleanly — there's no useful
                    // recovery for an emit failure during shutdown.
                    let _ = handle.emit(event_channels::QUIT_FLUSH, ());
                    // name the thread so the 1 s
                    // quit-flush wait is identifiable in macOS Activity
                    // Monitor / `samply`-style stack traces / crash
                    // reports captured during shutdown. Without a name
                    // it shows up as an anonymous worker and is easy
                    // to mistake for a leaked Tokio thread when
                    // diagnosing slow exits.
                    // The 1000ms wait lives in a co-located named
                    // constant so the value and its rationale stay
                    // next to the only place that reads it. The
                    // canonical value covers the 600–800ms renderer
                    // debounce windows plus an IPC round-trip; bump
                    // only after measuring the actual debounce
                    // ceiling.
                    const QUIT_FLUSH_WAIT_MS: u64 = 1000;
                    // Piggy-back on the same wait window to drain
                    // the platform notification dispatcher's
                    // in-flight emit counter. Reminder UN-delegate
                    // callbacks fired at quit + ε would otherwise
                    // race process death — the wait above only
                    // counts renderer-side debounce flushes, so an
                    // outstanding `notification.action` event that
                    // the delegate emits while the dispatcher's IPC
                    // bus is still flushing would be lost. The
                    // dispatcher runs entirely in-process so we can
                    // join on its counter; if the counter never
                    // drains we still exit at the unconditional 1s
                    // ceiling so a stuck emit cannot hang shutdown
                    // indefinitely.
                    // #3053 M15: fallback path if the OS refuses to
                    // spawn another thread during shutdown (very rare,
                    // but a panic mid-quit instead of a graceful exit
                    // is worse than a synchronous wait). Run the same
                    // budget on the current thread so the user still
                    // gets the renderer drain + notification dispatcher
                    // wait before the process exits.
                    let handle_fallback = handle.clone();
                    let spawn_result = std::thread::Builder::new()
                        .name("lorvex-quit-flush-wait".to_string())
                        .spawn(move || {
                            let total = std::time::Duration::from_millis(QUIT_FLUSH_WAIT_MS);
                            let started = std::time::Instant::now();
                            std::thread::sleep(total);
                            let remaining = total.saturating_sub(started.elapsed());
                            // Two budgets in series: the unconditional
                            // 1s above covers the renderer's
                            // `lorvex-quit-flush` callbacks; this
                            // additional wait drains any
                            // notification-dispatcher emits that fired
                            // during that first window.
                            let _ = crate::platform::notification_dispatcher::wait_for_idle(
                                remaining.max(std::time::Duration::from_millis(50)),
                            );
                            handle.exit(0);
                        });
                    if let Err(error) = spawn_result {
                        append_desktop_close_policy_log(
                            "warn",
                            "quit flush wait thread spawn failed; draining inline",
                            Some(format!("error={error}")),
                        );
                        let total = std::time::Duration::from_millis(QUIT_FLUSH_WAIT_MS);
                        let started = std::time::Instant::now();
                        std::thread::sleep(total);
                        let remaining = total.saturating_sub(started.elapsed());
                        let _ = crate::platform::notification_dispatcher::wait_for_idle(
                            remaining.max(std::time::Duration::from_millis(50)),
                        );
                        handle_fallback.exit(0);
                    }
                }
            }
        }
    });
}

#[cfg(all(test, desktop))]
mod tests {
    use super::{
        cache_desktop_close_action, default_desktop_close_action, parse_desktop_close_action,
        read_cached_desktop_close_action, resolve_desktop_close_action_from_conn,
        DesktopCloseAction, ParseDesktopCloseActionError, DESKTOP_CLOSE_ACTION_CACHE,
        DESKTOP_CLOSE_ACTION_CACHE_UNKNOWN,
    };

    use crate::test_support::test_conn;

    #[test]
    fn append_desktop_close_policy_log_with_conn_persists_structured_diagnostic() {
        let conn = test_conn();

        super::append_desktop_close_policy_log_with_conn(
            &conn,
            "Warning",
            "Desktop close policy token=message-secret",
            Some("stage=test token=details-secret".to_string()),
        )
        .expect("append desktop close policy diagnostic");

        let row: (String, String, String, Option<String>) = conn
            .query_row(
                "SELECT source, level, message, details FROM error_logs",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .expect("read diagnostic row");

        assert_eq!(row.0, super::DESKTOP_CLOSE_POLICY_LOG_SOURCE);
        assert_eq!(row.1, "warn");
        assert_eq!(row.2, "Desktop close policy token=[REDACTED]");
        assert_eq!(row.3.as_deref(), Some("stage=test token=[REDACTED]"));
    }

    #[test]
    fn desktop_close_action_defaults_match_platform_contract() {
        #[cfg(target_os = "macos")]
        assert_eq!(
            default_desktop_close_action(),
            DesktopCloseAction::HideToTray
        );

        #[cfg(not(target_os = "macos"))]
        assert_eq!(default_desktop_close_action(), DesktopCloseAction::Quit);
    }

    #[test]
    fn desktop_close_action_cache_roundtrip() {
        DESKTOP_CLOSE_ACTION_CACHE.store(
            DESKTOP_CLOSE_ACTION_CACHE_UNKNOWN,
            std::sync::atomic::Ordering::Relaxed,
        );
        assert_eq!(read_cached_desktop_close_action(), None);

        cache_desktop_close_action(DesktopCloseAction::Quit);
        assert_eq!(
            read_cached_desktop_close_action(),
            Some(DesktopCloseAction::Quit)
        );

        cache_desktop_close_action(DesktopCloseAction::HideToTray);
        assert_eq!(
            read_cached_desktop_close_action(),
            Some(DesktopCloseAction::HideToTray)
        );
    }

    #[test]
    fn desktop_close_action_parser_requires_canonical_json_string() {
        assert_eq!(
            parse_desktop_close_action("\"quit\""),
            Ok(DesktopCloseAction::Quit)
        );
        assert_eq!(
            parse_desktop_close_action("\"hide_to_tray\""),
            Ok(DesktopCloseAction::HideToTray)
        );
        // raw unquoted string is not canonical JSON,
        // distinct error arm from "valid JSON string but unknown
        // action."
        assert_eq!(
            parse_desktop_close_action("quit"),
            Err(ParseDesktopCloseActionError::NotCanonicalJsonString)
        );
        assert_eq!(
            parse_desktop_close_action("\"invalid\""),
            Err(ParseDesktopCloseActionError::UnknownAction)
        );
    }

    #[test]
    fn resolve_desktop_close_action_from_conn_reads_canonical_device_state() {
        let conn = test_conn();
        conn.execute(
            "INSERT INTO device_state (key, value) VALUES (?1, ?2)",
            rusqlite::params![
                super::DESKTOP_CLOSE_ACTION_PREFERENCE_KEY,
                "\"hide_to_tray\""
            ],
        )
        .expect("insert close action device state");

        assert_eq!(
            resolve_desktop_close_action_from_conn(&conn, DesktopCloseAction::Quit)
                .expect("read close action"),
            DesktopCloseAction::HideToTray
        );
    }

    #[test]
    fn resolve_desktop_close_action_from_conn_rejects_malformed_device_state() {
        let conn = test_conn();
        conn.execute(
            "INSERT INTO device_state (key, value) VALUES (?1, ?2)",
            rusqlite::params![super::DESKTOP_CLOSE_ACTION_PREFERENCE_KEY, "hide_to_tray"],
        )
        .expect("insert malformed close action device state");

        let error = resolve_desktop_close_action_from_conn(&conn, DesktopCloseAction::Quit)
            .expect_err("malformed close action should fail");
        assert!(
            error.contains("desktop_close_action"),
            "unexpected error: {error}"
        );
    }
}
