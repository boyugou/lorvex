import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('notifications runtime is organized as a folder-backed subsystem with root hooks and support modules', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/notifications/usePollingNotifications.ts'),
    'utf8',
  );
  const actionsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/notifications/actions.ts'),
    'utf8',
  );
  const preferencesSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/notifications/preferences.ts'),
    'utf8',
  );
  const runtimeLogicSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/notifications/runtime.logic.ts'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/notifications/runtime.ts'),
    'utf8',
  );

  // Root composes from sibling support modules without re-importing the
  // notification-specific preference helper (it uses the canonical
  // shared preferences parser instead).
  assert.match(rootSource, /from '\.\/reminderPolling\.runtime';/);
  assert.match(rootSource, /from '\.\/scheduled\.runtime';/);
  assert.match(rootSource, /from '\.\/atRisk\.runtime';/);
  assert.doesNotMatch(
    rootSource,
    /from '\.\/preferences';/,
    'root notifications hook should import generic preference parsers from the canonical parser module, not the notification preferences helper',
  );
  assert.match(rootSource, /from '\.\.\/preferences\/parser';/);
  assert.match(rootSource, /export function useReminderNotifications\(\): void \{/);
  assert.match(rootSource, /export function useScheduledNotifications\(\): void \{/);
  assert.match(rootSource, /export function useNotificationPermissionPrompt\(enabled = true\): void \{/);
  assert.match(rootSource, /export function useAtRiskNotifications\(enabled = true\): void \{/);

  assert.match(actionsSource, /export async function registerNotificationActions\(\): Promise<void> \{/);
  assert.doesNotMatch(
    preferencesSource,
    /export \{[^}]*parse(?:Boolean|String)Preference[^}]*\};/,
    'notification preferences should not re-export generic preference parsers',
  );
  assert.match(preferencesSource, /export function parseTimePreference\(/);
  assert.match(preferencesSource, /export function parseWeekdayPreference\(/);
  assert.doesNotMatch(preferencesSource, /parseBooleanPreference/);

  assert.match(runtimeLogicSource, /export function selectReminderEntriesToNotify/);
  assert.match(runtimeLogicSource, /export function countReminderBadgeEntries/);
  assert.match(runtimeLogicSource, /export function shouldFireDailyScheduledNotification/);
  assert.match(runtimeSource, /export async function checkReminders\(\): Promise<void> \{/);
  assert.match(runtimeSource, /export async function checkScheduled\(\): Promise<void> \{/);
  assert.match(runtimeSource, /export async function checkAtRiskDeadlines\(\): Promise<void> \{/);
  assert.match(runtimeSource, /from '\.\/runtime\.logic';/);
  assert.match(runtimeSource, /const notifiedReminderKeys = new Set<string>\(\);/);
  assert.doesNotMatch(runtimeSource, /const notifiedAtRiskKeys = new Set<string>\(\);/);
});
