/**
 * Notification system — polls for due reminders and fires native notifications.
 * Also handles scheduled morning briefing and weekly review prompts.
 */
import { useCallback, useEffect, useRef, useState } from 'react';

import { confirm } from '../dialogs/confirm';
import { reportClientError } from '../errors/errorLogging';
import { useI18n } from '../i18n';
import { getDeviceState, setDeviceState } from '@/lib/ipc/settings';
import { getUpcomingReminders } from '@/lib/ipc/tasks/queries';
import {
  createBrowserNativeCalendarAutoSyncIntervalHost,
  installNativeCalendarAutoSyncRuntime,
} from '../nativeCalendarAutoSync.runtime';
import { getNativeCalendarRuntimeConfig } from '../nativeCalendarRuntime';
import {
  createBrowserAtRiskNotificationsHost,
  installAtRiskNotificationsRuntime,
} from './atRisk.runtime';
import { parseBooleanPreference } from '../preferences/parser';
import {
  createBrowserReminderPollingHost,
  installReminderPollingRuntime,
} from './reminderPolling.runtime';
import {
  createBrowserScheduledNotificationsIntervalHost,
  installScheduledNotificationsRuntime,
} from './scheduled.runtime';
import { installNotificationPermissionPromptRuntime } from './permissionPrompt.runtime';
import {
  getNotificationPermissionPromptDeviceState,
  setNotificationPermissionPromptDeviceState,
} from './permissionPrompt.persistence';
import {
  createBrowserNotificationPermissionStatusWatchHost,
  installNotificationPermissionStatusWatchRuntime,
  probeNotificationPermissionStatusRuntime,
  requestNotificationPermissionAgainRuntime,
} from './permissionStatus.runtime';
import { registerNotificationActions } from './actions';
import { DEV_NOTIFICATION_PERMISSION_GRANTED, DEV_NOTIFICATION_PERMISSION_PROMPTED } from '../preferences/keys';
import type { RuntimeProfile } from '../platform/platform';
import {
  AT_RISK_POLL_MS,
  REMINDER_POLL_MS,
  REMINDER_URGENT_MS,
  SCHEDULE_POLL_MS,
  checkAtRiskDeadlines,
  checkHabitReminders,
  checkReminders,
  checkScheduled,
  refreshNotificationPermissionCache,
} from './runtime';

// CONTRACT: every host below MUST remain stateless. Vite HMR does
// NOT reset module-level `const` values across reloads, and React
// StrictMode mounts effects twice in development. If a future change
// adds in-host state (e.g. a counter, a `WeakSet` of subscribers,
// last-fired-at memo) to any of these factories, the value will be
// silently shared across all mount cycles in dev — re-introducing the
// class of StrictMode/HMR bugs these polling hosts were split to avoid.
// To add stateful behavior, move that host's construction
// INSIDE the effect that consumes it (and remove its declaration
// from this block).
const scheduledNotificationsIntervalHost = createBrowserScheduledNotificationsIntervalHost();
const nativeCalendarAutoSyncIntervalHost = createBrowserNativeCalendarAutoSyncIntervalHost();
const reminderPollingBrowserHost = createBrowserReminderPollingHost();
const atRiskNotificationsBrowserHost = createBrowserAtRiskNotificationsHost();
const notificationPermissionStatusWatchHost = createBrowserNotificationPermissionStatusWatchHost();

export function useReminderNotifications(): void {
  const runningRef = useRef(false);

  useEffect(() => {
    // Audit notif#1: force an immediate tick whenever the window
    // comes back to the foreground. While the document is hidden,
    // the renderer aggressively throttles setInterval (≥1/min, or
    // suspends entirely depending on platform). A reminder that
    // came due during sleep / hidden-state therefore could be
    // delayed by minutes. The catch-up via dedup in
    // `notifiedReminderKeys` + `mark_reminder_notified` makes this
    // safe to fire on every resume.
    const handle = installReminderPollingRuntime({
      checkReminders,
      getUpcomingReminders,
      registerNotificationActions,
      reportActionRegistrationError: (error) => {
        reportClientError(
          'notifications.actionRegistration',
          'Failed to register notification action handlers',
          error,
          undefined,
          'warn',
        );
      },
      reportCadenceError: (error) => {
        reportClientError(
          'notifications.reminderCadence',
          'Failed to probe upcoming reminders for adaptive polling',
          error,
          undefined,
          'warn',
        );
      },
      state: {
        get running() {
          return runningRef.current;
        },
        set running(value) {
          runningRef.current = value;
        },
      },
      pollIntervalMs: REMINDER_POLL_MS,
      urgentIntervalMs: REMINDER_URGENT_MS,
      urgentLookaheadMinutes: 120,
      ...reminderPollingBrowserHost,
    });

    return handle.dispose;
  }, []);
}

