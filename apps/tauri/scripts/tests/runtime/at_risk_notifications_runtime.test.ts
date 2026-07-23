import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserAtRiskNotificationsHost,
  installAtRiskNotificationsRuntime,
  type AtRiskNotificationsRuntimeState,
} from '../../../app/src/lib/notifications/atRisk.runtime';

interface AtRiskNotificationsHarnessOptions {
  checkAtRiskDeadlines?: () => Promise<void>;
  enabled?: boolean;
  initialRunning?: boolean;
  visibilityState?: DocumentVisibilityState;
}

async function flushAtRiskNotificationsRuntime(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
  await new Promise((resolve) => setTimeout(resolve, 0));
}

function createAtRiskNotificationsHarness(options: AtRiskNotificationsHarnessOptions = {}) {
  const checkCalls: string[] = [];
  const clearedIntervals: unknown[] = [];
  const errors: unknown[] = [];
  const focusListeners: Array<() => void> = [];
  const intervalCallbacks: Array<() => void> = [];
  const unregisters: string[] = [];
  const visibilityListeners: Array<() => void> = [];
  const state: AtRiskNotificationsRuntimeState = {
    running: options.initialRunning ?? false,
  };
  let visibilityState = options.visibilityState ?? 'visible';

  return {
    checkCalls,
    clearedIntervals,
    errors,
    focusListeners,
    intervalCallbacks,
    state,
    unregisters,
    visibilityListeners,
    setVisibilityState(nextVisibilityState: DocumentVisibilityState) {
      visibilityState = nextVisibilityState;
    },
    install: () => installAtRiskNotificationsRuntime({
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
      checkAtRiskDeadlines: options.checkAtRiskDeadlines ?? (async () => {
        checkCalls.push('check');
      }),
      clearInterval: (handle) => {
        clearedIntervals.push(handle);
      },
      enabled: options.enabled ?? true,
      getVisibilityState: () => visibilityState,
      reportTickError: (error) => {
        errors.push(error);
      },
      setInterval: (callback) => {
        intervalCallbacks.push(callback);
        return `timer-${intervalCallbacks.length}`;
      },
      state,
      pollIntervalMs: 15 * 60_000,
    }),
  };
}

test('at-risk notification runtime is inert when disabled', async () => {
  const harness = createAtRiskNotificationsHarness({ enabled: false });

  harness.install();
  await flushAtRiskNotificationsRuntime();

  assert.deepEqual(harness.checkCalls, []);
  assert.equal(harness.intervalCallbacks.length, 0);
  assert.equal(harness.visibilityListeners.length, 0);
  assert.equal(harness.focusListeners.length, 0);
  assert.equal(harness.state.running, false);
});

test('at-risk notification runtime ticks immediately and installs the poll timer', async () => {
  const harness = createAtRiskNotificationsHarness();

  harness.install();
  await flushAtRiskNotificationsRuntime();

  assert.deepEqual(harness.checkCalls, ['check']);
  assert.equal(harness.intervalCallbacks.length, 1);
  assert.equal(harness.state.running, false);
});

test('at-risk notification runtime runs later checks from the poll timer', async () => {
  const harness = createAtRiskNotificationsHarness();

  harness.install();
  await flushAtRiskNotificationsRuntime();
  harness.intervalCallbacks[0]?.();
  await flushAtRiskNotificationsRuntime();

  assert.deepEqual(harness.checkCalls, ['check', 'check']);
});

test('at-risk notification runtime suppresses overlapping ticks with the shared running guard', async () => {
  const harness = createAtRiskNotificationsHarness({ initialRunning: true });

  harness.install();
  harness.intervalCallbacks[0]?.();
  await flushAtRiskNotificationsRuntime();

  assert.deepEqual(harness.checkCalls, []);
  assert.equal(harness.state.running, true);
});

test('at-risk notification runtime catches up only from visible foreground events', async () => {
  const harness = createAtRiskNotificationsHarness({ visibilityState: 'hidden' });

  harness.install();
  await flushAtRiskNotificationsRuntime();
  harness.visibilityListeners[0]?.();
  await flushAtRiskNotificationsRuntime();
  harness.setVisibilityState('visible');
  harness.focusListeners[0]?.();
  await flushAtRiskNotificationsRuntime();

  assert.deepEqual(harness.checkCalls, ['check', 'check']);
});

