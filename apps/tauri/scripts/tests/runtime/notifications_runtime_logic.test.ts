import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  countReminderBadgeEntries,
  isQuietHoursWindow,
  selectReminderEntriesToNotify,
  shouldFireDailyScheduledNotification,
  shouldFireWeeklyScheduledNotification,
  shouldMuteTaskNotification,
} from '../../../app/src/lib/notifications/runtime.logic';

const repoRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../..',
);

test('notification quiet-hours window supports disabled, same-day, and overnight spans', () => {
  assert.equal(isQuietHoursWindow(600, 480, 480), false);
  assert.equal(isQuietHoursWindow(600, 540, 1020), true);
  assert.equal(isQuietHoursWindow(530, 540, 1020), false);
  assert.equal(isQuietHoursWindow(1380, 1320, 420), true);
  assert.equal(isQuietHoursWindow(120, 1320, 420), true);
  assert.equal(isQuietHoursWindow(720, 1320, 420), false);
});

test('scheduled notifications fire only once per day after their configured time', () => {
  assert.equal(shouldFireDailyScheduledNotification({
    lastFired: '',
    today: '2026-04-22',
    nowMinutes: 480,
    targetMinutes: 480,
  }), true);
  assert.equal(shouldFireDailyScheduledNotification({
    lastFired: '',
    today: '2026-04-22',
    nowMinutes: 479,
    targetMinutes: 480,
  }), false);
  assert.equal(shouldFireDailyScheduledNotification({
    lastFired: '2026-04-22',
    today: '2026-04-22',
    nowMinutes: 720,
    targetMinutes: 480,
  }), false);
});

test('weekly scheduled notifications additionally require the configured weekday', () => {
  assert.equal(shouldFireWeeklyScheduledNotification({
    lastFired: '',
    today: '2026-04-24',
    nowMinutes: 960,
    targetMinutes: 900,
    todayDayName: 'friday',
    targetDayName: 'friday',
  }), true);
  assert.equal(shouldFireWeeklyScheduledNotification({
    lastFired: '',
    today: '2026-04-24',
    nowMinutes: 960,
    targetMinutes: 900,
    todayDayName: 'thursday',
    targetDayName: 'friday',
  }), false);
});

test('mute predicate only mutes tasks that actually belong to a muted list', () => {
  const muted = new Set(['list-muted']);
  assert.equal(shouldMuteTaskNotification(null, muted), false);
  assert.equal(shouldMuteTaskNotification('', muted), false);
  assert.equal(shouldMuteTaskNotification('list-live', muted), false);
  assert.equal(shouldMuteTaskNotification('list-muted', muted), true);
});

test('reminder notification selection preserves listless tasks while dropping muted and already-notified reminders', () => {
  const entries = [
    {
      task: { list_id: null },
      reminder: { id: 'listless', reminder_at: '2026-04-22T12:00:00Z' },
    },
    {
      task: { list_id: 'list-muted' },
      reminder: { id: 'muted', reminder_at: '2026-04-22T12:05:00Z' },
    },
    {
      task: { list_id: 'list-live' },
      reminder: { id: 'seen', reminder_at: '2026-04-22T12:10:00Z' },
    },
    {
      task: { list_id: 'list-live' },
      reminder: { id: 'fresh', reminder_at: '2026-04-22T12:15:00Z' },
    },
  ];

  const selected = selectReminderEntriesToNotify(
    entries,
    new Set(['list-muted']),
    new Set(['seen@2026-04-22T12:10:00Z']),
  );

  assert.deepEqual(
    selected.map(({ reminder }) => reminder.id),
    ['listless', 'fresh'],
  );
});

test('reminder badge counts include listless tasks and exclude only muted lists', () => {
  const entries = [
    { task: { list_id: null } },
    { task: { list_id: 'list-muted' } },
    { task: { list_id: 'list-live' } },
  ];
  assert.equal(countReminderBadgeEntries(entries, new Set(['list-muted'])), 2);
});