export function useScheduledNotifications(): void {
  const runningRef = useRef(false);

  // Scheduled notifications (morning briefing, weekly review, habit
  // reminders) MUST keep ticking while the window is hidden, so the
  // briefing's 08:00 quiet-hours-retry loop doesn't silently stop
  // whenever the user's window isn't foreground. The ticks are all
  // idempotent (dedup via notifiedReminderKeys / notifiedHabitKeys /
  // per-day DB state), the interval is 60 s, and Chromium throttles
  // hidden setInterval to exactly that cadence, so always-on costs
  // nothing beyond what a visibility-gated interval would pay on
  // resume.
  useEffect(() => {
    const handle = installScheduledNotificationsRuntime({
      checkScheduled,
      checkHabitReminders,
      reportTickError: (error) => {
        reportClientError(
          'notifications.scheduledRuntime',
          'Scheduled notification runtime failed',
          error,
          undefined,
          'warn',
        );
      },
      state: {
        get running() {
          return runningRef.current;
        },
        set running(value) {
          runningRef.current = value;
        },
      },
      pollIntervalMs: SCHEDULE_POLL_MS,
      ...scheduledNotificationsIntervalHost,
    });
    return handle.dispose;
  }, []);
}

export function useNotificationPermissionPrompt(enabled = true): void {
  const { t } = useI18n();
  // the native OS notification dialog was previously
  // fired on app boot with zero context, causing most first-time
  // users to reflexively click "Don't Allow" — after which reminders,
  // briefings, and at-risk deadlines silently never fire. We now
  // gate the OS prompt behind an in-app explainer (`confirm()`) so
  // the user understands what they're granting. The explainer is an
  // imperative async Promise, so we guard with a launch-scoped ref
  // to ensure it can only be spawned once per mount even under
  // StrictMode double-invocation or prop re-render.
  const launchedRef = useRef(false);
  useEffect(() => {
    const handle = installNotificationPermissionPromptRuntime({
      confirmPrompt: () => confirm({
        title: t('notifications.prePromptTitle'),
        message: t('notifications.prePromptMessage'),
        confirmLabel: t('notifications.prePromptConfirm'),
        cancelLabel: t('notifications.prePromptCancel'),
      }),
      enabled,
      getPrompted: async () => parseBooleanPreference(
        await getNotificationPermissionPromptDeviceState({
          getDeviceState,
          setDeviceState,
        }, DEV_NOTIFICATION_PERMISSION_PROMPTED),
      ),
      loadNotificationPlugin: async () => import('@tauri-apps/plugin-notification'),
      refreshNotificationPermissionCache,
      reportPromptError: (error) => {
        reportClientError(
          'notifications.permissionPrompt',
          'Failed to check or request notification permission',
          error,
          undefined,
          'warn',
        );
      },
      setGranted: async (granted, isCancelled) => {
        await setNotificationPermissionPromptDeviceState({
          getDeviceState,
          setDeviceState,
        }, DEV_NOTIFICATION_PERMISSION_GRANTED, granted, isCancelled);
      },
      setPrompted: async (prompted, isCancelled) => {
        await setNotificationPermissionPromptDeviceState({
          getDeviceState,
          setDeviceState,
        }, DEV_NOTIFICATION_PERMISSION_PROMPTED, prompted, isCancelled);
      },
      state: {
        get launched() {
          return launchedRef.current;
        },
        set launched(value) {
          launchedRef.current = value;
        },
      },
    });

    return handle.dispose;
  }, [enabled, t]);
}

/**
 * return the current OS notification permission state
 * so UI can surface "denied — reminders won't fire" affordances.
 *
 * On mount, and on every window focus / visibility event, re-probes
 * `notification.isPermissionGranted()` and keeps the
 * `DEV_NOTIFICATION_PERMISSION_GRANTED` device-state row in sync —
 * the user can grant/revoke in System Settings while Lorvex is
 * running, so a stale persisted value otherwise lies. When the
 * state flips from granted → denied, writes one warn-level
 * `error_logs` row so Settings → Diagnostics shows the transition.
 *
 * Returns `{ promptedButDenied, requestAgain }`. `promptedButDenied`
 * is true iff the OS has been asked before AND the current answer
 * is no — that's the banner-visible case. Not-yet-asked state
 * returns false so the banner stays hidden while
 * `useNotificationPermissionPrompt` still owns the first-run flow.
 */
