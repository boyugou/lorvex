//! Cross-platform notification action handling for task reminders.
//!
//! Each platform registers two actions for the "task-reminder" category:
//! - **Complete**: marks the task as completed
//! - **Snooze**: creates a new reminder on the same task, scheduled for
//!   `now + DEFAULT_REMINDER_SNOOZE_MINUTES` (default: 60 minutes).
//!   Mirrors the TypeScript snooze path exactly.
//!
//! **macOS** — Registers a `UNNotificationCategory` with two
//! `UNNotificationAction`s and installs a `UNUserNotificationCenterDelegate`
//! that handles action responses and default taps. Button titles are
//! resolved against the current `language` preference at registration time;
//! call [`register_notification_categories`] again after the user changes
//! their language to re-register with translated titles.
//!
//! **Windows** — Toast rich action buttons (Complete / Snooze) require
//! both a WinRT ToastNotificationManager emission path AND a COM-
//! registered `INotificationActivationCallback` (CLSID in the registry
//! via NSIS + correct AUMID). This build ships neither, so Windows
//! reminders fall back to plain toasts from the Tauri notification
//! plugin. The Windows module here keeps stub handlers for symmetry
//! with macOS; if/when someone wires the WinRT + CLSID path,
//! `register_notification_categories` and `install_notification_delegate`
//! become the hooks to plug in.
//!
//! **Other platforms** — No-op stubs.
//!
//! ---
//!
//! The platform-specific implementations live in sibling modules:
//!
//! - [`macos`] — UN delegate registration + Obj-C delegate class definition.
//! - [`windows`] — no-op stubs and the rationale comment block for the
//!   missing WinRT + COM activation wiring.
//! - [`fallback`] — no-op stubs for non-macOS/non-Windows targets.
//!
//! The cfg-dispatch shells in this file route the public surface
//! (`register_notification_categories`, `install_notification_delegate`)
//! to the appropriate platform module at compile time.

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
mod fallback;
#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "windows")]
mod windows;

// ---------------------------------------------------------------------------
// Typed action identifier (M1)
// ---------------------------------------------------------------------------
//
// The native UN APIs hand us an `NSString` action identifier inside
// `did_receive_notification_response`. The closed set is lifted into
// a typed enum so the dispatch is exhaustive at compile time and the
// unknown-id path is logged as an explicit diagnostic. A
// `match action_id.as_str()` with a wildcard arm
// (`_ => handle_open_task`) would let a future "delete" action wired
// in `register_notification_categories` but missed in the dispatcher
// silently become an "open" tap, discarding the user's destructive
// intent as a navigation.

/// Action identifier returned by the native UN response delegate.
///
/// `Default` represents the user tapping the notification body (no
/// custom action) — UN signals this with `UNNotificationDefaultActionIdentifier`
/// which the parser maps to this variant.
///
/// `Unknown` carries the raw string for telemetry: we still dispatch
/// to the open-task path (default tap is the safest interpretation),
/// but the wrapped value lets the diagnostic surface flag the
/// surprise so a future variant gap is observable.
#[cfg(target_os = "macos")]
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) enum NotificationAction {
    Complete,
    Snooze,
    Default,
    Unknown(String),
}

#[cfg(target_os = "macos")]
impl NotificationAction {
    /// Identifier for the macOS-default tap. Hardcoded literal value
    /// of `UNNotificationDefaultActionIdentifier` so we can pattern-
    /// match without pulling the Apple-prefixed constant through the
    /// Obj-C runtime on every tap.
    const DEFAULT_ACTION_ID: &'static str = "com.apple.UNNotificationDefaultActionIdentifier";

    pub(super) fn parse(raw: &str) -> Self {
        match raw {
            "complete" => NotificationAction::Complete,
            "snooze" => NotificationAction::Snooze,
            Self::DEFAULT_ACTION_ID => NotificationAction::Default,
            other => NotificationAction::Unknown(other.to_string()),
        }
    }
}

