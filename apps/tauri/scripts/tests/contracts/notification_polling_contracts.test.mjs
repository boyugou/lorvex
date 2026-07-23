import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readTypeScriptSources, repoRoot } from './shared.mjs';

test('notification polling hooks prevent overlapping async interval ticks', () => {
  const source = readTypeScriptSources('app/src/lib/notifications');

  // The reminder-polling adaptive tick was lifted into a dedicated
  // `reminderPolling.runtime.ts` helper. The hook now wires `runningRef`
  // through `deps.state.running`, and the runtime guard inside `runTick`
  // skips overlapping ticks while a prior async iteration is still running.
  assert.match(
    source,
    /export function useReminderNotifications\(\): void \{\s*const runningRef = useRef\(false\);/s,
    'Reminder polling should track in-flight state so async interval ticks cannot overlap',
  );
  assert.match(
    source,
    /installReminderPollingRuntime\(\{[\s\S]*?state: \{[\s\S]*?get running\(\) \{\s*return runningRef\.current;[\s\S]*?set running\(value\) \{\s*runningRef\.current = value;/s,
    'Reminder polling hook should pass runningRef through to the shared polling runtime helper',
  );
  assert.match(
    source,
    /const runTick = async \(\): Promise<void> => \{\s*if \(cancelled \|\| deps\.state\.running\) return;\s*deps\.state\.running = true;[\s\S]*?finally \{\s*deps\.state\.running = false;\s*\}\s*\};/s,
    'reminderPolling.runtime should skip overlapping ticks while a prior async iteration is still running',
  );
  assert.match(
    source,
    /intervalHandle = deps\.setInterval\(\(\) => \{\s*void runTick\(\);\s*\}, currentIntervalMs\);/s,
    'reminderPolling.runtime should route interval callbacks through the same guarded async tick',
  );
  assert.match(
    source,
    /export function useScheduledNotifications\(\): void \{\s*const runningRef = useRef\(false\);/s,
    'Scheduled notification polling should still track in-flight state so async interval ticks cannot overlap',
  );
  // Scheduled-notification polling was lifted into
  // `installScheduledNotificationsRuntime` with the same
  // `state.running` plumbing as the reminder helper.
  assert.match(
    source,
    /installScheduledNotificationsRuntime\(\{[\s\S]*?state: \{[\s\S]*?get running\(\) \{\s*return runningRef\.current;[\s\S]*?set running\(value\) \{\s*runningRef\.current = value;/s,
    'Scheduled notifications should route polling through the shared scheduled-notifications runtime with the canonical running-state plumbing',
  );
  assert.match(
    source,
    /export function useAtRiskNotifications\(enabled = true\): void \{\s*const runningRef = useRef\(false\);/s,
    'At-risk polling should still track in-flight state so async interval ticks cannot overlap',
  );
  // At-risk polling was also lifted into a dedicated runtime helper
  // (`installAtRiskNotificationsRuntime`) which receives the
  // enabled flag plus the canonical running-state plumbing.
  assert.match(
    source,
    /installAtRiskNotificationsRuntime\(\{[\s\S]*?enabled,[\s\S]*?state: \{[\s\S]*?get running\(\) \{\s*return runningRef\.current;[\s\S]*?set running\(value\) \{\s*runningRef\.current = value;/s,
    'At-risk polling should route polling through the shared at-risk runtime with the canonical enabled + running plumbing',
  );
});

test('notification dedupe keys preserve exact optional reminder and due-field values', () => {
  const source = readTypeScriptSources('app/src/lib/notifications');
  const helperSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/notifications/taskKey.ts'),
    'utf8',
  );

  assert.match(
    helperSource,
    /export function reminderNotificationKey\(/,
    'notifications key helper should expose reminderNotificationKey as the canonical reminder dedupe key builder',
  );
  assert.match(
    source,
    /import \{ reminderNotificationKey } from '\.\/taskKey';/,
    'notifications runtime should import the canonical reminder dedupe key builder instead of inlining lossy string concatenation',
  );
  assert.match(
    source,
    /reminderNotificationKey\(/,
    'Reminder polling should dedupe through the canonical reminder key helper',
  );
  assert.match(
    source,
    /parseStringPreference\(lastFiredRaw, ''\) === today/,
    'At-risk polling should dedupe through the persisted per-day device-state marker',
  );
  assert.doesNotMatch(
    source,
    /function reminderKey\(/,
    'notifications.ts should not keep a local reminderKey helper that can collapse null and empty-string fields',
  );
  assert.doesNotMatch(
    source,
    /function atRiskKey\(/,
    'notifications.ts should not keep a local atRiskKey helper that can collapse null and empty-string fields',
  );
  assert.doesNotMatch(
    source,
    /notifiedAtRiskKeys|atRiskNotificationKey\(/,
    'notifications runtime should not keep the removed in-memory at-risk dedupe-key path',
  );
});
