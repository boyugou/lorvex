// per-key value shapes for the preference / device-state
// IPC surface. This is the second half of the type-safety story started
// in, which locked the *key* surface to a literal union but left
// values as `unknown`. Each entry pins the JS value an
// `setPreference<K>(key, value)` call may pass; the same shape doubles
// as the parsed read-side result for callers that already validated raw
// input.
//
// Heterogeneity rules:
//   - Boolean preferences use `boolean`.
//   - Numeric preferences use `number`. Nullable retention windows use
//     `number | null` (null === "keep forever / no limit").
//   - Enum-like strings use the existing literal-union types.
//   - Structured JSON preferences use the canonical interface that the
//     reader already exports (`SidebarModuleConfig`, `SyncBackendConfigs`,
//     `WorkingHoursPreference`, …).
//   - `unknown` is reserved for preferences with genuinely polymorphic
//     payloads owned by the backend (e.g. `dashboard_layout`); the UI
//     never writes those, so the loose typing has no observable cost.
//
// `string` covers IANA timezones, RFC3339 timestamps, and HH:MM clock
// values; values that can be cleared by the UI are typed
// `string | null` so passing `null` clears the slot through the same
// IPC. Stricter branded types are a follow-up — they require touching
// every caller and the runtime behaviour is identical.

import type { AppearanceProfile, ThemeMode } from '../theme/model';
import type { SidebarModuleConfig } from '../sidebarModules';
import type { SyncBackendConfigs } from '../syncBackend/model';
import type { SyncBackendKind } from '../syncBackend/kinds';
import type {
  PREF_AI_BRIEFING_ENABLED,
  PREF_AI_CHANGELOG_RETENTION_POLICY,
  PREF_APPEARANCE_PROFILE,
  PREF_CALENDAR_VIEW_MODE,
  PREF_DASHBOARD_LAYOUT,
  PREF_DEFAULT_LIST_ID,
  PREF_ERROR_LOG_RETENTION_DAYS,
  PREF_FOCUS_BREAK_END_ALERT,
  PREF_FOCUS_BREAK_MINUTES,
  PREF_FOCUS_CONFIRM_EXIT,
  PREF_FOCUS_CONFIRM_SKIP_BREAK,
  PREF_FOCUS_WINDOW_OPACITY,
  PREF_FONT_SCALE,
  PREF_HIDE_COMPLETED_OLDER_THAN_DAYS,
  PREF_LANGUAGE,
  PREF_MEMORY_LOCK_ENABLED,
  PREF_MORNING_BRIEFING_TIME,
  PREF_NOTIFICATION_MUTED_LISTS,
  PREF_NOTIFICATION_SOUND_ENABLED,
  PREF_QUIET_HOURS_END,
  PREF_QUIET_HOURS_START,
  PREF_RECORD_RAW_INPUT,
  PREF_SETUP_COMPLETED,
  PREF_SETUP_SUMMARY,
  PREF_SETUP_STATE,
  PREF_SIDEBAR_HIDE_EMPTY_LISTS,
  PREF_SIDEBAR_VISIBLE_MODULES,
  PREF_SYNC_BACKEND_CONFIGS,
  PREF_SYNC_BACKEND_KIND,
  PREF_SYNC_ENABLED,
  PREF_THEME,
  PREF_TIMEZONE,
  PREF_WEEK_STARTS_ON,
  PREF_WEEKLY_REVIEW_DAY,
  PREF_WEEKLY_REVIEW_TIME,
  PREF_WORKING_HOURS,
  DEV_ASSISTANT_UI_COMMAND,
  DEV_ASSISTANT_UI_COMMAND_HANDLED_ID,
  DEV_AT_RISK_NOTIFICATION_LAST_FIRED,
  DEV_CALENDAR_AI_ACCESS_MODE,
  DEV_DESKTOP_CLOSE_ACTION,
  DEV_ERROR_LOGS_LAST_VIEWED_AT,
  DEV_FIRST_TASK_CELEBRATED,
  DEV_FOCUS_MODE_TARGET_TASK_ID,
  DEV_FOCUS_SESSION_TRIED,
  DEV_LINUX_CALENDAR_SYNC_ENABLED,
  DEV_MENU_BAR_ICON_VISIBLE,
  DEV_MORNING_BRIEFING_LAST_FIRED,
  DEV_NOTIFICATION_PERMISSION_GRANTED,
  DEV_NOTIFICATION_PERMISSION_PROMPTED,
  DEV_ONBOARDING_DISMISSED,
  DEV_ONBOARDING_COMPLETION_HINT_DISMISSED,
  DEV_ONBOARDING_PREVIOUSLY_DONE,
  DEV_UI_VIEW_STATE,
  DEV_WEEKLY_REVIEW_LAST_FIRED,
  DEV_WINDOWS_CALENDAR_SYNC_ENABLED,
  DeviceStateKey,
  PreferenceKey,
} from './keys';

