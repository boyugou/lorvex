//! Canonical preference and device-state key registry.
//! All preference key strings must be defined here, not scattered as literals.

// Synced global preferences (preferences table)
pub const PREF_WORKING_HOURS: &str = "working_hours";
pub const PREF_TIMEZONE: &str = "timezone";
pub const PREF_WEEKLY_REVIEW_DAY: &str = "weekly_review_day";
pub const PREF_DASHBOARD_LAYOUT: &str = "dashboard_layout";
pub const PREF_DEFAULT_LIST_ID: &str = "default_list_id";
pub const PREF_AI_BRIEFING_ENABLED: &str = "ai_briefing_enabled";
pub const PREF_AI_CHANGELOG_RETENTION_POLICY: &str = "ai_changelog_retention_policy";
pub const PREF_LANGUAGE: &str = "language";
pub const PREF_THEME: &str = "theme";
pub const PREF_APPEARANCE_PROFILE: &str = "appearance_profile";
pub const PREF_FONT_SCALE: &str = "font_scale";
pub const PREF_ERROR_LOG_RETENTION_DAYS: &str = "error_log_retention_days";
/// hide completed tasks older than N days in list views to
/// avoid rendering the full completion history (10k+ rows after years of
/// use). Integer-valued preference: 0 means "always show", any positive
/// integer is the cutoff in days. Completed tasks themselves are kept
/// forever — this is purely a render-time filter. Default is 30 days.
pub const PREF_HIDE_COMPLETED_OLDER_THAN_DAYS: &str = "hide_completed_older_than_days";
pub const PREF_SIDEBAR_VISIBLE_MODULES: &str = "sidebar_visible_modules";
pub const PREF_MORNING_BRIEFING_TIME: &str = "morning_briefing_time";
pub const PREF_WEEKLY_REVIEW_TIME: &str = "weekly_review_time";
pub const PREF_MEMORY_LOCK_ENABLED: &str = "memory_lock_enabled";
pub const PREF_SYNC_ENABLED: &str = "sync_enabled";
pub const PREF_SYNC_BACKEND_KIND: &str = "sync_backend_kind";
pub const PREF_SYNC_BACKEND_CONFIGS: &str = "sync_backend_configs";
pub const PREF_QUIET_HOURS_START: &str = "quiet_hours_start";
pub const PREF_QUIET_HOURS_END: &str = "quiet_hours_end";
pub const PREF_NOTIFICATION_SOUND_ENABLED: &str = "notification_sound_enabled";
pub const PREF_NOTIFICATION_MUTED_LISTS: &str = "notification_muted_lists";
pub const PREF_WEEK_STARTS_ON: &str = "week_starts_on";
pub const PREF_CALENDAR_VIEW_MODE: &str = "calendar_view_mode";
pub const PREF_SIDEBAR_HIDE_EMPTY_LISTS: &str = "sidebar_hide_empty_lists";
pub const PREF_SETUP_COMPLETED: &str = "setup_completed";
pub const PREF_SETUP_SUMMARY: &str = "setup_summary";
pub const PREF_SETUP_STATE: &str = "setup_state";
pub const PREF_RECORD_RAW_INPUT: &str = "record_raw_input";
pub const PREF_FOCUS_WINDOW_OPACITY: &str = "focus_window_opacity";
/// Confirm before skipping the focus-mode break (default true).
/// Owned by the focus-mode frontend; the canonical key string lives
/// here so the cross-language parity contract continues to hold.
pub const PREF_FOCUS_CONFIRM_SKIP_BREAK: &str = "focus_confirm_skip_break";
/// Confirm before exiting focus mode mid-session when elapsed time > 0
/// (default true). Frontend-owned.
pub const PREF_FOCUS_CONFIRM_EXIT: &str = "focus_confirm_exit";
/// End-of-break alert: chime + visual flash + (when the window is
/// unfocused) a Tauri notification. Default true. Frontend-owned.
pub const PREF_FOCUS_BREAK_END_ALERT: &str = "focus_break_end_alert";

