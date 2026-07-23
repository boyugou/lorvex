import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  cleanupAssistantSyncAutosaveReset,
  createBrowserAssistantSyncAutosaveTimerHost,
  installAssistantSyncAutosaveRuntime,
  runAssistantSyncAutosaveTick,
  type AssistantSyncAutosaveResetTimerRef,
  type AssistantSyncAutosaveTimerHost,
} from '../../../app/src/components/settings/controller/assistant/sync/autosave.runtime';
import type { SyncBackendSaveState } from '../../../app/src/components/settings/controller/assistant/sync/types';

const repoRoot = process.cwd();

function createTimerHost() {
  const callbacks: Array<() => void> = [];
  const clearedHandles: unknown[] = [];
  const delays: number[] = [];
  const host: AssistantSyncAutosaveTimerHost = {
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

test('assistant sync autosave runtime schedules one delayed tick and clears it', () => {
  const timer = createTimerHost();
  let fired = 0;

  const cleanup = installAssistantSyncAutosaveRuntime({
    delayMs: 250,
    onTick: () => {
      fired += 1;
    },
    timerHost: timer.host,
  });

  assert.deepEqual(timer.delays, [250]);
  assert.equal(fired, 0);
  timer.callbacks[0]?.();
  cleanup();

  assert.equal(fired, 1);
  assert.deepEqual(timer.clearedHandles, ['timer-1']);
});

test('assistant sync autosave tick persists, schedules reset, and clears older reset timers', async () => {
  const timer = createTimerHost();
  const saveStates: SyncBackendSaveState[] = [];
  const resetTimerRef: AssistantSyncAutosaveResetTimerRef = {
    current: 'timer-stale' as ReturnType<typeof globalThis.setTimeout>,
  };

  runAssistantSyncAutosaveTick({
    isCurrent: () => true,
    isMounted: () => true,
    reportSaveError: () => {
      throw new Error('unexpected error report');
    },
    resetDelayMs: 1_200,
    resetTimerRef,
    save: async () => {},
    setSaveState: (value) => {
      saveStates.push(value);
    },
    timerHost: timer.host,
  });

  await Promise.resolve();

  assert.deepEqual(saveStates, ['saving', 'saved']);
  assert.deepEqual(timer.clearedHandles, ['timer-stale']);
  assert.deepEqual(timer.delays, [1_200]);
  assert.equal(resetTimerRef.current, 'timer-1');

  timer.callbacks[0]?.();
  assert.deepEqual(saveStates, ['saving', 'saved', 'idle']);
  assert.equal(resetTimerRef.current, null);
});

test('assistant sync autosave tick reports failures and suppresses stale completions', async () => {
  const timer = createTimerHost();
  const saveStates: SyncBackendSaveState[] = [];
  const reported: unknown[] = [];
  const resetTimerRef: AssistantSyncAutosaveResetTimerRef = { current: null };

  runAssistantSyncAutosaveTick({
    isCurrent: () => false,
    isMounted: () => true,
    reportSaveError: (error) => {
      reported.push(error);
    },
    resetDelayMs: 1_200,
    resetTimerRef,
    save: async () => {},
    setSaveState: (value) => {
      saveStates.push(value);
    },
    timerHost: timer.host,
  });
  await Promise.resolve();

  const failure = new Error('autosave failed');
  runAssistantSyncAutosaveTick({
    isCurrent: () => true,
    isMounted: () => true,
    reportSaveError: (error) => {
      reported.push(error);
    },
    resetDelayMs: 1_200,
    resetTimerRef,
    save: async () => {
      throw failure;
    },
    setSaveState: (value) => {
      saveStates.push(value);
    },
    timerHost: timer.host,
  });
  await Promise.resolve();
  await Promise.resolve();

  assert.equal(saveStates.length, 3);
  assert.equal(saveStates[0], 'saving');
  assert.equal(saveStates[1], 'saving');
  assert.equal(saveStates[2], 'error');
  assert.equal(reported.length, 1);
  assert.equal(reported[0], failure);
  assert.equal(resetTimerRef.current, null);
});

test('assistant sync autosave cleanup clears a pending reset timer once', () => {
  const timer = createTimerHost();
  const resetTimerRef: AssistantSyncAutosaveResetTimerRef = {
    current: 'timer-reset' as ReturnType<typeof globalThis.setTimeout>,
  };

  cleanupAssistantSyncAutosaveReset(resetTimerRef, timer.host);
  cleanupAssistantSyncAutosaveReset(resetTimerRef, timer.host);

  assert.deepEqual(timer.clearedHandles, ['timer-reset']);
  assert.equal(resetTimerRef.current, null);
});

test('assistant sync autosave hook delegates debounce and reset timers to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/controller/assistant/sync/autosave.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*cleanupAssistantSyncAutosaveReset,[\s\S]*createBrowserAssistantSyncAutosaveTimerHost,[\s\S]*installAssistantSyncAutosaveRuntime,[\s\S]*runAssistantSyncAutosaveTick,[\s\S]*\} from '\.\/autosave\.runtime';/s,
  );
  assert.match(
    source,
    /const assistantSyncAutosaveTimerHost = createBrowserAssistantSyncAutosaveTimerHost\(\);/,
  );
  assert.match(
    source,
    /return installAssistantSyncAutosaveRuntime\(\{[\s\S]*delayMs: 250,[\s\S]*runAssistantSyncAutosaveTick\(\{[\s\S]*resetDelayMs: 1200,[\s\S]*save: \(\) => saveSyncBackend\(false\),[\s\S]*setSaveState: setSyncBackendSaveState,[\s\S]*timerHost: assistantSyncAutosaveTimerHost,/s,
  );
  assert.doesNotMatch(source, /globalThis\.setTimeout/);
  assert.doesNotMatch(source, /globalThis\.clearTimeout/);
  assert.doesNotMatch(source, /window\.setTimeout\(/);
  assert.doesNotMatch(source, /window\.clearTimeout\(/);
});

test('assistant sync autosave runtime owns the browser timer host wiring', () => {
  const host = createBrowserAssistantSyncAutosaveTimerHost();
  assert.equal(typeof host.setTimeout, 'function');
  assert.equal(typeof host.clearTimeout, 'function');

  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/controller/assistant/sync/autosave.runtime.ts'),
    'utf8',
  );

  assert.match(source, /export function createBrowserAssistantSyncAutosaveTimerHost\(\): AssistantSyncAutosaveTimerHost/);
  assert.match(
    source,
    /globalThis\.clearTimeout\(handle as ReturnType<typeof globalThis\.setTimeout>\);/,
  );
  assert.match(source, /setTimeout: \(callback, delayMs\) => globalThis\.setTimeout\(callback, delayMs\),/);
});