test('notification hooks keep permission-cache refresh wired through probe/request paths and run at-risk polling always-on', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/notifications/usePollingNotifications.ts'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/notifications/runtime.ts'),
    'utf8',
  );
  const permissionStatusRuntimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/notifications/permissionStatus.runtime.ts'),
    'utf8',
  );
  const atRiskRuntimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/notifications/atRisk.runtime.ts'),
    'utf8',
  );
  const scheduledRuntimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/notifications/scheduled.runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserScheduledNotificationsIntervalHost,[\s\S]*installScheduledNotificationsRuntime,[\s\S]*\} from '\.\/scheduled\.runtime';/s,
  );
  assert.match(source, /const scheduledNotificationsIntervalHost = createBrowserScheduledNotificationsIntervalHost\(\);/);
  assert.doesNotMatch(source, /useAlwaysOnInterval/);
  assert.match(
    source,
    /export function useScheduledNotifications\(\): void \{[\s\S]*installScheduledNotificationsRuntime\(\{[\s\S]*checkScheduled,[\s\S]*checkHabitReminders,[\s\S]*pollIntervalMs: SCHEDULE_POLL_MS,[\s\S]*\.\.\.scheduledNotificationsIntervalHost,[\s\S]*\}\);/s,
  );
  assert.match(
    scheduledRuntimeSource,
    /export function installScheduledNotificationsRuntime\(/,
  );
  assert.match(
    scheduledRuntimeSource,
    /await deps\.checkScheduled\(\);[\s\S]*await deps\.checkHabitReminders\(\);/s,
  );
  assert.match(
    source,
    /import \{[\s\S]*refreshNotificationPermissionCache,[\s\S]*\} from '\.\/runtime';/,
  );
  assert.match(
    source,
    /import \{[\s\S]*installNotificationPermissionStatusWatchRuntime,[\s\S]*probeNotificationPermissionStatusRuntime,[\s\S]*requestNotificationPermissionAgainRuntime,[\s\S]*\} from '\.\/permissionStatus\.runtime';/s,
  );
  assert.match(
    source,
    /const probe = useCallback\(async \(\) => \{\s*await probeNotificationPermissionStatusRuntime\(\{/s,
  );
  assert.match(
    source,
    /const requestAgain = useCallback\(async \(\) => \{\s*await requestNotificationPermissionAgainRuntime\(\{/s,
  );
  assert.match(
    source,
    /return installNotificationPermissionStatusWatchRuntime\(\{[\s\S]*enabled,[\s\S]*probe,[\s\S]*\}\);/s,
  );
  assert.match(
    source,
    /import \{[\s\S]*createBrowserAtRiskNotificationsHost,[\s\S]*installAtRiskNotificationsRuntime,[\s\S]*\} from '\.\/atRisk\.runtime';/s,
  );
  assert.match(source, /const atRiskNotificationsBrowserHost = createBrowserAtRiskNotificationsHost\(\);/);
  assert.match(
    source,
    /export function useAtRiskNotifications\(enabled = true\): void \{[\s\S]*installAtRiskNotificationsRuntime\(\{[\s\S]*checkAtRiskDeadlines,[\s\S]*pollIntervalMs: AT_RISK_POLL_MS,[\s\S]*\.\.\.atRiskNotificationsBrowserHost,[\s\S]*\}\);/s,
  );
  assert.match(
    atRiskRuntimeSource,
    /export function installAtRiskNotificationsRuntime\(/,
  );
  assert.match(
    atRiskRuntimeSource,
    /installForegroundCatchUpController\(\{[\s\S]*runCatchUp: \(\): void => \{[\s\S]*runTick\(\);[\s\S]*\},[\s\S]*\}\);/s,
  );
  assert.match(
    atRiskRuntimeSource,
    /runTick\(\);[\s\S]*deps\.setInterval\(runTick, deps\.pollIntervalMs\);/s,
  );
  assert.match(
    fs.readFileSync(path.join(repoRoot, 'app/src/lib/foregroundCatchUpController.ts'), 'utf8'),
    /deps\.getVisibilityState\(\) === 'visible'[\s\S]*deps\.runCatchUp\(\);/s,
  );
  assert.match(
    runtimeSource,
    /async function refreshReminderBadge\(\): Promise<void> \{/,
  );
  assert.match(
    runtimeSource,
    /} catch \(error\) \{\s*reportClientError\('notifications\.checkReminders'[\s\S]*\} finally \{\s*[\s\S]*await refreshReminderBadge\(\);/s,
  );
  assert.match(
    permissionStatusRuntimeSource,
    /export async function probeNotificationPermissionStatusRuntime\(/,
  );
  assert.match(
    permissionStatusRuntimeSource,
    /deps\.refreshNotificationPermissionCache\(\);[\s\S]*if \(!prompted\) \{[\s\S]*deps\.setPromptedButDenied\(false\);/s,
  );
  assert.match(
    permissionStatusRuntimeSource,
    /export async function requestNotificationPermissionAgainRuntime\(/,
  );
  assert.match(
    permissionStatusRuntimeSource,
    /const response = await notification\.requestPermission\(\);[\s\S]*deps\.refreshNotificationPermissionCache\(\);[\s\S]*deps\.setPromptedButDenied\(!granted\);/s,
  );
});
