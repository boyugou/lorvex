// Canonical preference key registry — mirrors lorvex-domain/src/preference_keys.rs
//
// Parity contract: every `pub const PREF_*` / `pub const DEV_*` in
// `lorvex-domain/src/preference_keys.rs` MUST have a matching export
// here with the same string literal. The sole exception is
// `PREF_FOCUS_BREAK_MINUTES`, which is a TS-only preference that Rust
// never reads (stored via the generic `set_preference` IPC and owned
// entirely by the focus-mode frontend). Keep this file sorted to match
// the Rust source so drift shows up clearly in diffs.
//
// Drift detection: `scripts/tests/contracts/preference_keys_contracts.test.mjs`
// enforces the parity invariant at CI time.

// Synced global preferences (preferences table)
export const PREF_WORKING_HOURS = 'working_hours';
export const PREF_TIMEZONE = 'timezone';
export const PREF_WEEKLY_REVIEW_DAY = 'weekly_review_day';
export const PREF_DASHBOARD_LAYOUT = 'dashboard_layout';
export const PREF_DEFAULT_LIST_ID = 'default_list_id';
export const PREF_AI_BRIEFING_ENABLED = 'ai_briefing_enabled';
export const PREF_AI_CHANGELOG_RETENTION_POLICY = 'ai_changelog_retention_policy';
export const PREF_LANGUAGE = 'language';
export const PREF_THEME = 'theme';
export const PREF_APPEARANCE_PROFILE = 'appearance_profile';
export const PREF_FONT_SCALE = 'font_scale';
export const PREF_ERROR_LOG_RETENTION_DAYS = 'error_log_retention_days';
/** hide completed tasks older than N days in list views to
 *  avoid rendering the full completion history. Integer-valued: 0 means
 *  "always show", any positive integer is the cutoff in days. Completed
 *  tasks themselves are kept forever — this is a render-time filter.
 *  Default is 30 days. */
export const PREF_HIDE_COMPLETED_OLDER_THAN_DAYS = 'hide_completed_older_than_days';
export const PREF_SIDEBAR_VISIBLE_MODULES = 'sidebar_visible_modules';
export const PREF_MORNING_BRIEFING_TIME = 'morning_briefing_time';
export const PREF_WEEKLY_REVIEW_TIME = 'weekly_review_time';
export const PREF_MEMORY_LOCK_ENABLED = 'memory_lock_enabled';
export const PREF_SYNC_ENABLED = 'sync_enabled';
export const PREF_SYNC_BACKEND_KIND = 'sync_backend_kind';
export const PREF_SYNC_BACKEND_CONFIGS = 'sync_backend_configs';
export const PREF_QUIET_HOURS_START = 'quiet_hours_start';
export const PREF_QUIET_HOURS_END = 'quiet_hours_end';
export const PREF_NOTIFICATION_SOUND_ENABLED = 'notification_sound_enabled';
export const PREF_NOTIFICATION_MUTED_LISTS = 'notification_muted_lists';
export const PREF_WEEK_STARTS_ON = 'week_starts_on';
export const PREF_CALENDAR_VIEW_MODE = 'calendar_view_mode';
export const PREF_SIDEBAR_HIDE_EMPTY_LISTS = 'sidebar_hide_empty_lists';
export const PREF_SETUP_COMPLETED = 'setup_completed';
export const PREF_SETUP_SUMMARY = 'setup_summary';
export const PREF_SETUP_STATE = 'setup_state';
export const PREF_RECORD_RAW_INPUT = 'record_raw_input';
export const PREF_FOCUS_WINDOW_OPACITY = 'focus_window_opacity';
// TS-only preference (no Rust consumer)
export const PREF_FOCUS_BREAK_MINUTES = 'focus_break_minutes';
/** confirm before skipping a break (default true). */
export const PREF_FOCUS_CONFIRM_SKIP_BREAK = 'focus_confirm_skip_break';
/** confirm before exiting focus mode mid-session (default true). */
export const PREF_FOCUS_CONFIRM_EXIT = 'focus_confirm_exit';
/** chime + visual flash + Tauri notification near break end (default true). */
export const PREF_FOCUS_BREAK_END_ALERT = 'focus_break_end_alert';