/** Working-hours preference payload. Times are HH:MM strings. */
interface WorkingHoursPreference {
  start: string;
  end: string;
}

/**
 * Per-key value shape for the synced preferences table. Every member
 * of the `PreferenceKey` literal union must have an entry; the
 * compile-time `Record<PreferenceKey, …>` constraint below keeps
 * future additions honest.
 *
 * The `null` branches mark preferences that are *cleared* (rather than
 * defaulted) by writing `null` through `setPreference`. Read paths
 * still parse `null` raws through their own default fallback, so the
 * `null` here represents the wire payload, not the parsed default.
 */
interface PreferenceValueShape {
  [PREF_WORKING_HOURS]: WorkingHoursPreference;
  [PREF_TIMEZONE]: string;
  [PREF_WEEKLY_REVIEW_DAY]: string;
  // Backend-owned JSON layout (`{sections:[…]}`); the UI only reads it.
  [PREF_DASHBOARD_LAYOUT]: unknown;
  [PREF_DEFAULT_LIST_ID]: string;
  [PREF_AI_BRIEFING_ENABLED]: boolean;
  /** Days to keep the AI changelog; `null` = keep forever. */
  [PREF_AI_CHANGELOG_RETENTION_POLICY]: number | null;
  /** Active locale tag (e.g. `'en'`, `'zh'`); `null` resets to system. */
  [PREF_LANGUAGE]: string | null;
  [PREF_THEME]: ThemeMode;
  [PREF_APPEARANCE_PROFILE]: AppearanceProfile;
  [PREF_FONT_SCALE]: number;
  /** Days to keep error logs; `null` = keep forever. */
  [PREF_ERROR_LOG_RETENTION_DAYS]: number | null;
  [PREF_HIDE_COMPLETED_OLDER_THAN_DAYS]: number;
  [PREF_SIDEBAR_VISIBLE_MODULES]: SidebarModuleConfig;
  [PREF_MORNING_BRIEFING_TIME]: string;
  [PREF_WEEKLY_REVIEW_TIME]: string;
  [PREF_MEMORY_LOCK_ENABLED]: boolean;
  [PREF_SYNC_ENABLED]: boolean;
  /** Active sync backend; `null` when sync is disabled / not yet configured. */
  [PREF_SYNC_BACKEND_KIND]: SyncBackendKind | null;
  [PREF_SYNC_BACKEND_CONFIGS]: SyncBackendConfigs;
  /** HH:MM start of nightly quiet-hours window; `null` disables. */
  [PREF_QUIET_HOURS_START]: string | null;
  /** HH:MM end of nightly quiet-hours window; `null` disables. */
  [PREF_QUIET_HOURS_END]: string | null;
  [PREF_NOTIFICATION_SOUND_ENABLED]: boolean;
  [PREF_NOTIFICATION_MUTED_LISTS]: string[];
  /** ISO weekday index 0–6 (0 = Sunday). */
  [PREF_WEEK_STARTS_ON]: number;
  [PREF_CALENDAR_VIEW_MODE]: 'week' | 'month';
  [PREF_SIDEBAR_HIDE_EMPTY_LISTS]: boolean;
  [PREF_SETUP_COMPLETED]: boolean;
  [PREF_SETUP_SUMMARY]: string;
  // Backend-owned setup-state machine; the UI never writes it.
  [PREF_SETUP_STATE]: unknown;
  [PREF_RECORD_RAW_INPUT]: boolean;
  /** Window opacity in 0.0–1.0. */
  [PREF_FOCUS_WINDOW_OPACITY]: number;
  /** Break length in minutes; 0 = breaks disabled. */
  [PREF_FOCUS_BREAK_MINUTES]: number;
  [PREF_FOCUS_CONFIRM_SKIP_BREAK]: boolean;
  [PREF_FOCUS_CONFIRM_EXIT]: boolean;
  [PREF_FOCUS_BREAK_END_ALERT]: boolean;
}

