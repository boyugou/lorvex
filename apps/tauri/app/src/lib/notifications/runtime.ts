import { buildDayContext, getMinutesSinceMidnightInTimezone, getWeekdayNameInTimezone, resolveConfiguredTimezone } from '../dayContext';
import { reportClientError } from '../errors/errorLogging';
import {
  formatNotificationDueSoonTaskCountLabel,
  formatNotificationFocusTaskCountLabel,
  formatNotificationOverdueTaskCountLabel,
} from '../dates/i18nCountPhrases';
import { truncateGraphemes } from '../textTruncate';
import { getDueHabitReminders, markHabitReminderFired } from '@/lib/ipc/habits';
import { setBadgeCount } from '@/lib/ipc/runtime';
import { getDeviceState, getPreference, getPreferences, setDeviceState } from '@/lib/ipc/settings';
import { getDueReminders, getUpcomingReminders, getUpcomingTasks, markReminderNotified } from '@/lib/ipc/tasks/queries';
import { getOverview } from '@/lib/ipc/tasks/reviews';
import { reminderNotificationKey } from './taskKey';
import {
  DEV_AT_RISK_NOTIFICATION_LAST_FIRED,
  DEV_MORNING_BRIEFING_LAST_FIRED,
  DEV_WEEKLY_REVIEW_LAST_FIRED,
  PREF_LANGUAGE,
  PREF_MORNING_BRIEFING_TIME,
  PREF_NOTIFICATION_MUTED_LISTS,
  PREF_NOTIFICATION_SOUND_ENABLED,
  PREF_QUIET_HOURS_END,
  PREF_QUIET_HOURS_START,
  PREF_TIMEZONE,
  PREF_WEEKLY_REVIEW_DAY,
  PREF_WEEKLY_REVIEW_TIME,
} from '../preferences/keys';
import { parseBooleanPreference, parseStringArrayPreference, parseStringPreference } from '../preferences/parser';
import { timeToMinutes } from '../timeUtils';

import {
  parseTimePreference,
  parseWeekdayPreference,
  resolveNotificationLocale,
  translatorFor,
} from './preferences';
import {
  countReminderBadgeEntries,
  isQuietHoursWindow,
  type NotificationSendResult,
  selectReminderEntriesToNotify,
  shouldFireDailyScheduledNotification,
  shouldFireWeeklyScheduledNotification,
  shouldMuteTaskNotification,
} from './runtime.logic';
import {
  createBrowserNotificationPermissionVisibilityRefreshHost,
  installNotificationPermissionVisibilityRefreshRuntime,
  refreshNotificationPermissionCacheState,
  sendNotificationRuntime,
  type NotificationOptions,
  type PermissionCache,
} from './runtime.runtime';
import { TASK_STATUS } from '@lorvex/shared/types';

export const REMINDER_POLL_MS = 30_000;
export const REMINDER_URGENT_MS = 5_000;
export const SCHEDULE_POLL_MS = 60_000;
export const AT_RISK_POLL_MS = 15 * 60_000;

const notifiedReminderKeys = new Set<string>();

/**
 * Check if the current time falls within the user's quiet hours window.
 * Quiet hours span from `quiet_hours_start` to `quiet_hours_end` (HH:MM format).
 * Supports overnight spans (e.g., 22:00 to 07:00).
 */
async function isInQuietHours(): Promise<boolean> {
  try {
    // one SELECT fans out all three prefs instead of
    // three IPC round-trips.
    const prefs = await getPreferences([
      PREF_QUIET_HOURS_START,
      PREF_QUIET_HOURS_END,
      PREF_TIMEZONE,
    ]);
    const startRaw = prefs.get(PREF_QUIET_HOURS_START) ?? null;
    const endRaw = prefs.get(PREF_QUIET_HOURS_END) ?? null;
    const timezoneRaw = prefs.get(PREF_TIMEZONE) ?? null;
    if (!startRaw || !endRaw) return false;
    const start = parseTimePreference(startRaw, '');
    const end = parseTimePreference(endRaw, '');
    if (!start || !end) return false;

    const timezone = resolveConfiguredTimezone(timezoneRaw);
    const nowMinutes = getMinutesSinceMidnightInTimezone(timezone);
    const startMinutes = timeToMinutes(start);
    const endMinutes = timeToMinutes(end);

    return isQuietHoursWindow(nowMinutes, startMinutes, endMinutes);
  } catch {
    return false;
  }
}

