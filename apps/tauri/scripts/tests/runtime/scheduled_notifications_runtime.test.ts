import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserScheduledNotificationsIntervalHost,
  installScheduledNotificationsRuntime,
  type ScheduledNotificationsRuntimeState,
} from '../../../app/src/lib/notifications/scheduled.runtime';

interface ScheduledNotificationsHarnessOptions {
  checkHabitReminders?: () => Promise<void>;
  checkScheduled?: () => Promise<void>;
  initialRunning?: boolean;
}

async function flushScheduledNotificationsRuntime(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
  await new Promise((resolve) => setTimeout(resolve, 0));
}

function createScheduledNotificationsHarness(options: ScheduledNotificationsHarnessOptions = {}) {
  const calls: string[] = [];
  const clearedIntervals: unknown[] = [];
  const errors: unknown[] = [];
  const intervalCallbacks: Array<() => void> = [];
  const state: ScheduledNotificationsRuntimeState = {
    running: options.initialRunning ?? false,
  };

  return {
    calls,
    clearedIntervals,
    errors,
    intervalCallbacks,
    state,
    install: () => installScheduledNotificationsRuntime({
      checkHabitReminders: options.checkHabitReminders ?? (async () => {
        calls.push('habit');
      }),
      checkScheduled: options.checkScheduled ?? (async () => {
        calls.push('scheduled');
      }),
      clearInterval: (handle) => {
        clearedIntervals.push(handle);
      },
      reportTickError: (error) => {
        errors.push(error);
      },
      setInterval: (callback) => {
        intervalCallbacks.push(callback);
        return `timer-${intervalCallbacks.length}`;
      },
      state,
      pollIntervalMs: 60_000,
    }),
  };
}

test('scheduled notifications runtime ticks immediately and installs the poll timer', async () => {
  const harness = createScheduledNotificationsHarness();

  harness.install();
  await flushScheduledNotificationsRuntime();

  assert.deepEqual(harness.calls, ['scheduled', 'habit']);
  assert.equal(harness.intervalCallbacks.length, 1);
  assert.equal(harness.state.running, false);
});

test('scheduled notifications runtime runs later checks from the poll timer', async () => {
  const harness = createScheduledNotificationsHarness();

  harness.install();
  await flushScheduledNotificationsRuntime();
  harness.intervalCallbacks[0]?.();
  await flushScheduledNotificationsRuntime();

  assert.deepEqual(harness.calls, ['scheduled', 'habit', 'scheduled', 'habit']);
});

test('scheduled notifications runtime suppresses overlapping ticks with the shared running guard', async () => {
  const harness = createScheduledNotificationsHarness({ initialRunning: true });

  harness.install();
  harness.intervalCallbacks[0]?.();
  await flushScheduledNotificationsRuntime();

  assert.deepEqual(harness.calls, []);
  assert.equal(harness.state.running, true);
});

test('scheduled notifications runtime does not run habit reminders when scheduled checks fail', async () => {
  const failure = new Error('scheduled failed');
  const harness = createScheduledNotificationsHarness({
    checkScheduled: async () => {
      harness.calls.push('scheduled');
      throw failure;
    },
  });

  harness.install();
  await flushScheduledNotificationsRuntime();

  assert.deepEqual(harness.calls, ['scheduled']);
  assert.deepEqual(harness.errors, [failure]);
  assert.equal(harness.state.running, false);
});

test('scheduled notifications runtime reports habit reminder failures and releases the running guard', async () => {
  const failure = new Error('habit failed');
  const harness = createScheduledNotificationsHarness({
    checkHabitReminders: async () => {
      harness.calls.push('habit');
      throw failure;
    },
  });

  harness.install();
  await flushScheduledNotificationsRuntime();

  assert.deepEqual(harness.calls, ['scheduled', 'habit']);
  assert.deepEqual(harness.errors, [failure]);
  assert.equal(harness.state.running, false);
});

test('scheduled notifications runtime cleanup clears timer and suppresses late callbacks', async () => {
  const harness = createScheduledNotificationsHarness();

  const handle = harness.install();
  await flushScheduledNotificationsRuntime();
  handle.dispose();
  harness.intervalCallbacks[0]?.();
  await flushScheduledNotificationsRuntime();

  assert.deepEqual(harness.clearedIntervals, ['timer-1']);
  assert.deepEqual(harness.calls, ['scheduled', 'habit']);
});

test('scheduled notifications runtime suppresses late errors after cleanup during an in-flight tick', async () => {
  const failure = new Error('late scheduled failure');
  let rejectScheduled: ((error: Error) => void) | null = null;
  const harness = createScheduledNotificationsHarness({
    checkScheduled: () => new Promise((_resolve, reject) => {
      harness.calls.push('scheduled');
      rejectScheduled = reject;
    }),
  });

  const handle = harness.install();
  await Promise.resolve();
  handle.dispose();
  rejectScheduled?.(failure);
  await flushScheduledNotificationsRuntime();

  assert.deepEqual(harness.clearedIntervals, ['timer-1']);
  assert.deepEqual(harness.errors, []);
  assert.deepEqual(harness.calls, ['scheduled']);
  assert.equal(harness.state.running, false);
});

test('scheduled notifications hook delegates timer wiring through the browser interval host seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/notifications/usePollingNotifications.ts'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/notifications/scheduled.runtime.ts'),
    'utf8',
  );
  const scheduledHookSource = source.slice(
    source.indexOf('export function useScheduledNotifications'),
    source.indexOf('export function useNotificationPermissionPrompt'),
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserScheduledNotificationsIntervalHost,[\s\S]*installScheduledNotificationsRuntime,[\s\S]*\} from '\.\/scheduled\.runtime';/s,
  );
  assert.match(source, /const scheduledNotificationsIntervalHost = createBrowserScheduledNotificationsIntervalHost\(\);/);
  assert.match(
    scheduledHookSource,
    /installScheduledNotificationsRuntime\(\{[\s\S]*checkScheduled,[\s\S]*checkHabitReminders,[\s\S]*pollIntervalMs: SCHEDULE_POLL_MS,[\s\S]*\.\.\.scheduledNotificationsIntervalHost,[\s\S]*\}\)/s,
  );
  assert.doesNotMatch(scheduledHookSource, /globalThis\.setInterval/);
  assert.doesNotMatch(scheduledHookSource, /globalThis\.clearInterval/);

  assert.match(runtimeSource, /export function createBrowserScheduledNotificationsIntervalHost\(\): ScheduledNotificationsIntervalHost/);
  assert.match(runtimeSource, /globalThis\.clearInterval\(handle as ReturnType<typeof globalThis\.setInterval>\);/);
  assert.match(runtimeSource, /setInterval: \(callback, delayMs\) => globalThis\.setInterval\(callback, delayMs\),/);
});

test('scheduled notifications runtime owns the browser interval host wiring', () => {
  const host = createBrowserScheduledNotificationsIntervalHost();
  assert.equal(typeof host.setInterval, 'function');
  assert.equal(typeof host.clearInterval, 'function');
});
