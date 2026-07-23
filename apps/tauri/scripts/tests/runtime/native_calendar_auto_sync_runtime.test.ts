import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserNativeCalendarAutoSyncIntervalHost,
  installNativeCalendarAutoSyncRuntime,
  type NativeCalendarAutoSyncRuntimeConfig,
  type NativeCalendarAutoSyncRuntimeState,
} from '../../../app/src/lib/nativeCalendarAutoSync.runtime';

function createRuntimeHarness(options: {
  config?: NativeCalendarAutoSyncRuntimeConfig | null;
  deviceState?: string | null;
  getDeviceState?: (key: string) => Promise<string | null>;
  initialFired?: boolean;
} = {}) {
  const intervalCallbacks: Array<() => void> = [];
  const clearedIntervals: unknown[] = [];
  const errors: unknown[] = [];
  const syncCalls: string[] = [];
  const state: NativeCalendarAutoSyncRuntimeState = {
    firedInitialSync: options.initialFired ?? false,
  };
  const config: NativeCalendarAutoSyncRuntimeConfig | null = options.config ?? {
    deviceStateKey: 'windows_calendar_sync_enabled',
    isAvailable: true,
    syncNow: async () => {
      syncCalls.push('sync');
    },
  };

  return {
    clearedIntervals,
    config,
    errors,
    intervalCallbacks,
    state,
    syncCalls,
    install: () => installNativeCalendarAutoSyncRuntime({
      clearInterval: (handle) => {
        clearedIntervals.push(handle);
      },
      config,
      getDeviceState: options.getDeviceState ?? (async () => options.deviceState ?? 'true'),
      reportSyncError: (error) => {
        errors.push(error);
      },
      setInterval: (callback) => {
        intervalCallbacks.push(callback);
        return `timer-${intervalCallbacks.length}`;
      },
      state,
      syncIntervalMs: 15 * 60_000,
    }),
  };
}

async function flushNativeCalendarAutoSync(): Promise<void> {
  await Promise.resolve();
}

test('native calendar auto-sync fires immediately and installs periodic sync when enabled', async () => {
  const harness = createRuntimeHarness();

  const handle = harness.install();
  await flushNativeCalendarAutoSync();

  assert.equal(handle.installed, true);
  assert.deepEqual(harness.syncCalls, ['sync']);
  assert.equal(harness.state.firedInitialSync, true);
  assert.equal(harness.intervalCallbacks.length, 1);

  harness.intervalCallbacks[0]?.();
  await flushNativeCalendarAutoSync();

  assert.deepEqual(harness.syncCalls, ['sync', 'sync']);
});

test('native calendar auto-sync skips sync when the device-state toggle is disabled', async () => {
  const harness = createRuntimeHarness({ deviceState: 'false' });

  const handle = harness.install();
  await flushNativeCalendarAutoSync();
  harness.intervalCallbacks[0]?.();
  await flushNativeCalendarAutoSync();

  assert.equal(handle.installed, true);
  assert.deepEqual(harness.syncCalls, []);
  assert.equal(harness.intervalCallbacks.length, 1);
});

test('native calendar auto-sync is inert and resets initial state when unavailable', () => {
  const harness = createRuntimeHarness({
    config: {
      deviceStateKey: 'windows_calendar_sync_enabled',
      isAvailable: false,
      syncNow: async () => {},
    },
    initialFired: true,
  });

  const handle = harness.install();

  assert.equal(handle.installed, false);
  assert.equal(harness.state.firedInitialSync, false);
  assert.equal(harness.intervalCallbacks.length, 0);
});

test('native calendar auto-sync avoids duplicate immediate sync while still installing timer', async () => {
  const harness = createRuntimeHarness({ initialFired: true });

  harness.install();
  await flushNativeCalendarAutoSync();

  assert.deepEqual(harness.syncCalls, []);
  assert.equal(harness.intervalCallbacks.length, 1);

  harness.intervalCallbacks[0]?.();
  await flushNativeCalendarAutoSync();

  assert.deepEqual(harness.syncCalls, ['sync']);
});