const permissionCacheState: { current: PermissionCache } = { current: null };
const notificationPermissionVisibilityRefreshHost = createBrowserNotificationPermissionVisibilityRefreshHost();

export function refreshNotificationPermissionCache(): void {
  refreshNotificationPermissionCacheState(permissionCacheState);
}

// Re-probe on tab visibility changes so toggling permission in macOS
// System Settings → Notifications and returning to the app recovers
// without a reload. Fires exactly once on load (StrictMode double-
// invoke in dev is harmless — both registrations share the same cache).
installNotificationPermissionVisibilityRefreshRuntime({
  ...notificationPermissionVisibilityRefreshHost,
  refreshPermissionCache: refreshNotificationPermissionCache,
});

async function sendNotification(opts: NotificationOptions): Promise<NotificationSendResult> {
  return sendNotificationRuntime({
    cacheState: permissionCacheState,
    getSoundEnabled: async () => {
      const soundEnabledRaw = await getPreference(PREF_NOTIFICATION_SOUND_ENABLED);
      return parseBooleanPreference(soundEnabledRaw, true);
    },
    isInQuietHours,
    loadNotificationPlugin: async () => import('@tauri-apps/plugin-notification'),
    options: opts,
    reportDispatchError: (error) => {
      reportClientError(
        'notifications.send',
        'Failed to dispatch native notification',
        error,
      );
    },
    reportPermissionDenied: (error) => {
      reportClientError(
        'notifications.send',
        'Notifications permission denied — suppressing further attempts this session',
        error,
      );
    },
  });
}

// Cache the most recent successful muted-list fetch so an IPC outage
// (transient Tauri channel failure, settings backend stall) doesn't
// silently treat every list as un-muted and fire notifications a
// user already opted out of. `parseStringArrayPreference` is total
// — empty or malformed payloads collapse to `[]` without throwing
// — so the only catch path is a true IPC failure.
let lastKnownMutedLists: Set<string> | null = null;

/**
 * Resolve the muted-list-id set for notification filtering.
 *
 * Returns `null` only when the IPC fetch fails AND no prior
 * successful fetch has populated the cache. Callers MUST treat
 * `null` as "filtering unavailable" and skip the notification
 * dispatch rather than firing on every list — collapsing the IPC
 * error into an empty `Set` would notify on muted lists whenever
 * the IPC was down.
 *
 * On IPC failure with a previously-cached set, the cached set is
 * returned so transient outages converge to "last user-known
 * preference" rather than "fire everything".
 */
async function getMutedListIds(): Promise<Set<string> | null> {
  try {
    const raw = await getPreference(PREF_NOTIFICATION_MUTED_LISTS);
    const set = new Set(parseStringArrayPreference(raw));
    lastKnownMutedLists = set;
    return set;
  } catch (error) {
    reportClientError(
      'notifications.getMutedListIds',
      'Failed to fetch muted-list preference; reusing last-known set if any',
      error,
    );
    return lastKnownMutedLists;
  }
}

async function refreshReminderBadge(): Promise<void> {
  try {
    const upcoming = await getUpcomingReminders();
    const badgeMutedLists = await getMutedListIds();
    if (badgeMutedLists === null) {
      // IPC for the muted-list pref is down with no prior cached
      // value — skip the badge refresh rather than overcounting
      // reminders the user muted. The next successful poll will
      // converge.
      return;
    }
    const pendingCount = countReminderBadgeEntries(upcoming, badgeMutedLists);
    await setBadgeCount(pendingCount > 0 ? pendingCount : null);
  } catch {
    // Non-critical — badge update failure should not block reminder flow
  }
}

