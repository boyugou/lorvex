import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserReminderPollingHost,
  installReminderPollingRuntime,
  type ReminderPollingRuntimeState,
} from '../../../app/src/lib/notifications/reminderPolling.runtime';

interface ReminderPollingHarnessOptions {
  checkReminders?: () => Promise<void>;
  getUpcomingReminders?: (lookaheadMinutes: number) => Promise<readonly unknown[]>;
  initialRunning?: boolean;
  registerNotificationActions?: () => Promise<unknown> | unknown;
  visibilityState?: DocumentVisibilityState;
}

async function flushReminderPollingRuntime(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

function createReminderPollingHarness(options: ReminderPollingHarnessOptions = {}) {
  const intervalCallbacks: Array<() => void> = [];
  const actionRegistrationErrors: unknown[] = [];
  const clearedIntervals: unknown[] = [];
  const errors: unknown[] = [];
  const visibilityListeners: Array<() => void> = [];
  const focusListeners: Array<() => void> = [];
  const unregisters: string[] = [];
  const checkCalls: string[] = [];
  const lookaheadCalls: number[] = [];
  let actionRegistrations = 0;
  let visibilityState = options.visibilityState ?? 'visible';
  const state: ReminderPollingRuntimeState = {
    running: options.initialRunning ?? false,
  };

  return {
    actionRegistrationErrors,
    checkCalls,
    clearedIntervals,
    errors,
    focusListeners,
    intervalCallbacks,
    lookaheadCalls,
    state,
    unregisters,
    visibilityListeners,
    get actionRegistrations() {
      return actionRegistrations;
    },
    setVisibilityState(nextVisibilityState: DocumentVisibilityState) {
      visibilityState = nextVisibilityState;
    },
    install: () => installReminderPollingRuntime({
      addVisibilityListener: (handler) => {
        visibilityListeners.push(handler);
        return () => {
          unregisters.push('visibility');
        };
      },
      addWindowFocusListener: (handler) => {
        focusListeners.push(handler);
        return () => {
          unregisters.push('focus');
        };
      },
      checkReminders: options.checkReminders ?? (async () => {
        checkCalls.push('check');
      }),
      clearInterval: (handle) => {
        clearedIntervals.push(handle);
      },
      getUpcomingReminders: options.getUpcomingReminders ?? (async (lookaheadMinutes) => {
        lookaheadCalls.push(lookaheadMinutes);
        return [];
      }),
      getVisibilityState: () => visibilityState,
      registerNotificationActions: options.registerNotificationActions ?? (() => {
        actionRegistrations += 1;
      }),
      reportActionRegistrationError: (error) => {
        actionRegistrationErrors.push(error);
      },
      reportCadenceError: (error) => {
        errors.push(error);
      },
      setInterval: (callback) => {
        intervalCallbacks.push(callback);
        return `timer-${intervalCallbacks.length}`;
      },
      state,
      pollIntervalMs: 30_000,
      urgentIntervalMs: 5_000,
      urgentLookaheadMinutes: 120,
    }),
  };
}

test('reminder polling runtime registers actions, ticks immediately, and installs the baseline timer', async () => {
  const harness = createReminderPollingHarness();

  harness.install();
  await flushReminderPollingRuntime();

  assert.equal(harness.actionRegistrations, 1);
  assert.deepEqual(harness.checkCalls, ['check']);
  assert.deepEqual(harness.lookaheadCalls, [120]);
  assert.equal(harness.intervalCallbacks.length, 1);
  assert.equal(harness.state.running, false);
});

test('reminder polling runtime switches to urgent cadence when upcoming reminders exist', async () => {
  const harness = createReminderPollingHarness({
    getUpcomingReminders: async (lookaheadMinutes) => {
      harness.lookaheadCalls.push(lookaheadMinutes);
      return ['soon'];
    },
  });

  harness.install();
  await flushReminderPollingRuntime();

  assert.deepEqual(harness.clearedIntervals, ['timer-1']);
  assert.equal(harness.intervalCallbacks.length, 2);
});

test('reminder polling runtime returns from urgent cadence to baseline when upcoming reminders clear', async () => {
  let hasUpcoming = true;
  const harness = createReminderPollingHarness({
    getUpcomingReminders: async () => (hasUpcoming ? ['soon'] : []),
  });

  harness.install();
  await flushReminderPollingRuntime();
  hasUpcoming = false;
  harness.intervalCallbacks[1]?.();
  await flushReminderPollingRuntime();

  assert.deepEqual(harness.clearedIntervals, ['timer-1', 'timer-2']);
  assert.equal(harness.intervalCallbacks.length, 3);
});

test('reminder polling runtime suppresses overlapping ticks while one is already running', async () => {
  const harness = createReminderPollingHarness({ initialRunning: true });

  harness.install();
  harness.intervalCallbacks[0]?.();
  await flushReminderPollingRuntime();

  assert.deepEqual(harness.checkCalls, []);
  assert.deepEqual(harness.lookaheadCalls, []);
});

test('reminder polling runtime catches up only for visible foreground events', async () => {
  const harness = createReminderPollingHarness({ visibilityState: 'hidden' });

  harness.install();
  await flushReminderPollingRuntime();
  harness.visibilityListeners[0]?.();
  await flushReminderPollingRuntime();
  harness.setVisibilityState('visible');
  harness.focusListeners[0]?.();
  await flushReminderPollingRuntime();

  assert.deepEqual(harness.checkCalls, ['check', 'check']);
});

test('reminder polling runtime keeps polling without optional foreground hosts', async () => {
  const harness = createReminderPollingHarness();

  const handle = installReminderPollingRuntime({
    addVisibilityListener: null,
    addWindowFocusListener: null,
    checkReminders: async () => {
      harness.checkCalls.push('check');
    },
    clearInterval: (timerHandle) => {
      harness.clearedIntervals.push(timerHandle);
    },
    getUpcomingReminders: async (lookaheadMinutes) => {
      harness.lookaheadCalls.push(lookaheadMinutes);
      return [];
    },
    getVisibilityState: () => 'visible',
    registerNotificationActions: () => {},
    reportActionRegistrationError: (error) => {
      harness.actionRegistrationErrors.push(error);
    },
    reportCadenceError: (error) => {
      harness.errors.push(error);
    },
    setInterval: (callback) => {
      harness.intervalCallbacks.push(callback);
      return `timer-${harness.intervalCallbacks.length}`;
    },
    state: harness.state,
    pollIntervalMs: 30_000,
    urgentIntervalMs: 5_000,
    urgentLookaheadMinutes: 120,
  });

  await flushReminderPollingRuntime();
  harness.intervalCallbacks[0]?.();
  await flushReminderPollingRuntime();
  handle.dispose();

  assert.deepEqual(harness.checkCalls, ['check', 'check']);
  assert.deepEqual(harness.lookaheadCalls, [120, 120]);
  assert.deepEqual(harness.clearedIntervals, ['timer-1']);
});

test('reminder polling runtime reports cadence failures and releases the running guard', async () => {
  const failure = new Error('upcoming probe failed');
  const harness = createReminderPollingHarness({
    getUpcomingReminders: async () => {
      throw failure;
    },
  });

  harness.install();
  await flushReminderPollingRuntime();

  assert.deepEqual(harness.errors, [failure]);
  assert.equal(harness.state.running, false);
});

test('reminder polling runtime reports rejected notification action registration', async () => {
  const failure = new Error('action registration failed');
  const harness = createReminderPollingHarness({
    registerNotificationActions: () => Promise.reject(failure),
  });

  harness.install();
  await flushReminderPollingRuntime();

  assert.deepEqual(harness.errors, []);
  assert.equal(harness.actionRegistrationErrors.length, 1);
  assert.equal(harness.actionRegistrationErrors[0], failure);
  assert.deepEqual(harness.checkCalls, ['check']);
});

test('reminder polling runtime reports synchronous notification action registration failures', async () => {
  const failure = new Error('action registration unsupported');
  const harness = createReminderPollingHarness({
    registerNotificationActions: () => {
      throw failure;
    },
  });

  assert.doesNotThrow(() => {
    harness.install();
  });
  await flushReminderPollingRuntime();

  assert.deepEqual(harness.errors, []);
  assert.equal(harness.actionRegistrationErrors.length, 1);
  assert.equal(harness.actionRegistrationErrors[0], failure);
  assert.deepEqual(harness.checkCalls, ['check']);
});

test('reminder polling runtime suppresses late action registration failures after cleanup', async () => {
  const failure = new Error('late action registration failed');
  let rejectRegistration: ((error: unknown) => void) | null = null;
  const harness = createReminderPollingHarness({
    registerNotificationActions: () => new Promise((_resolve, reject) => {
      rejectRegistration = reject;
    }),
  });

  const handle = harness.install();
  handle.dispose();
  rejectRegistration?.(failure);
  await flushReminderPollingRuntime();

  assert.deepEqual(harness.actionRegistrationErrors, []);
  assert.deepEqual(harness.errors, []);
  assert.deepEqual(harness.clearedIntervals, ['timer-1']);
});

test('reminder polling runtime cleanup clears timer, unregisters listeners, and suppresses late cadence changes', async () => {
  let resolveUpcoming: ((value: readonly unknown[]) => void) | null = null;
  const harness = createReminderPollingHarness({
    getUpcomingReminders: () => new Promise((resolve) => {
      resolveUpcoming = resolve;
    }),
  });

  const handle = harness.install();
  await Promise.resolve();
  handle.dispose();
  resolveUpcoming?.(['soon']);
  await flushReminderPollingRuntime();
  harness.focusListeners[0]?.();
  await flushReminderPollingRuntime();

  assert.deepEqual(harness.clearedIntervals, ['timer-1']);
  assert.deepEqual([...harness.unregisters].sort(), ['focus', 'visibility']);
  assert.equal(harness.intervalCallbacks.length, 1);
  assert.deepEqual(harness.checkCalls, ['check']);
});

test('reminder polling runtime suppresses late check failures after cleanup', async () => {
  const failure = new Error('late reminder check failed');
  let rejectCheck: ((error: unknown) => void) | null = null;
  const harness = createReminderPollingHarness({
    checkReminders: () => new Promise((_resolve, reject) => {
      harness.checkCalls.push('check');
      rejectCheck = reject;
    }),
  });

  const handle = harness.install();
  await Promise.resolve();
  handle.dispose();
  rejectCheck?.(failure);
  await flushReminderPollingRuntime();

  assert.deepEqual(harness.errors, []);
  assert.equal(harness.state.running, false);
  assert.deepEqual(harness.clearedIntervals, ['timer-1']);
});

test('reminder polling runtime suppresses late upcoming failures after cleanup', async () => {
  const failure = new Error('late upcoming reminder probe failed');
  let rejectUpcoming: ((error: unknown) => void) | null = null;
  const harness = createReminderPollingHarness({
    getUpcomingReminders: () => new Promise((_resolve, reject) => {
      rejectUpcoming = reject;
    }),
  });

  const handle = harness.install();
  await Promise.resolve();
  handle.dispose();
  rejectUpcoming?.(failure);
  await flushReminderPollingRuntime();

  assert.deepEqual(harness.errors, []);
  assert.equal(harness.state.running, false);
  assert.deepEqual(harness.clearedIntervals, ['timer-1']);
  assert.deepEqual(harness.checkCalls, ['check']);
});

test('reminder polling hook delegates foreground listeners through the browser host seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/notifications/usePollingNotifications.ts'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/notifications/reminderPolling.runtime.ts'),
    'utf8',
  );
  const reminderHookSource = source.slice(
    source.indexOf('export function useReminderNotifications'),
    source.indexOf('export function useScheduledNotifications'),
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserReminderPollingHost,[\s\S]*installReminderPollingRuntime,[\s\S]*\} from '\.\/reminderPolling\.runtime';/s,
  );
  assert.match(source, /const reminderPollingBrowserHost = createBrowserReminderPollingHost\(\);/);
  assert.match(
    reminderHookSource,
    /installReminderPollingRuntime\(\{[\s\S]*checkReminders,[\s\S]*reportActionRegistrationError: \(error\) => \{[\s\S]*notifications\.actionRegistration[\s\S]*Failed to register notification action handlers[\s\S]*reportCadenceError: \(error\) => \{[\s\S]*notifications\.reminderCadence[\s\S]*urgentLookaheadMinutes: 120,[\s\S]*\.\.\.reminderPollingBrowserHost,[\s\S]*\}\);/s,
  );
  assert.doesNotMatch(reminderHookSource, /globalThis\.(setInterval|clearInterval)/);
  assert.doesNotMatch(reminderHookSource, /document\.addEventListener/);
  assert.doesNotMatch(reminderHookSource, /window\.addEventListener/);

  assert.match(runtimeSource, /createBrowserForegroundCatchUpHost,/);
  assert.match(runtimeSource, /installForegroundCatchUpController,/);
  assert.match(runtimeSource, /export function createBrowserReminderPollingHost\(\): ReminderPollingBrowserHost/);
  assert.match(runtimeSource, /\.\.\.createBrowserForegroundCatchUpHost\(\),/);
  assert.match(runtimeSource, /const foregroundCatchUp = installForegroundCatchUpController\(\{/);
  assert.doesNotMatch(runtimeSource, /document\.addEventListener\('visibilitychange', handler\);/);
  assert.doesNotMatch(runtimeSource, /window\.addEventListener\('focus', handler\);/);
  assert.match(runtimeSource, /globalThis\.clearInterval\(handle as ReturnType<typeof globalThis\.setInterval>\);/);
  assert.match(runtimeSource, /setInterval: \(callback, delayMs\) => globalThis\.setInterval\(callback, delayMs\),/);
});

test('reminder polling runtime owns the browser host wiring', () => {
  const host = createBrowserReminderPollingHost();
  assert.equal(typeof host.setInterval, 'function');
  assert.equal(typeof host.clearInterval, 'function');
  assert.equal(typeof host.getVisibilityState, 'function');
});