test('native calendar auto-sync reports sync failures without breaking future ticks', async () => {
  const failure = new Error('calendar unavailable');
  const syncCalls: string[] = [];
  const harness = createRuntimeHarness({
    config: {
      deviceStateKey: 'windows_calendar_sync_enabled',
      isAvailable: true,
      syncNow: async () => {
        syncCalls.push('sync');
        if (syncCalls.length === 1) throw failure;
      },
    },
  });

  harness.install();
  await flushNativeCalendarAutoSync();
  harness.intervalCallbacks[0]?.();
  await flushNativeCalendarAutoSync();

  assert.deepEqual(syncCalls, ['sync', 'sync']);
  assert.deepEqual(harness.errors, [failure]);
});

test('native calendar auto-sync cleanup clears timer and allows a future initial sync', async () => {
  const harness = createRuntimeHarness();

  const handle = harness.install();
  await flushNativeCalendarAutoSync();
  handle.dispose();

  assert.deepEqual(harness.clearedIntervals, ['timer-1']);
  assert.equal(harness.state.firedInitialSync, false);

  harness.install();
  await flushNativeCalendarAutoSync();

  assert.deepEqual(harness.syncCalls, ['sync', 'sync']);
  assert.equal(harness.intervalCallbacks.length, 2);
});

test('native calendar auto-sync suppresses sync when cleanup happens before device state resolves', async () => {
  let resolveDeviceState: ((value: string | null) => void) | null = null;
  const harness = createRuntimeHarness({
    getDeviceState: () => new Promise((resolve) => {
      resolveDeviceState = resolve;
    }),
  });

  const handle = harness.install();
  handle.dispose();
  resolveDeviceState?.('true');
  await flushNativeCalendarAutoSync();

  assert.deepEqual(harness.syncCalls, []);
  assert.deepEqual(harness.errors, []);
  assert.deepEqual(harness.clearedIntervals, ['timer-1']);
});

test('native calendar auto-sync suppresses late errors after cleanup', async () => {
  const failure = new Error('device state failed after cleanup');
  let rejectDeviceState: ((error: unknown) => void) | null = null;
  const harness = createRuntimeHarness({
    getDeviceState: () => new Promise((_resolve, reject) => {
      rejectDeviceState = reject;
    }),
  });

  const handle = harness.install();
  handle.dispose();
  rejectDeviceState?.(failure);
  await flushNativeCalendarAutoSync();

  assert.deepEqual(harness.syncCalls, []);
  assert.deepEqual(harness.errors, []);
  assert.deepEqual(harness.clearedIntervals, ['timer-1']);
});

test('native calendar auto-sync hook delegates timer wiring through the browser interval host seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/notifications/usePollingNotifications.ts'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/nativeCalendarAutoSync.runtime.ts'),
    'utf8',
  );
  const nativeCalendarHookSource = source.slice(
    source.indexOf('export function useNativeCalendarAutoSync'),
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserNativeCalendarAutoSyncIntervalHost,[\s\S]*installNativeCalendarAutoSyncRuntime,[\s\S]*\} from '\.\.\/nativeCalendarAutoSync\.runtime';/s,
  );
  assert.match(source, /const nativeCalendarAutoSyncIntervalHost = createBrowserNativeCalendarAutoSyncIntervalHost\(\);/);
  assert.match(
    nativeCalendarHookSource,
    /installNativeCalendarAutoSyncRuntime\(\{[\s\S]*syncIntervalMs: NATIVE_CALENDAR_RESYNC_MS,[\s\S]*\.\.\.nativeCalendarAutoSyncIntervalHost,[\s\S]*\}\)/s,
  );
  assert.doesNotMatch(nativeCalendarHookSource, /globalThis\.setInterval/);
  assert.doesNotMatch(nativeCalendarHookSource, /globalThis\.clearInterval/);

  assert.match(runtimeSource, /export function createBrowserNativeCalendarAutoSyncIntervalHost\(\): NativeCalendarAutoSyncIntervalHost/);
  assert.match(runtimeSource, /globalThis\.clearInterval\(handle as ReturnType<typeof globalThis\.setInterval>\);/);
  assert.match(runtimeSource, /setInterval: \(callback, delayMs\) => globalThis\.setInterval\(callback, delayMs\),/);
});

test('native calendar auto-sync runtime owns the browser interval host wiring', () => {
  const host = createBrowserNativeCalendarAutoSyncIntervalHost();
  assert.equal(typeof host.setInterval, 'function');
  assert.equal(typeof host.clearInterval, 'function');
});