export async function checkReminders(): Promise<void> {
  try {
    const [locale, mutedLists] = await Promise.all([
      resolveNotificationLocale(await getPreference(PREF_LANGUAGE)),
      getMutedListIds(),
    ]);
    if (mutedLists === null) {
      // IPC for the muted-list pref is down with no prior cached
      // value — short-circuit reminder dispatch rather than firing
      // on every list. The next successful poll resumes normal
      // operation.
      return;
    }
    const t = await translatorFor(locale);
    const entries = await getDueReminders();
    const unseen = selectReminderEntriesToNotify(
      entries,
      mutedLists,
      notifiedReminderKeys,
    );

    const tryMarkNotified = async (reminderId: string): Promise<boolean> => {
      try {
        await markReminderNotified(reminderId);
        return true;
      } catch (error) {
        reportClientError(
          'notifications.markReminderNotified',
          'Failed to mark reminder as notified after dispatching notification',
          error,
          reminderId,
        );
        return false;
      }
    };

    if (unseen.length > 0) {
      // Always send individual notifications so each retains action buttons
      // (Complete / Snooze). No burst-grouping — losing action buttons is worse
      // than receiving several actionable notifications at once.
      for (const { task, reminder } of unseen) {
        const body = task.ai_notes
          ? truncateGraphemes(task.ai_notes, 200, false)
          : task.due_date
            ? `${t('notifications.duePrefix')}: ${task.due_date}${task.due_time ? ` ${task.due_time}` : ''}`
            : undefined;

        const sendResult = await sendNotification({
          title: task.title,
          ...(body != null && { body }),
          actionTypeId: 'task-reminder',
          extra: { taskId: task.id },
        });
        if (sendResult !== 'sent') continue;

        // Add to the in-memory dedup set BEFORE the DB call so that a
        // `markReminderNotified` failure does NOT cause the same
        // notification to fire again on the next poll tick. The habit
        // reminder path already does this correctly; the task path was
        // gating on DB success, which caused duplicates on transient
        // DB errors (R20 audit fix).
        notifiedReminderKeys.add(reminderNotificationKey(reminder));
        await tryMarkNotified(reminder.id);
      }

      if (notifiedReminderKeys.size > 1000) {
        const keep = new Set<string>();
        entries.forEach(({ reminder }) => keep.add(reminderNotificationKey(reminder)));
        notifiedReminderKeys.clear();
        keep.forEach(key => notifiedReminderKeys.add(key));
      }
    }
  } catch (error) {
    reportClientError('notifications.checkReminders', 'Reminder polling failed', error);
  } finally {
    // Keep the dock badge converging even when the reminder-dispatch path
    // itself throws; otherwise transient IPC/locale/dedup errors can leave
    // a stale count visible until the next clean poll.
    await refreshReminderBadge();
  }
}

async function checkMorningBriefing(): Promise<void> {
  try {
    // 3 preference reads batched into one IPC.
    // The getDeviceState call stays separate — it's a different
    // backend table with its own SELECT.
    const [prefs, lastFiredRaw] = await Promise.all([
      getPreferences([PREF_MORNING_BRIEFING_TIME, PREF_LANGUAGE, PREF_TIMEZONE]),
      getDeviceState(DEV_MORNING_BRIEFING_LAST_FIRED),
    ]);
    const timeRaw = prefs.get(PREF_MORNING_BRIEFING_TIME) ?? null;
    const localeRaw = prefs.get(PREF_LANGUAGE) ?? null;
    const timezoneRaw = prefs.get(PREF_TIMEZONE) ?? null;
    const locale = resolveNotificationLocale(localeRaw);
    const t = await translatorFor(locale);
    const timezone = resolveConfiguredTimezone(timezoneRaw);
    const dayContext = buildDayContext(timezone);

    const briefingTime = parseTimePreference(timeRaw, '08:00');
    const lastFired = parseStringPreference(lastFiredRaw, '');
    const today = dayContext.todayYmd;

    if (!shouldFireDailyScheduledNotification({
      lastFired,
      today,
      nowMinutes: getMinutesSinceMidnightInTimezone(timezone),
      targetMinutes: timeToMinutes(briefingTime),
    })) return;

    const overview = await getOverview();
    const focusCount = overview.current_focus?.task_count ?? 0;
    const overdueCount = overview.stats.overdue_count;
    const briefing = overview.current_focus?.briefing;

    let body: string;
    if (briefing) {
      body = truncateGraphemes(briefing, 120, false);
    } else {
      const parts: string[] = [];
      if (focusCount > 0) parts.push(formatNotificationFocusTaskCountLabel(locale, focusCount, t));
      if (overdueCount > 0) parts.push(formatNotificationOverdueTaskCountLabel(locale, overdueCount, t));
      body = parts.length > 0 ? parts.join(' · ') : t('notifications.haveGreatDay');
    }

    const sendResult = await sendNotification({ title: t('notifications.morningTitle'), body });
    // Only record the fire date if the notification was actually delivered.
    // If suppressed by quiet hours, we retry on the next poll cycle after
    // quiet hours end. Permission-denied is also a "not sent" — retry is
    // harmless since the OS will keep blocking it.
    if (sendResult === 'sent') {
      await setDeviceState(DEV_MORNING_BRIEFING_LAST_FIRED, today);
    }
  } catch (error) {
    reportClientError('notifications.checkMorningBriefing', 'Morning briefing notification failed', error);
  }
}