// Device-local state (device_state table)
export const DEV_MORNING_BRIEFING_LAST_FIRED = 'morning_briefing_last_fired';
export const DEV_WEEKLY_REVIEW_LAST_FIRED = 'weekly_review_last_fired';
export const DEV_AT_RISK_NOTIFICATION_LAST_FIRED = 'at_risk_notification_last_fired';
export const DEV_DESKTOP_CLOSE_ACTION = 'desktop_close_action';
export const DEV_MENU_BAR_ICON_VISIBLE = 'menu_bar_icon_visible';
export const DEV_NOTIFICATION_PERMISSION_PROMPTED = 'notification_permission_prompted';
export const DEV_NOTIFICATION_PERMISSION_GRANTED = 'notification_permission_granted';
export const DEV_FOCUS_MODE_TARGET_TASK_ID = 'focus_mode_target_task_id';
export const DEV_LINUX_CALENDAR_SYNC_ENABLED = 'linux_calendar_sync_enabled';
export const DEV_WINDOWS_CALENDAR_SYNC_ENABLED = 'windows_calendar_sync_enabled';
export const DEV_CALENDAR_AI_ACCESS_MODE = 'calendar_ai_access_mode';
export const DEV_ERROR_LOGS_LAST_VIEWED_AT = 'error_logs_last_viewed_at';
/**
 * latches on the first successful Quick Capture so the
 * celebratory 'try ⌘K / ?' toast fires exactly once per device. Value
 * is the RFC3339 timestamp of the first celebrated capture; presence
 * alone suppresses subsequent celebrations.
 */
export const DEV_FIRST_TASK_CELEBRATED = 'first_task_celebrated';
/**
 * onboarding-checklist visibility on this device.
 * `"true"` means the user dismissed the sidebar checklist; the card
 * auto-resurfaces if any tracked step regresses.
 */
export const DEV_ONBOARDING_DISMISSED = 'onboarding_dismissed';
/**
 * JSON array of step ids that were satisfied on the
 * previous launch, so the checklist can detect regression.
 */
export const DEV_ONBOARDING_PREVIOUSLY_DONE = 'onboarding_previously_done';
/**
 * latches `"true"` the first time the user starts focus
 * mode on this device. The onboarding checklist reads this so the
 * "try focus" row stays checked across sessions.
 */
export const DEV_FOCUS_SESSION_TRIED = 'focus_session_tried';
/**
 * latches `"true"` once the onboarding-checklist
 * post-completion hint ("You're set — quick-capture is ⌘N") has been
 * dismissed. Hints out either via the explicit close button or
 * implicitly when the user creates the next task. Local-only — no
 * sync semantics.
 */
export const DEV_ONBOARDING_COMPLETION_HINT_DISMISSED = 'onboarding_completion_hint_dismissed';
/**
 * persisted UI view-state snapshot (sidebar selection,
 * scroll positions, expanded/collapsed sections) so the MCP
 * `get_ui_view_state` tool can report what the user is currently
 * looking at. Owned entirely by the frontend; no Rust reader.
 */
export const DEV_UI_VIEW_STATE = 'ui_view_state';
/**
 * JSON-encoded next assistant-UI command the renderer
 * should execute. Written by the assistant via MCP, polled by the
 * main window. Owned by the frontend.
 */
export const DEV_ASSISTANT_UI_COMMAND = 'assistant_ui_command';
export const DEV_ASSISTANT_UI_COMMAND_HANDLED_ID = 'assistant_ui_command_handled_id';

