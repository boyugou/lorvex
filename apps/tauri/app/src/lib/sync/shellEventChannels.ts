/**
 * Frontend mirrors of the canonical Tauri event-channel names defined
 * in `app/src-tauri/src/event_channels.rs`. The Rust side cannot export
 * its `pub const` strings to TypeScript, so any rename has to land in
 * BOTH files in the same change. Centralizing the literals here keeps
 * the surface area visible in one place rather than scattering raw
 * strings across hooks.
 */

/** Non-blocking informational toast, payload `{ kind, i18n_key }`. */
export const SYNC_NOTICE_EVENT = 'lorvex://sync-notice';

/** "Reset all data" failure / partial-success notice. */
export const DATA_RESET_FAILED_EVENT = 'lorvex://data-reset-failed';

/** Notification-center action (Complete / Snooze / …) failed to apply. */
export const NOTIFICATION_ACTION_ERROR_EVENT = 'lorvex://notification-action-error';
