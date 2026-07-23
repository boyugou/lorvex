import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  cleanupChangelogActionFeedbackReset,
  createBrowserChangelogActionFeedbackTimerHost,
  createChangelogActionFeedbackRuntimeState,
  scheduleChangelogActionFeedbackReset,
  type ChangelogActionFeedbackTimerHost,
} from '../../../app/src/components/changelog/actionFeedback.runtime';

const repoRoot = process.cwd();

function createTimerHost() {
  const callbacks: Array<() => void> = [];
  const clearedHandles: unknown[] = [];
  const delays: number[] = [];
  const host: ChangelogActionFeedbackTimerHost = {
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

test('changelog action feedback runtime schedules a mounted message reset', () => {
  const timer = createTimerHost();
  const state = createChangelogActionFeedbackRuntimeState();
  const published: Array<string | null> = [];

  scheduleChangelogActionFeedbackReset({
    delayMs: 3000,
    isMounted: () => true,
    setActionMessage: (value) => {
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
  assert.deepEqual(published, [null]);
});

test('changelog action feedback runtime cancels an older reset before scheduling a newer one', () => {
  const timer = createTimerHost();
  const state = createChangelogActionFeedbackRuntimeState();
  const published: Array<string | null> = [];

  const deps = {
    delayMs: 8000,
    isMounted: () => true,
    setActionMessage: (value: string | null) => {
      published.push(value);
    },
    state,
    timerHost: timer.host,
  };

  scheduleChangelogActionFeedbackReset(deps);
  scheduleChangelogActionFeedbackReset(deps);
  timer.callbacks[1]?.();

  assert.deepEqual(timer.clearedHandles, ['timer-1']);
  assert.deepEqual(published, [null]);
  assert.equal(state.resetTimer, null);
});

test('changelog action feedback runtime suppresses reset after unmount', () => {
  const timer = createTimerHost();
  const state = createChangelogActionFeedbackRuntimeState();
  const published: Array<string | null> = [];

  scheduleChangelogActionFeedbackReset({
    delayMs: 3000,
    isMounted: () => false,
    setActionMessage: (value) => {
      published.push(value);
    },
    state,
    timerHost: timer.host,
  });
  timer.callbacks[0]?.();

  assert.deepEqual(published, []);
  assert.equal(state.resetTimer, null);
});

test('changelog action feedback runtime cleanup clears a pending timer once', () => {
  const timer = createTimerHost();
  const state = createChangelogActionFeedbackRuntimeState();

  scheduleChangelogActionFeedbackReset({
    delayMs: 3000,
    isMounted: () => true,
    setActionMessage: () => {},
    state,
    timerHost: timer.host,
  });
  cleanupChangelogActionFeedbackReset(state, timer.host);
  cleanupChangelogActionFeedbackReset(state, timer.host);

  assert.deepEqual(timer.clearedHandles, ['timer-1']);
  assert.equal(state.resetTimer, null);
});

test('changelog controller delegates action feedback reset timing to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/changelog/useChangelogController.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*cleanupChangelogActionFeedbackReset,[\s\S]*createBrowserChangelogActionFeedbackTimerHost,[\s\S]*createChangelogActionFeedbackRuntimeState,[\s\S]*scheduleChangelogActionFeedbackReset,[\s\S]*\} from '\.\/actionFeedback\.runtime';/,
  );
  assert.match(
    source,
    /const actionFeedbackRuntimeStateRef = useLazyRef\(\(\) => createChangelogActionFeedbackRuntimeState\(\)\);/,
  );
  assert.match(
    source,
    /const actionFeedbackTimerHostRef = useLazyRef\(\(\) => createBrowserChangelogActionFeedbackTimerHost\(\)\);/,
  );
  assert.match(source, /scheduleChangelogActionFeedbackReset\(\{[\s\S]*delayMs: isError \? 8000 : 3000,[\s\S]*isMounted: \(\) => changelogMountedRef\.current,[\s\S]*setActionMessage,/);
  assert.match(
    source,
    /timerHost: actionFeedbackTimerHostRef\.current,/,
  );
  assert.match(
    source,
    /cleanupChangelogActionFeedbackReset\([\s\S]*actionFeedbackRuntimeStateRef\.current,[\s\S]*actionFeedbackTimerHostRef\.current,[\s\S]*\);/s,
  );
  assert.doesNotMatch(source, /actionTimerRef/);
  assert.doesNotMatch(source, /globalThis\.setTimeout/);
  assert.doesNotMatch(source, /globalThis\.clearTimeout/);
  assert.doesNotMatch(source, /window\.setTimeout\(\(\) => \{\s*if \(changelogMountedRef\.current\) setActionMessage\(null\);/);
});

test('changelog action feedback runtime owns the browser timer host wiring', () => {
  const host = createBrowserChangelogActionFeedbackTimerHost();
  assert.equal(typeof host.setTimeout, 'function');
  assert.equal(typeof host.clearTimeout, 'function');

  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/changelog/actionFeedback.runtime.ts'),
    'utf8',
  );

  assert.match(source, /export function createBrowserChangelogActionFeedbackTimerHost\(\): ChangelogActionFeedbackTimerHost/);
  assert.match(
    source,
    /globalThis\.clearTimeout\(handle as ReturnType<typeof globalThis\.setTimeout>\);/,
  );
  assert.match(source, /setTimeout: \(callback, delayMs\) => globalThis\.setTimeout\(callback, delayMs\),/);
});