async function checkWeeklyReview(): Promise<void> {
  try {
    // 4 preference reads batched into one IPC.
    const [prefs, lastFiredRaw] = await Promise.all([
      getPreferences([
        PREF_WEEKLY_REVIEW_DAY,
        PREF_WEEKLY_REVIEW_TIME,
        PREF_LANGUAGE,
        PREF_TIMEZONE,
      ]),
      getDeviceState(DEV_WEEKLY_REVIEW_LAST_FIRED),
    ]);
    const dayRaw = prefs.get(PREF_WEEKLY_REVIEW_DAY) ?? null;
    const timeRaw = prefs.get(PREF_WEEKLY_REVIEW_TIME) ?? null;
    const localeRaw = prefs.get(PREF_LANGUAGE) ?? null;
    const timezoneRaw = prefs.get(PREF_TIMEZONE) ?? null;
    const locale = resolveNotificationLocale(localeRaw);
    const t = await translatorFor(locale);
    const timezone = resolveConfiguredTimezone(timezoneRaw);
    const dayContext = buildDayContext(timezone);

    const reviewDay = parseWeekdayPreference(dayRaw, 'friday');
    const reviewTime = parseTimePreference(timeRaw, '16:00');
    const lastFired = parseStringPreference(lastFiredRaw, '');
    const today = dayContext.todayYmd;

    if (!shouldFireWeeklyScheduledNotification({
      lastFired,
      today,
      nowMinutes: getMinutesSinceMidnightInTimezone(timezone),
      targetMinutes: timeToMinutes(reviewTime),
      todayDayName: getWeekdayNameInTimezone(timezone),
      targetDayName: reviewDay,
    })) return;

    const sendResult = await sendNotification({
      title: t('notifications.weeklyReviewTitle'),
      body: t('notifications.weeklyReviewBody'),
    });
    // Only record the fire date if actually sent. If suppressed by quiet
    // hours, retry on the next poll cycle after quiet hours end.
    if (sendResult === 'sent') {
      await setDeviceState(DEV_WEEKLY_REVIEW_LAST_FIRED, today);
    }
  } catch (error) {
    reportClientError('notifications.checkWeeklyReview', 'Weekly review notification failed', error);
  }
}

const notifiedHabitKeys = new Set<string>();