// Device-local state (device_state table)
// Notification last-fired timestamps: device-local so a fire on device A
// does not suppress the same notification on device B.
pub const DEV_MORNING_BRIEFING_LAST_FIRED: &str = "morning_briefing_last_fired";
pub const DEV_WEEKLY_REVIEW_LAST_FIRED: &str = "weekly_review_last_fired";
pub const DEV_AT_RISK_NOTIFICATION_LAST_FIRED: &str = "at_risk_notification_last_fired";
pub const DEV_DESKTOP_CLOSE_ACTION: &str = "desktop_close_action";
pub const DEV_MENU_BAR_ICON_VISIBLE: &str = "menu_bar_icon_visible";
pub const DEV_NOTIFICATION_PERMISSION_PROMPTED: &str = "notification_permission_prompted";
pub const DEV_NOTIFICATION_PERMISSION_GRANTED: &str = "notification_permission_granted";
pub const DEV_FOCUS_MODE_TARGET_TASK_ID: &str = "focus_mode_target_task_id";
pub const DEV_LINUX_CALENDAR_SYNC_ENABLED: &str = "linux_calendar_sync_enabled";
pub const DEV_WINDOWS_CALENDAR_SYNC_ENABLED: &str = "windows_calendar_sync_enabled";
/// Provider calendar AI access mode: "off" | "busy_only" | "full_details".
/// Controls what provider calendar data AI/MCP surfaces can see (spec doc 19).
pub const DEV_CALENDAR_AI_ACCESS_MODE: &str = "calendar_ai_access_mode";
/// RFC3339 UTC timestamp of the last time the user opened
/// Settings → Data → Diagnostics and saw the current error_logs view.
/// The sidebar Settings badge counts rows with `created_at > last_viewed_at`
/// so persistent error_logs surface a "you have N unseen failures" hint
/// even when the transient toast has faded (issue #2253). Stored per-device
/// because "viewed" is a per-device UI acknowledgement, not a synced
/// semantic state.
pub const DEV_ERROR_LOGS_LAST_VIEWED_AT: &str = "error_logs_last_viewed_at";
/// latches on the first successful Quick Capture so the
/// celebratory "try command palette / keyboard shortcuts" toast fires
/// exactly once per device. Stored in `device_state`; Rust only owns the
/// canonical key string for cross-language parity.
pub const DEV_FIRST_TASK_CELEBRATED: &str = "first_task_celebrated";

/// onboarding-checklist visibility on this device.
/// `"true"` means the user dismissed the sidebar checklist; the card
/// re-appears automatically if any tracked step regresses (sync turned
/// off, MCP binary disappeared, …). Owned exclusively by the frontend;
/// Rust only stores the string blob via the generic preferences IPC.
pub const DEV_ONBOARDING_DISMISSED: &str = "onboarding_dismissed";
/// JSON array of `OnboardingStepId` values that were
/// satisfied on the previous launch. detect regression so the
/// checklist re-surfaces if a step that was done is no longer done.
pub const DEV_ONBOARDING_PREVIOUSLY_DONE: &str = "onboarding_previously_done";
/// latches `"true"` the first time the user launches
/// focus mode on this device. The onboarding checklist's "try focus"
/// row reads this so it stays checked across sessions.
pub const DEV_FOCUS_SESSION_TRIED: &str = "focus_session_tried";
/// onboarding-checklist completion hint visibility.
/// `"true"` once the post-completion "you're set — quick-capture is ⌘N"
/// hint that replaces the finished checklist has been dismissed. The
/// hint dismisses either explicitly (close button) or implicitly the
/// next time the user creates a task. Owned exclusively by the
/// frontend; Rust only stores the string blob via the generic
/// preferences IPC.
pub const DEV_ONBOARDING_COMPLETION_HINT_DISMISSED: &str = "onboarding_completion_hint_dismissed";
/// persisted UI view-state snapshot (sidebar selection, scroll
/// positions, expanded/collapsed sections) so the MCP
/// `get_ui_view_state` tool can report what the user is currently
/// looking at. Owned entirely by the frontend; Rust only stores the
/// JSON blob via the generic device-state IPC.
pub const DEV_UI_VIEW_STATE: &str = "ui_view_state";
/// JSON-encoded next assistant-UI command the
/// renderer should execute. Written by the assistant via MCP, polled
/// by the main window. Frontend-owned; Rust only round-trips the
/// blob.
pub const DEV_ASSISTANT_UI_COMMAND: &str = "assistant_ui_command";
/// id of the most recently handled
/// assistant-UI command, dedupe replay on poll. Frontend-owned.
pub const DEV_ASSISTANT_UI_COMMAND_HANDLED_ID: &str = "assistant_ui_command_handled_id";

