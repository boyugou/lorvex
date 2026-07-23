import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  cleanupDailyReviewJustSavedReset,
  createBrowserDailyReviewTimerHost,
  createDailyReviewJustSavedRuntimeState,
  scheduleDailyReviewJustSavedReset,
  type DailyReviewJustSavedTimerHost,
} from '../../../app/src/components/daily-review/controller/justSaved.runtime';

const repoRoot = process.cwd();

function createTimerHost() {
  const callbacks: Array<() => void> = [];
  const clearedHandles: unknown[] = [];
  const delays: number[] = [];
  const host: DailyReviewJustSavedTimerHost = {
    clearTimeout: (handle) => {
      clearedHandles.push(handle);
    },
    setTimeout: (callback, delayMs) => {
      callbacks.push(callback);
      delays.push(delayMs);
      return `timer-${callbacks.length}`;
    },
  };

  return {
    callbacks,
    clearedHandles,
    delays,
    host,
  };
}

test('daily review just-saved runtime schedules a delayed mounted reset', () => {
  const timer = createTimerHost();
  const state = createDailyReviewJustSavedRuntimeState();
  const published: boolean[] = [];

  scheduleDailyReviewJustSavedReset({
    delayMs: 3000,
    isMounted: () => true,
    setJustSaved: (value) => {
      published.push(value);
    },
    state,
    timerHost: timer.host,
  });

  assert.equal(state.resetTimer, 'timer-1');
  assert.deepEqual(timer.delays, [3000]);
  assert.deepEqual(published, []);

  timer.callbacks[0]?.();
  assert.equal(state.resetTimer, null);
  assert.deepEqual(published, [false]);
});

test('daily review just-saved runtime cancels an older reset before scheduling a newer one', () => {
  const timer = createTimerHost();
  const state = createDailyReviewJustSavedRuntimeState();
  const published: boolean[] = [];

  const deps = {
    delayMs: 3000,
    isMounted: () => true,
    setJustSaved: (value: boolean) => {
      published.push(value);
    },
    state,
    timerHost: timer.host,
  };

  scheduleDailyReviewJustSavedReset(deps);
  scheduleDailyReviewJustSavedReset(deps);
  timer.callbacks[1]?.();

  assert.deepEqual(timer.clearedHandles, ['timer-1']);
  assert.deepEqual(published, [false]);
  assert.equal(state.resetTimer, null);
});

test('daily review just-saved runtime suppresses reset after unmount', () => {
  const timer = createTimerHost();
  const state = createDailyReviewJustSavedRuntimeState();
  const published: boolean[] = [];

  scheduleDailyReviewJustSavedReset({
    delayMs: 3000,
    isMounted: () => false,
    setJustSaved: (value) => {
      published.push(value);
    },
    state,
    timerHost: timer.host,
  });
  timer.callbacks[0]?.();

  assert.deepEqual(published, []);
  assert.equal(state.resetTimer, null);
});

test('daily review just-saved runtime cleanup clears a pending timer once', () => {
  const timer = createTimerHost();
  const state = createDailyReviewJustSavedRuntimeState();

  scheduleDailyReviewJustSavedReset({
    delayMs: 3000,
    isMounted: () => true,
    setJustSaved: () => {},
    state,
    timerHost: timer.host,
  });
  cleanupDailyReviewJustSavedReset(state, timer.host);
  cleanupDailyReviewJustSavedReset(state, timer.host);

  assert.deepEqual(timer.clearedHandles, ['timer-1']);
  assert.equal(state.resetTimer, null);
});

test('daily review controller delegates just-saved reset timing to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/daily-review/controller/useDailyReviewController.ts'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/daily-review/controller/justSaved.runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*cleanupDailyReviewJustSavedReset,[\s\S]*createBrowserDailyReviewTimerHost,[\s\S]*createDailyReviewJustSavedRuntimeState,[\s\S]*scheduleDailyReviewJustSavedReset,[\s\S]*\} from '\.\/justSaved\.runtime';/,
  );
  assert.match(source, /const justSavedRuntimeStateRef = useLazyRef\(\(\) => createDailyReviewJustSavedRuntimeState\(\)\);/);
  assert.match(source, /scheduleDailyReviewJustSavedReset\(\{[\s\S]*delayMs: 3000,[\s\S]*isMounted: \(\) => mountedRef\.current,[\s\S]*setJustSaved,/);
  assert.match(source, /timerHost: createBrowserDailyReviewTimerHost\(\),/);
  assert.match(source, /cleanupDailyReviewJustSavedReset\(\s*justSavedRuntimeStateRef\.current,\s*createBrowserDailyReviewTimerHost\(\),\s*\);/s);
  assert.doesNotMatch(source, /justSavedTimerRef/);
  assert.doesNotMatch(source, /clearTimeout: \(handle\) => clearTimeout/);
  assert.doesNotMatch(source, /setTimeout: \(callback, delayMs\) => setTimeout/);

  assert.equal(typeof createBrowserDailyReviewTimerHost, 'function');
  assert.match(
    runtimeSource,
    /export function createBrowserDailyReviewTimerHost\(\): DailyReviewJustSavedTimerHost \{/,
  );
  assert.match(
    runtimeSource,
    /globalThis\.clearTimeout\(handle as ReturnType<typeof globalThis\.setTimeout>\);/,
  );
  assert.match(
    runtimeSource,
    /setTimeout: \(callback, delayMs\) => globalThis\.setTimeout\(callback, delayMs\),/,
  );
});