/** Static check: every `PreferenceKey` has an entry. */
type _AssertPreferenceShape = PreferenceValueShape extends Record<PreferenceKey, unknown>
  ? true
  : never;
const _assertPreferenceShape: _AssertPreferenceShape = true;
void _assertPreferenceShape;

interface DeviceStateValueShape {
  /** RFC3339 timestamp of the last morning-briefing fire on this device. */
  [DEV_MORNING_BRIEFING_LAST_FIRED]: string | null;
  /** RFC3339 timestamp of the last weekly-review fire on this device. */
  [DEV_WEEKLY_REVIEW_LAST_FIRED]: string | null;
  /** RFC3339 timestamp of the last at-risk notification fire. */
  [DEV_AT_RISK_NOTIFICATION_LAST_FIRED]: string | null;
  [DEV_DESKTOP_CLOSE_ACTION]: 'quit' | 'hide_to_tray';
  [DEV_MENU_BAR_ICON_VISIBLE]: boolean;
  [DEV_NOTIFICATION_PERMISSION_PROMPTED]: boolean;
  [DEV_NOTIFICATION_PERMISSION_GRANTED]: boolean;
  /** Task id of the explicit focus-mode target; `null` clears. */
  [DEV_FOCUS_MODE_TARGET_TASK_ID]: string | null;
  [DEV_LINUX_CALENDAR_SYNC_ENABLED]: boolean;
  [DEV_WINDOWS_CALENDAR_SYNC_ENABLED]: boolean;
  [DEV_CALENDAR_AI_ACCESS_MODE]: 'off' | 'busy_only' | 'full_details';
  /** RFC3339 timestamp of the last "viewed Diagnostics" event. */
  [DEV_ERROR_LOGS_LAST_VIEWED_AT]: string | null;
  /** RFC3339 timestamp of the celebrated first capture; absence === not yet. */
  [DEV_FIRST_TASK_CELEBRATED]: string | null;
  [DEV_ONBOARDING_DISMISSED]: boolean;
  /** Completed onboarding step ids, persisted as a canonical JSON array. */
  [DEV_ONBOARDING_PREVIOUSLY_DONE]: readonly string[];
  [DEV_FOCUS_SESSION_TRIED]: boolean;
  [DEV_ONBOARDING_COMPLETION_HINT_DISMISSED]: boolean;
  /** Persisted UI view-state snapshot (sidebar selection, scroll, …). */
  [DEV_UI_VIEW_STATE]: unknown;
  /** Next assistant-UI command payload; `null` clears the slot. */
  [DEV_ASSISTANT_UI_COMMAND]: unknown;
  /** Most recently handled assistant-UI command id; `null` clears. */
  [DEV_ASSISTANT_UI_COMMAND_HANDLED_ID]: string | null;
}

type _AssertDeviceStateShape = DeviceStateValueShape extends Record<DeviceStateKey, unknown>
  ? true
  : never;
const _assertDeviceStateShape: _AssertDeviceStateShape = true;
void _assertDeviceStateShape;

/**
 * Resolve a preference key's expected JS value type. Used as the
 * `value` parameter type for `setPreference<K>(key, value)`.
 */
export type PreferenceValueOf<K extends PreferenceKey> = PreferenceValueShape[K];

/**
 * Resolve a device-state key's expected JS value type. Used as the
 * `value` parameter type for `setDeviceState<K>(key, value)`.
 */
export type DeviceStateValueOf<K extends DeviceStateKey> = DeviceStateValueShape[K];