export function useNotificationPermissionStatus(enabled = true): {
  promptedButDenied: boolean;
  requestAgain: () => Promise<void>;
} {
  const [promptedButDenied, setPromptedButDenied] = useState(false);

  const probe = useCallback(async () => {
    await probeNotificationPermissionStatusRuntime({
      getPersistedGranted: async () => parseBooleanPreference(
        await getNotificationPermissionPromptDeviceState({
          getDeviceState,
          setDeviceState,
        }, DEV_NOTIFICATION_PERMISSION_GRANTED),
      ),
      getPrompted: async () => parseBooleanPreference(
        await getNotificationPermissionPromptDeviceState({
          getDeviceState,
          setDeviceState,
        }, DEV_NOTIFICATION_PERMISSION_PROMPTED),
      ),
      loadNotificationPlugin: async () => import('@tauri-apps/plugin-notification'),
      refreshNotificationPermissionCache,
      reportProbeError: (error) => {
        reportClientError(
          'notifications.permission',
          'Failed to probe notification permission',
          error,
          undefined,
          'warn',
        );
      },
      reportRevokedWhileRunning: () => {
        reportClientError(
          'notifications.permission',
          'OS notification permission revoked while app running',
          undefined,
          undefined,
          'warn',
        );
      },
      setPersistedGranted: async (granted) => {
        await setNotificationPermissionPromptDeviceState({
          getDeviceState,
          setDeviceState,
        }, DEV_NOTIFICATION_PERMISSION_GRANTED, granted, () => false);
      },
      setPromptedButDenied,
    });
  }, []);

  useEffect(() => {
    return installNotificationPermissionStatusWatchRuntime({
      enabled,
      probe,
      reportWatchError: (error) => {
        reportClientError(
          'notifications.permissionWatch',
          'Notification permission watcher failed',
          error,
          undefined,
          'warn',
        );
      },
      ...notificationPermissionStatusWatchHost,
    });
  }, [enabled, probe]);

  const requestAgain = useCallback(async () => {
    await requestNotificationPermissionAgainRuntime({
      loadNotificationPlugin: async () => import('@tauri-apps/plugin-notification'),
      refreshNotificationPermissionCache,
      reportRequestError: (error) => {
        reportClientError(
          'notifications.permission',
          'Failed to re-request notification permission',
          error,
          undefined,
          'warn',
        );
      },
      setPersistedGranted: async (granted) => {
        await setNotificationPermissionPromptDeviceState({
          getDeviceState,
          setDeviceState,
        }, DEV_NOTIFICATION_PERMISSION_GRANTED, granted, () => false);
      },
      setPromptedButDenied,
    });
  }, []);

  return { promptedButDenied, requestAgain };
}

export function useAtRiskNotifications(enabled = true): void {
  const runningRef = useRef(false);

  // due-soon warnings should follow the same always-on
  // scheduler model as morning briefing / weekly review / habit
  // reminders. Visibility-gated polling silently drops background
  // alerts until the user foregrounds the window, which defeats the
  // point of a native warning.
  useEffect(() => {
    const handle = installAtRiskNotificationsRuntime({
      checkAtRiskDeadlines,
      enabled,
      reportTickError: (error) => {
        reportClientError(
          'notifications.atRiskRuntime',
          'At-risk deadline notification runtime failed',
          error,
          undefined,
          'warn',
        );
      },
      state: {
        get running() {
          return runningRef.current;
        },
        set running(value) {
          runningRef.current = value;
        },
      },
      pollIntervalMs: AT_RISK_POLL_MS,
      ...atRiskNotificationsBrowserHost,
    });
    return handle.dispose;
  }, [enabled]);
}

/** How often to re-sync native calendar events (15 minutes). */
const NATIVE_CALENDAR_RESYNC_MS = 15 * 60 * 1000;

/** Auto-sync the current runtime's native calendar adapter on app launch and every 15 minutes. */
export function useNativeCalendarAutoSync(runtimeProfile: RuntimeProfile): void {
  const firedRef = useRef(false);

  useEffect(() => {
    const nativeCalendarConfig = getNativeCalendarRuntimeConfig(runtimeProfile);
    const handle = installNativeCalendarAutoSyncRuntime({
      config: nativeCalendarConfig,
      getDeviceState,
      reportSyncError: (error) => {
        reportClientError(
          'notifications.nativeCalendarAutoSync',
          'Native calendar auto-sync failed',
          error,
          undefined,
          'warn',
        );
      },
      state: {
        get firedInitialSync() {
          return firedRef.current;
        },
        set firedInitialSync(value) {
          firedRef.current = value;
        },
      },
      syncIntervalMs: NATIVE_CALENDAR_RESYNC_MS,
      ...nativeCalendarAutoSyncIntervalHost,
    });

    return handle.dispose;
  }, [runtimeProfile]);
}