// literal-union types over the registry above so IPC wrappers
// (`setPreference` / `setDeviceState` in `lib/ipc/settings.ts`) reject
// arbitrary strings at compile time. Per-key value shapes live in
// `preferenceValues.ts`, where `PreferenceValueOf<K>` maps each key to
// the JS value shape accepted by the typed IPC wrappers.
export type PreferenceKey =
  | typeof PREF_WORKING_HOURS
  | typeof PREF_TIMEZONE
  | typeof PREF_WEEKLY_REVIEW_DAY
  | typeof PREF_DASHBOARD_LAYOUT
  | typeof PREF_DEFAULT_LIST_ID
  | typeof PREF_AI_BRIEFING_ENABLED
  | typeof PREF_AI_CHANGELOG_RETENTION_POLICY
  | typeof PREF_LANGUAGE
  | typeof PREF_THEME
  | typeof PREF_APPEARANCE_PROFILE
  | typeof PREF_FONT_SCALE
  | typeof PREF_ERROR_LOG_RETENTION_DAYS
  | typeof PREF_HIDE_COMPLETED_OLDER_THAN_DAYS
  | typeof PREF_SIDEBAR_VISIBLE_MODULES
  | typeof PREF_MORNING_BRIEFING_TIME
  | typeof PREF_WEEKLY_REVIEW_TIME
  | typeof PREF_MEMORY_LOCK_ENABLED
  | typeof PREF_SYNC_ENABLED
  | typeof PREF_SYNC_BACKEND_KIND
  | typeof PREF_SYNC_BACKEND_CONFIGS
  | typeof PREF_QUIET_HOURS_START
  | typeof PREF_QUIET_HOURS_END
  | typeof PREF_NOTIFICATION_SOUND_ENABLED
  | typeof PREF_NOTIFICATION_MUTED_LISTS
  | typeof PREF_WEEK_STARTS_ON
  | typeof PREF_CALENDAR_VIEW_MODE
  | typeof PREF_SIDEBAR_HIDE_EMPTY_LISTS
  | typeof PREF_SETUP_COMPLETED
  | typeof PREF_SETUP_SUMMARY
  | typeof PREF_SETUP_STATE
  | typeof PREF_RECORD_RAW_INPUT
  | typeof PREF_FOCUS_WINDOW_OPACITY
  | typeof PREF_FOCUS_BREAK_MINUTES
  | typeof PREF_FOCUS_CONFIRM_SKIP_BREAK
  | typeof PREF_FOCUS_CONFIRM_EXIT
  | typeof PREF_FOCUS_BREAK_END_ALERT;

export type DeviceStateKey =
  | typeof DEV_MORNING_BRIEFING_LAST_FIRED
  | typeof DEV_WEEKLY_REVIEW_LAST_FIRED
  | typeof DEV_AT_RISK_NOTIFICATION_LAST_FIRED
  | typeof DEV_DESKTOP_CLOSE_ACTION
  | typeof DEV_MENU_BAR_ICON_VISIBLE
  | typeof DEV_NOTIFICATION_PERMISSION_PROMPTED
  | typeof DEV_NOTIFICATION_PERMISSION_GRANTED
  | typeof DEV_FOCUS_MODE_TARGET_TASK_ID
  | typeof DEV_LINUX_CALENDAR_SYNC_ENABLED
  | typeof DEV_WINDOWS_CALENDAR_SYNC_ENABLED
  | typeof DEV_CALENDAR_AI_ACCESS_MODE
  | typeof DEV_ERROR_LOGS_LAST_VIEWED_AT
  | typeof DEV_FIRST_TASK_CELEBRATED
  | typeof DEV_ONBOARDING_DISMISSED
  | typeof DEV_ONBOARDING_PREVIOUSLY_DONE
  | typeof DEV_FOCUS_SESSION_TRIED
  | typeof DEV_ONBOARDING_COMPLETION_HINT_DISMISSED
  | typeof DEV_UI_VIEW_STATE
  | typeof DEV_ASSISTANT_UI_COMMAND
  | typeof DEV_ASSISTANT_UI_COMMAND_HANDLED_ID;