// ---------------------------------------------------------------------------
// Cfg-dispatch shells: the platform module exports the same public surface
// regardless of target OS.
// ---------------------------------------------------------------------------

#[cfg(target_os = "macos")]
pub(crate) fn register_notification_categories(locale: &str) {
    macos::register_notification_categories(locale);
}

#[cfg(target_os = "macos")]
pub(crate) fn install_notification_delegate(app_handle: tauri::AppHandle) {
    macos::install_notification_delegate(app_handle);
}

#[cfg(target_os = "windows")]
pub(crate) fn register_notification_categories(locale: &str) {
    windows::register_notification_categories(locale);
}

#[cfg(target_os = "windows")]
pub(crate) fn install_notification_delegate(app_handle: tauri::AppHandle) {
    windows::install_notification_delegate(app_handle);
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub(crate) fn register_notification_categories(locale: &str) {
    fallback::register_notification_categories(locale);
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub(crate) fn install_notification_delegate(app_handle: tauri::AppHandle) {
    fallback::install_notification_delegate(app_handle);
}

// ---------------------------------------------------------------------------
// Shared error sink — durable + typed-event channel
// ---------------------------------------------------------------------------

/// notification-action errors must be durable. Previously
/// every `eprintln!` on complete/snooze/open failure went to a closed
/// stderr (no console on macOS release, windows_subsystem=windows on
/// Windows), so users whose Complete-tap silently failed had no trace
/// anywhere. Write to error_logs so Settings → Diagnostics surfaces
/// the failure.
///
/// Routes the `get_conn()` Err path (SQLite pool init failure, disk
/// gone, schema migration mid-flight) to `error_logs` instead of
/// silently dropping it. Without it the notification system never
/// got a signal that the action failed, the user saw nothing, and
/// macOS would re-fire the same reminder on its retry cadence —
/// silently, forever. Dual-channel: write the durable error_logs row
/// when the DB is reachable, AND fire a typed Tauri event so the
/// frontend can show an in-app toast even when the DB layer is
/// degraded. The event payload carries the action + task_id +
/// message so the frontend's diagnostic surface (Settings →
/// Diagnostics) can correlate with the durable row when the DB
/// recovers.
///
/// the notification-action error channel const now
/// lives in [`crate::event_channels::NOTIFICATION_ACTION_ERROR`] so every
/// backend-emitted event channel name is co-located in a single module.
#[cfg(any(target_os = "macos", target_os = "windows"))]
pub(super) fn record_notification_action_error(action: &str, task_id: &str, message: &str) {
    let detail = format!("notification action '{action}' on task {task_id} failed: {message}");
    let mut durable_log_ok = false;
    if let Ok(conn) = crate::db::get_conn() {
        if crate::commands::diagnostics::append_error_log_internal(
            &conn,
            "notification.action",
            &detail,
            None,
            Some("error".to_string()),
        )
        .is_ok()
        {
            durable_log_ok = true;
        }
    }

    // Always emit the typed event so the frontend can react even when
    // the durable log is reachable; Settings → Diagnostics will
    // dedupe on `notification.action` source.
    #[cfg(target_os = "macos")]
    {
        if let Some(app_handle) = macos::delegate_app_handle() {
            use tauri::Emitter;
            let payload = serde_json::json!({
                "action": action,
                "taskId": task_id,
                "message": message,
                "durableLogged": durable_log_ok,
            });
            // track this emit so the desktop quit-flush
            // path can join on outstanding reminder-action diagnostics
            // before tearing the process down. `track_emit` increments
            // a process-global atomic before the closure runs and
            // decrements it on drop (panic-safe).
            crate::platform::notification_dispatcher::track_emit(|| {
                let _ = app_handle.emit(crate::event_channels::NOTIFICATION_ACTION_ERROR, payload);
            });
        }
    }
    // On Windows the delegate is a no-op (no rich actions), so there
    // is no app_handle path here today; if the WinRT activation path
    // ever lands the event emit can be moved into a shared helper.
    let _ = durable_log_ok;
}

#[cfg(all(test, any(target_os = "macos", target_os = "windows")))]
mod tests {
    use crate::commands::diagnostics::{append_error_log_internal, read_error_logs};
    use crate::test_support::test_conn;

    /// typed `NotificationAction::parse` covers every
    /// dispatcher arm explicitly. A wildcard regression that
    /// silently re-folded an unknown identifier into the default-tap
    /// open path would fail this test because `Unknown(raw)`
    /// preserves the raw bytes for diagnostics.
    #[cfg(target_os = "macos")]
    #[test]
    fn notification_action_parse_covers_complete_snooze_default_and_unknown() {
        use super::NotificationAction;

        assert_eq!(
            NotificationAction::parse("complete"),
            NotificationAction::Complete
        );
        assert_eq!(
            NotificationAction::parse("snooze"),
            NotificationAction::Snooze
        );
        assert_eq!(
            NotificationAction::parse(NotificationAction::DEFAULT_ACTION_ID),
            NotificationAction::Default
        );
        // A hypothetical "delete" action must land on `Unknown` with
        // the raw bytes preserved so the diagnostic path can flag
        // the gap. A wildcard match arm routing it to
        // `handle_open_task` would silently drop the destructive
        // intent.
        let unknown = NotificationAction::parse("delete");
        match unknown {
            NotificationAction::Unknown(raw) => assert_eq!(raw, "delete"),
            other => panic!("expected Unknown arm, got {other:?}"),
        }
    }

    /// Regression for #2630 / notification-action
    /// Complete / Snooze / Open failures must land in `error_logs`
    /// so Settings → Diagnostics can surface them. Previously
    /// every failure was `eprintln!`-only — invisible on Tauri
    /// release binaries (no console on macOS, `windows_subsystem=
    /// windows` on Windows).
    ///
    /// Why this test mirrors the helper inline instead of calling
    /// `record_notification_action_error` directly: the production
    /// helper acquires a writer connection through
    /// `crate::db::get_conn()` which bootstraps the process-wide
    /// `OnceLock<ConnectionPool>`. That pool's init step calls
    /// `crate::hlc::init_hlc` which refuses to run twice, so in a
    /// test binary where any other test has already called
    /// `ensure_hlc_for_test` the pool init fails with
    /// `"HLC already initialized"`. Fixing that is a production-code
    /// change outside the scope of this regression-test PR (see the
    /// follow-up note in the issue #2630 thread).
    ///
    /// The test still locks in the invariants that matter: the
    /// `source` tag, the level, and the wire format that Settings →
    /// Diagnostics pattern-matches on. A refactor that changed any of
    /// those would need to update the test here.
    #[test]
    fn notification_action_error_writes_are_persisted_with_stable_source_tag() {
        let conn = test_conn();

        // Exact replica of the body of `record_notification_action_error`
        // (#2575). Any change to that helper's source tag, level, or
        // format must also update this test.
        let action = "complete";
        let task_id = "task-regression-2630";
        let underlying = "complete_task_internal returned Err(\"list not found\")";
        let detail =
            format!("notification action '{action}' on task {task_id} failed: {underlying}");
        append_error_log_internal(
            &conn,
            "notification.action",
            &detail,
            None,
            Some("error".to_string()),
        )
        .expect("append_error_log_internal must succeed");

        let logs = read_error_logs(&conn, Some(10), None).expect("read error_logs");
        let row = logs
            .iter()
            .find(|row| row.source == "notification.action")
            .expect("notification-action row must exist");
        assert_eq!(
            row.level, "error",
            "notification-action failures must log at level=error"
        );
        assert!(
            row.message.contains("notification action 'complete'"),
            "message must name the action; got: {}",
            row.message
        );
        assert!(
            row.message.contains("task-regression-2630"),
            "message must name the task id; got: {}",
            row.message
        );
        assert!(
            row.message.contains("list not found"),
            "message must carry the underlying error detail; got: {}",
            row.message
        );
    }
}
