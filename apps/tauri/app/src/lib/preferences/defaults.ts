/**
 * Canonical default values for preference keys, keyed by the same string
 * constants in `preferenceKeys.ts`. Used by the Settings "Restore defaults"
 * affordance so every per-category reset button can read one
 * authoritative value instead of duplicating literals across UI files.
 *
 * Scope. Only preferences whose default is meaningful to surface in a
 * reset button are listed here. Purely device-local state (widget paths,
 * notification permission latches) and JSON-structural preferences whose
 * defaults are complex (sidebar module config, sync backend configs) are
 * intentionally omitted — those either have their own dedicated reset
 * controls or belong to the global-reset path.
 *
 * The Rust side has no single registry; defaults are computed in the
 * various `commands/preferences.rs` readers. Keeping the TS-facing
 * defaults here means the Restore button matches what the UI renders
 * (the `parse*` defaults in `usePreference`) and never diverges from a
 * Rust-internal fallback used by an MCP tool.
 */

import {
  DEFAULT_APPEARANCE_PROFILE,
  DEFAULT_THEME_MODE,
} from '../theme/model';
import { DEFAULT_HIDE_COMPLETED_OLDER_THAN_DAYS } from '../hideCompletedOlderThan';
import {
  PREF_AI_BRIEFING_ENABLED,
  PREF_AI_CHANGELOG_RETENTION_POLICY,
  PREF_APPEARANCE_PROFILE,
  PREF_ERROR_LOG_RETENTION_DAYS,
  PREF_FONT_SCALE,
  PREF_HIDE_COMPLETED_OLDER_THAN_DAYS,
  PREF_MORNING_BRIEFING_TIME,
  PREF_THEME,
  PREF_WEEKLY_REVIEW_DAY,
  PREF_WEEKLY_REVIEW_TIME,
  PREF_WORKING_HOURS,
  type PreferenceKey,
} from './keys';

/**
 * Raw default value for a preference, in the same shape the UI parses
 * after reading via `getPreference`. `null` is a legitimate default for
 * nullable preferences (e.g. "keep changelog forever" is the absence of
 * a retention window).
 */
export type PreferenceDefaultValue =
  | null
  | boolean
  | number
  | string
  | readonly PreferenceDefaultValue[]
  | { readonly [key: string]: PreferenceDefaultValue };

export const PREFERENCE_DEFAULTS: Partial<Record<PreferenceKey, PreferenceDefaultValue>> = {
  [PREF_THEME]: DEFAULT_THEME_MODE,
  [PREF_APPEARANCE_PROFILE]: DEFAULT_APPEARANCE_PROFILE,
  [PREF_FONT_SCALE]: 1.0,
  [PREF_AI_BRIEFING_ENABLED]: true,
  [PREF_AI_CHANGELOG_RETENTION_POLICY]: null,
  [PREF_ERROR_LOG_RETENTION_DAYS]: null,
  [PREF_HIDE_COMPLETED_OLDER_THAN_DAYS]: DEFAULT_HIDE_COMPLETED_OLDER_THAN_DAYS,
  [PREF_WORKING_HOURS]: { start: '09:00', end: '18:00' },
  [PREF_MORNING_BRIEFING_TIME]: '08:00',
  [PREF_WEEKLY_REVIEW_DAY]: 'sunday',
  [PREF_WEEKLY_REVIEW_TIME]: '18:00',
};

/**
 * Grouped category bundles for "Restore defaults" buttons that reset an
 * entire section's worth of preferences at once. The Restore Defaults UI
 * iterates one of these arrays and writes each default through the
 * usual `setPreference` path; the undo toast that surfaces gets a single
 * token that rolls the entire bundle back.
 */
export const APPEARANCE_DEFAULT_KEYS: readonly PreferenceKey[] = [
  PREF_THEME,
  PREF_APPEARANCE_PROFILE,
  PREF_FONT_SCALE,
];

export const RETENTION_DEFAULT_KEYS: readonly PreferenceKey[] = [
  PREF_AI_CHANGELOG_RETENTION_POLICY,
  PREF_ERROR_LOG_RETENTION_DAYS,
  PREF_HIDE_COMPLETED_OLDER_THAN_DAYS,
];

/** Read the canonical default for `key`. Returns `undefined` when the
 *  key has no registered default — callers should fall back to a no-op
 *  or surface a "no default" diagnostic rather than silently writing
 *  `null`. */
export function getPreferenceDefault(key: PreferenceKey): PreferenceDefaultValue | undefined {
  return Object.prototype.hasOwnProperty.call(PREFERENCE_DEFAULTS, key)
    ? PREFERENCE_DEFAULTS[key]
    : undefined;
}