/// Preferences whose *value* is only meaningful on the device that wrote it.
/// These must never cross the sync boundary — in either direction.
///
/// - Filesystem paths (`sync_backend_configs` carries `/Users/<username>/...`
///   rootPath values) leak PII to remote sync providers and are nonsensical on
///   peer devices.
/// - Each device chooses its OWN sync backend (`sync_backend_kind`,
///   `sync_enabled`) — replicating those would create feedback loops and
///   override the peer's own choice.
/// without this filter, `sync_backend_configs` was pushed to
/// every peer on every config change.
const LOCAL_ONLY_PREFERENCE_KEYS: &[&str] = &[
    PREF_SYNC_ENABLED,
    PREF_SYNC_BACKEND_KIND,
    PREF_SYNC_BACKEND_CONFIGS,
];

/// Returns true if `key` is device-local and must NOT be enqueued to the
/// sync outbox or accepted from a peer.
pub fn is_local_only_preference(key: &str) -> bool {
    LOCAL_ONLY_PREFERENCE_KEYS.contains(&key)
}

/// every preference key the app or MCP server is
/// allowed to write. The Tauri `set_preference` IPC validates against
/// this list before any DB work so a renderer XSS or a malformed
/// deep-link cannot shove arbitrary keys into the preferences table —
/// the previous behavior was an unbounded `(key, value)` write where
/// a hostile caller could pollute the table with thousands of garbage
/// rows. The list is the union of
/// every constant defined above (synced + the device-local subset
/// stored in the preferences table — see `LOCAL_ONLY_PREFERENCE_KEYS`).
///
/// Adding a new preference: add a constant above AND append it here.
/// The unit test below asserts every known constant is in the
/// allowlist so the two never drift.
pub const ALL_KNOWN_PREFERENCE_KEYS: &[&str] = &[
    PREF_WORKING_HOURS,
    PREF_TIMEZONE,
    PREF_WEEKLY_REVIEW_DAY,
    PREF_DASHBOARD_LAYOUT,
    PREF_DEFAULT_LIST_ID,
    PREF_AI_BRIEFING_ENABLED,
    PREF_AI_CHANGELOG_RETENTION_POLICY,
    PREF_LANGUAGE,
    PREF_THEME,
    PREF_APPEARANCE_PROFILE,
    PREF_FONT_SCALE,
    PREF_ERROR_LOG_RETENTION_DAYS,
    PREF_HIDE_COMPLETED_OLDER_THAN_DAYS,
    PREF_SIDEBAR_VISIBLE_MODULES,
    PREF_MORNING_BRIEFING_TIME,
    PREF_WEEKLY_REVIEW_TIME,
    PREF_MEMORY_LOCK_ENABLED,
    PREF_SYNC_ENABLED,
    PREF_SYNC_BACKEND_KIND,
    PREF_SYNC_BACKEND_CONFIGS,
    PREF_QUIET_HOURS_START,
    PREF_QUIET_HOURS_END,
    PREF_NOTIFICATION_SOUND_ENABLED,
    PREF_NOTIFICATION_MUTED_LISTS,
    PREF_WEEK_STARTS_ON,
    PREF_CALENDAR_VIEW_MODE,
    PREF_SIDEBAR_HIDE_EMPTY_LISTS,
    PREF_SETUP_COMPLETED,
    PREF_SETUP_SUMMARY,
    PREF_SETUP_STATE,
    PREF_RECORD_RAW_INPUT,
    PREF_FOCUS_WINDOW_OPACITY,
    PREF_FOCUS_CONFIRM_SKIP_BREAK,
    PREF_FOCUS_CONFIRM_EXIT,
    PREF_FOCUS_BREAK_END_ALERT,
];

/// Returns true if `key` is in the canonical allowlist and may be
/// written via the `set_preference` IPC.
pub fn is_known_preference_key(key: &str) -> bool {
    ALL_KNOWN_PREFERENCE_KEYS.contains(&key)
}

/// Preference keys whose scalar value is a filesystem path.
///
/// Tauri no longer has generic scalar path preferences. Sync backend paths
/// live inside `sync_backend_configs` and are validated by the sync-backend
/// configuration path, not by this key-level helper.
const PATH_SHAPED_PREFERENCE_KEYS: &[&str] = &[];

/// Returns true if `key` is a path-shaped preference whose value
/// must pass `..` / relative-path validation before being persisted.
pub fn is_path_shaped_preference_key(key: &str) -> bool {
    PATH_SHAPED_PREFERENCE_KEYS.contains(&key)
}

#[cfg(test)]
mod tests;
