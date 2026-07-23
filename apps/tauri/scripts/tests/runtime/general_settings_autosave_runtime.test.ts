import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  cleanupGeneralSettingsAutosaveReset,
  createBrowserGeneralSettingsAutosaveTimerHost,
  installGeneralSettingsAutosaveRuntime,
  runGeneralSettingsAutosaveTick,
  type GeneralSettingsAutosaveResetTimerRef,
  type GeneralSettingsAutosaveState,
  type GeneralSettingsAutosaveTimerHost,
} from '../../../app/src/components/settings/controller/general/autosave.runtime';

const repoRoot = process.cwd();

function createTimerHost() {
  const callbacks: Array<() => void> = [];
  const clearedHandles: unknown[] = [];
  const delays: number[] = [];
  const host: GeneralSettingsAutosaveTimerHost = {
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

test('general settings autosave runtime schedules one delayed tick and clears it', () => {
  const timer = createTimerHost();
  let fired = 0;

  const cleanup = installGeneralSettingsAutosaveRuntime({
    delayMs: 250,
    onTick: () => {
      fired += 1;
    },
    timerHost: timer.host,
  });

  assert.deepEqual(timer.delays, [250]);
  timer.callbacks[0]?.();
  cleanup();

  assert.equal(fired, 1);
  assert.deepEqual(timer.clearedHandles, ['timer-1']);
});

test('general settings autosave tick persists, schedules reset, and clears stale reset timers', async () => {
  const timer = createTimerHost();
  const states: GeneralSettingsAutosaveState[] = [];
  const resetTimerRef: GeneralSettingsAutosaveResetTimerRef = {
    current: 'timer-stale' as ReturnType<typeof globalThis.setTimeout>,
  };

  runGeneralSettingsAutosaveTick({
    action: async () => {},
    reportSaveError: () => {
      throw new Error('unexpected error report');
    },
    resetDelayMs: 1400,
    resetTimerRef,
    setAutosaveState: (value) => {
      states.push(value);
    },
    timerHost: timer.host,
  });
  await Promise.resolve();

  assert.deepEqual(states, ['saved']);
  assert.deepEqual(timer.clearedHandles, ['timer-stale']);
  assert.deepEqual(timer.delays, [1400]);
  assert.equal(resetTimerRef.current, 'timer-1');

  timer.callbacks[0]?.();
  assert.deepEqual(states, ['saved', 'idle']);
  assert.equal(resetTimerRef.current, null);
});

test('general settings autosave tick reports failures without scheduling a reset timer', async () => {
  const timer = createTimerHost();
  const states: GeneralSettingsAutosaveState[] = [];
  const reported: unknown[] = [];
  const failure = new Error('persist failed');

  runGeneralSettingsAutosaveTick({
    action: async () => {
      throw failure;
    },
    reportSaveError: (error) => {
      reported.push(error);
    },
    resetDelayMs: 1400,
    resetTimerRef: { current: null },
    setAutosaveState: (value) => {
      states.push(value);
    },
    timerHost: timer.host,
  });
  await Promise.resolve();
  await Promise.resolve();

  assert.deepEqual(states, ['error']);
  assert.deepEqual(reported, [failure]);
  assert.deepEqual(timer.delays, []);
});

test('general settings autosave cleanup clears a pending reset timer once', () => {
  const timer = createTimerHost();
  const resetTimerRef: GeneralSettingsAutosaveResetTimerRef = {
    current: 'timer-reset' as ReturnType<typeof globalThis.setTimeout>,
  };

  cleanupGeneralSettingsAutosaveReset(resetTimerRef, timer.host);
  cleanupGeneralSettingsAutosaveReset(resetTimerRef, timer.host);

  assert.deepEqual(timer.clearedHandles, ['timer-reset']);
  assert.equal(resetTimerRef.current, null);
});

test('general settings autosave hook delegates debounce and reset timers to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/controller/general/autosave.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*cleanupGeneralSettingsAutosaveReset,[\s\S]*createBrowserGeneralSettingsAutosaveTimerHost,[\s\S]*installGeneralSettingsAutosaveRuntime,[\s\S]*runGeneralSettingsAutosaveTick,[\s\S]*\} from '\.\/autosave\.runtime';/s,
  );
  assert.match(
    source,
    /const generalSettingsAutosaveTimerHost = createBrowserGeneralSettingsAutosaveTimerHost\(\);/,
  );
  assert.match(
    source,
    /runGeneralSettingsAutosaveTick\(\{[\s\S]*resetDelayMs: 1400,[\s\S]*setAutosaveState,[\s\S]*timerHost: generalSettingsAutosaveTimerHost,/s,
  );
  assert.match(
    source,
    /return installGeneralSettingsAutosaveRuntime\(\{[\s\S]*delayMs: 250,[\s\S]*void runAutosave\(persistWorkingHours\);[\s\S]*\}\);/s,
  );
  assert.match(
    source,
    /return installGeneralSettingsAutosaveRuntime\(\{[\s\S]*delayMs: 300,[\s\S]*void runAutosave\(persistAdvanced\);[\s\S]*\}\);/s,
  );
  assert.doesNotMatch(source, /globalThis\.setTimeout/);
  assert.doesNotMatch(source, /globalThis\.clearTimeout/);
  assert.doesNotMatch(source, /window\.setTimeout\(/);
  assert.doesNotMatch(source, /window\.clearTimeout\(/);
});

test('general settings autosave runtime owns the browser timer host wiring', () => {
  const host = createBrowserGeneralSettingsAutosaveTimerHost();
  assert.equal(typeof host.setTimeout, 'function');
  assert.equal(typeof host.clearTimeout, 'function');

  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/controller/general/autosave.runtime.ts'),
    'utf8',
  );

  assert.match(source, /export function createBrowserGeneralSettingsAutosaveTimerHost\(\): GeneralSettingsAutosaveTimerHost/);
  assert.match(
    source,
    /globalThis\.clearTimeout\(handle as ReturnType<typeof globalThis\.setTimeout>\);/,
  );
  assert.match(source, /setTimeout: \(callback, delayMs\) => globalThis\.setTimeout\(callback, delayMs\),/);
});
