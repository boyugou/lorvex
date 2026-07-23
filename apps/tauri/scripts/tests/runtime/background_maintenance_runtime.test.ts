import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserBackgroundMaintenanceTimerHost,
  installBackgroundMaintenanceLoop,
  type BackgroundMaintenanceTimerHost,
} from '../../../app/src/app-shell/main-window/runtime/useBackgroundMaintenance.runtime';

const repoRoot = process.cwd();

function createTimerHost() {
  const callbacks: Array<() => void> = [];
  const clearedHandles: unknown[] = [];
  const delays: number[] = [];
  const host: BackgroundMaintenanceTimerHost = {
    clearTimeout: (handle) => {
      clearedHandles.push(handle);
    },
    setTimeout: (callback, delayMs) => {
      callbacks.push(callback);
      delays.push(delayMs);
      return `timer-${callbacks.length}` as ReturnType<typeof globalThis.setTimeout>;
    },
  };

  return {
    callbacks,
    clearedHandles,
    delays,
    host,
  };
}

test('background maintenance loop runs immediately, schedules the next tick, and clears it on cleanup', async () => {
  const timer = createTimerHost();
  let runCount = 0;

  const cleanup = installBackgroundMaintenanceLoop({
    delayMs: 30000,
    run: async () => {
      runCount += 1;
    },
    timerHost: timer.host,
  });

  await Promise.resolve();
  await Promise.resolve();

  assert.equal(runCount, 1);
  assert.deepEqual(timer.delays, [30000]);

  timer.callbacks[0]?.();
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(runCount, 2);
  assert.deepEqual(timer.delays, [30000, 30000]);

  cleanup();
  assert.deepEqual(timer.clearedHandles, ['timer-2']);
});

test('background maintenance loop keeps polling after a rejected run', async () => {
  const timer = createTimerHost();
  const failure = new Error('tick failed');
  let runCount = 0;

  installBackgroundMaintenanceLoop({
    delayMs: 60000,
    run: async () => {
      runCount += 1;
      throw failure;
    },
    timerHost: timer.host,
  });

  await Promise.resolve();
  await Promise.resolve();

  assert.equal(runCount, 1);
  assert.deepEqual(timer.delays, [60000]);
});

test('background maintenance loop suppresses rescheduling after cleanup before the run settles', async () => {
  const timer = createTimerHost();
  let resolveRun: (() => void) | null = null;

  const cleanup = installBackgroundMaintenanceLoop({
    delayMs: 60000,
    run: () => new Promise<void>((resolve) => {
      resolveRun = resolve;
    }),
    timerHost: timer.host,
  });

  cleanup();
  resolveRun?.();
  await Promise.resolve();

  assert.deepEqual(timer.delays, []);
  assert.deepEqual(timer.clearedHandles, []);
});

test('background maintenance hook delegates looping timers through the browser host seam', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/app-shell/main-window/runtime/useBackgroundMaintenance.ts'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/app-shell/main-window/runtime/useBackgroundMaintenance.runtime.ts'),
    'utf8',
  );

  assert.ok(
    source.includes(
      'createBrowserBackgroundMaintenanceTimerHost,',
    ),
  );
  assert.ok(source.includes('const backgroundMaintenanceTimerHost = createBrowserBackgroundMaintenanceTimerHost();'));
  assert.ok(source.includes('const cleanup = installBackgroundMaintenanceLoop({'));
  assert.ok(source.includes('cancelled = true;'));
  assert.ok(source.includes('cleanup();'));
  assert.ok(source.includes('delayMs: TIMEZONE_CHECK_INTERVAL_MS,'));
  assert.equal((source.match(/timerHost: backgroundMaintenanceTimerHost,/g) ?? []).length, 1);
  assert.ok(!source.includes('globalThis.setTimeout'));
  assert.ok(!source.includes('globalThis.clearTimeout'));
  assert.ok(!source.includes('window.setTimeout('));
  assert.ok(!source.includes('window.clearTimeout('));

  assert.ok(runtimeSource.includes('export function createBrowserBackgroundMaintenanceTimerHost(): BackgroundMaintenanceTimerHost'));
  assert.ok(
    runtimeSource.includes(
      'globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);',
    ),
  );
  assert.ok(
    runtimeSource.includes('setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),'),
  );
});

test('background maintenance runtime owns the browser timer host wiring', () => {
  const host = createBrowserBackgroundMaintenanceTimerHost();
  assert.equal(typeof host.setTimeout, 'function');
  assert.equal(typeof host.clearTimeout, 'function');
});