test('at-risk notification runtime keeps polling without optional foreground hosts', async () => {
  const harness = createAtRiskNotificationsHarness();

  const handle = installAtRiskNotificationsRuntime({
    addVisibilityListener: null,
    addWindowFocusListener: null,
    checkAtRiskDeadlines: async () => {
      harness.checkCalls.push('check');
    },
    clearInterval: (timerHandle) => {
      harness.clearedIntervals.push(timerHandle);
    },
    enabled: true,
    getVisibilityState: () => 'visible',
    reportTickError: (error) => {
      harness.errors.push(error);
    },
    setInterval: (callback) => {
      harness.intervalCallbacks.push(callback);
      return `timer-${harness.intervalCallbacks.length}`;
    },
    state: harness.state,
    pollIntervalMs: 15 * 60_000,
  });

  await flushAtRiskNotificationsRuntime();
  harness.intervalCallbacks[0]?.();
  await flushAtRiskNotificationsRuntime();
  handle.dispose();

  assert.deepEqual(harness.checkCalls, ['check', 'check']);
  assert.deepEqual(harness.clearedIntervals, ['timer-1']);
});

test('at-risk notification runtime reports unexpected tick failures and releases the running guard', async () => {
  const failure = new Error('at-risk failed');
  const harness = createAtRiskNotificationsHarness({
    checkAtRiskDeadlines: async () => {
      throw failure;
    },
  });

  harness.install();
  await flushAtRiskNotificationsRuntime();

  assert.deepEqual(harness.errors, [failure]);
  assert.equal(harness.state.running, false);
});

test('at-risk notification runtime cleanup clears timer and unregisters foreground listeners', async () => {
  const harness = createAtRiskNotificationsHarness();

  const handle = harness.install();
  await flushAtRiskNotificationsRuntime();
  handle.dispose();
  harness.intervalCallbacks[0]?.();
  harness.focusListeners[0]?.();
  await flushAtRiskNotificationsRuntime();

  assert.deepEqual(harness.clearedIntervals, ['timer-1']);
  assert.deepEqual([...harness.unregisters].sort(), ['focus', 'visibility']);
  assert.deepEqual(harness.checkCalls, ['check']);
});

test('at-risk notifications hook delegates foreground listeners through the browser host seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/notifications/usePollingNotifications.ts'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/notifications/atRisk.runtime.ts'),
    'utf8',
  );
  const atRiskHookSource = source.slice(
    source.indexOf('export function useAtRiskNotifications'),
    source.indexOf('/** How often to re-sync native calendar events'),
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserAtRiskNotificationsHost,[\s\S]*installAtRiskNotificationsRuntime,[\s\S]*\} from '\.\/atRisk\.runtime';/s,
  );
  assert.match(source, /const atRiskNotificationsBrowserHost = createBrowserAtRiskNotificationsHost\(\);/);
  assert.match(
    atRiskHookSource,
    /installAtRiskNotificationsRuntime\(\{[\s\S]*checkAtRiskDeadlines,[\s\S]*pollIntervalMs: AT_RISK_POLL_MS,[\s\S]*\.\.\.atRiskNotificationsBrowserHost,[\s\S]*\}\);/s,
  );
  assert.doesNotMatch(atRiskHookSource, /globalThis\.(setInterval|clearInterval)/);
  assert.doesNotMatch(atRiskHookSource, /document\.addEventListener/);
  assert.doesNotMatch(atRiskHookSource, /window\.addEventListener/);

  assert.match(runtimeSource, /createBrowserForegroundCatchUpHost,/);
  assert.match(runtimeSource, /installForegroundCatchUpController,/);
  assert.match(runtimeSource, /export function createBrowserAtRiskNotificationsHost\(\): AtRiskNotificationsBrowserHost/);
  assert.match(runtimeSource, /\.\.\.createBrowserForegroundCatchUpHost\(\),/);
  assert.match(runtimeSource, /const foregroundCatchUp = installForegroundCatchUpController\(\{/);
  assert.doesNotMatch(runtimeSource, /document\.addEventListener\('visibilitychange', handler\);/);
  assert.doesNotMatch(runtimeSource, /window\.addEventListener\('focus', handler\);/);
  assert.match(runtimeSource, /globalThis\.clearInterval\(handle as ReturnType<typeof globalThis\.setInterval>\);/);
  assert.match(runtimeSource, /setInterval: \(callback, delayMs\) => globalThis\.setInterval\(callback, delayMs\),/);
});

test('at-risk notifications runtime owns the browser host wiring', () => {
  const host = createBrowserAtRiskNotificationsHost();
  assert.equal(typeof host.setInterval, 'function');
  assert.equal(typeof host.clearInterval, 'function');
  assert.equal(typeof host.getVisibilityState, 'function');
});