export async function checkHabitReminders(): Promise<void> {
  try {
    // 2 preference reads batched into one IPC.
    const prefs = await getPreferences([PREF_LANGUAGE, PREF_TIMEZONE]);
    const localeRaw = prefs.get(PREF_LANGUAGE) ?? null;
    const timezoneRaw = prefs.get(PREF_TIMEZONE) ?? null;
    const locale = resolveNotificationLocale(localeRaw);
    const t = await translatorFor(locale);
    const timezone = resolveConfiguredTimezone(timezoneRaw);
    const today = buildDayContext(timezone).todayYmd;

    const entries = await getDueHabitReminders();
    // Scope dedup keys by date so that a habit reminder that was
    // already fired today doesn't block delivery tomorrow when the
    // app stays running across midnight. Without the date scope, the
    // in-memory set retains `policy.id` indefinitely and
    // `checkHabitReminders` filters it as "already seen" even though
    // the backend correctly identifies it as due for the new day
    // (R20 audit fix).
    const unseen = entries.filter(
      ({ policy }) => !notifiedHabitKeys.has(`${policy.id}:${today}`),
    );

    if (unseen.length === 0) return;

    for (const { policy } of unseen) {
      const body = `${t('notifications.habitReminderBody')} · ${policy.reminder_time}`;
      // policy.habit_name is optional in the shared
      // type (only populated when the read path joins habits). The
      // Tauri `get_habit_reminder_policies` IPC always joins, so this
      // fallback is defensive.
      const sendResult = await sendNotification({ title: policy.habit_name ?? '', body });
      if (sendResult !== 'sent') continue;

      notifiedHabitKeys.add(`${policy.id}:${today}`);
      try {
        await markHabitReminderFired(policy.id);
      } catch (error) {
        reportClientError(
          'notifications.markHabitReminderFired',
          'Failed to mark habit reminder as fired',
          error,
          policy.id,
        );
      }
    }

    if (notifiedHabitKeys.size > 500) {
      const keep = new Set<string>();
      entries.forEach(({ policy }) => keep.add(`${policy.id}:${today}`));
      notifiedHabitKeys.clear();
      keep.forEach(key => notifiedHabitKeys.add(key));
    }
  } catch (error) {
    reportClientError('notifications.checkHabitReminders', 'Habit reminder polling failed', error);
  }
}

export async function checkScheduled(): Promise<void> {
  await checkMorningBriefing();
  await checkWeeklyReview();
}

export async function checkAtRiskDeadlines(): Promise<void> {
  try {
    // 2 preference reads batched into one IPC.
    const [prefs, lastFiredRaw, upcoming] = await Promise.all([
      getPreferences([PREF_LANGUAGE, PREF_TIMEZONE]),
      getDeviceState(DEV_AT_RISK_NOTIFICATION_LAST_FIRED),
      getUpcomingTasks(1),
    ]);
    const locale = resolveNotificationLocale(prefs.get(PREF_LANGUAGE) ?? null);
    const t = await translatorFor(locale);
    const timezone = resolveConfiguredTimezone(prefs.get(PREF_TIMEZONE) ?? null);
    const today = buildDayContext(timezone).todayYmd;

    // Suppress if already fired today (persisted across restarts)
    if (parseStringPreference(lastFiredRaw, '') === today) return;

    const mutedLists = await getMutedListIds();
    if (mutedLists === null) {
      // IPC for the muted-list pref is down with no prior cached
      // value — skip the at-risk notification rather than firing on
      // every list.
      return;
    }
    const unseen = upcoming
      .filter(task => task.status === TASK_STATUS.open && task.due_date)
      .filter(task => !shouldMuteTaskNotification(task.list_id, mutedLists));

    if (unseen.length === 0) return;

    const first = unseen[0]!;
    const dueSummary = first.due_date
      ? `${t('notifications.duePrefix')}: ${first.due_date}${first.due_time ? ` ${first.due_time}` : ''}`
      : t('notifications.dueSoon');

    const body = unseen.length === 1
      ? `${first.title} · ${dueSummary}`
      : `${formatNotificationDueSoonTaskCountLabel(locale, unseen.length, t)} · ${dueSummary}`;

    const sendResult = await sendNotification({ title: t('notifications.atRiskTitle'), body });

    if (sendResult === 'sent') {
      // Only record fire state when the notification was actually delivered.
      // If suppressed by quiet hours, leave unfired so it retries after
      // quiet hours end.
      await setDeviceState(DEV_AT_RISK_NOTIFICATION_LAST_FIRED, today);
    }
  } catch (error) {
    reportClientError('notifications.checkAtRiskDeadlines', 'Upcoming deadline notification failed', error);
  }
}
