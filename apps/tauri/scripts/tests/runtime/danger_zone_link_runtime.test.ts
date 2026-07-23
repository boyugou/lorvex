import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  cleanupDangerZoneLinkFocus,
  createBrowserDangerZoneLinkTimerHost,
  createDangerZoneLinkRuntimeState,
  scheduleDangerZoneLinkFocus,
  type DangerZoneLinkFocusTarget,
  type DangerZoneLinkTimerHost,
} from '../../../app/src/components/settings/data/dangerZoneLink.runtime';

const repoRoot = process.cwd();

function createTimerHost() {
  const callbacks: Array<() => void> = [];
  const clearedHandles: unknown[] = [];
  const delays: number[] = [];
  const host: DangerZoneLinkTimerHost = {
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

function createTarget(hasHeading = true) {
  const focusCalls: unknown[] = [];
  const scrollCalls: unknown[] = [];
  const heading = hasHeading
    ? {
        focus: (options?: FocusOptions) => {
          focusCalls.push(options);
        },
      }
    : null;
  const target: DangerZoneLinkFocusTarget = {
    querySelector: (selector) => {
      assert.equal(selector, 'h2');
      return heading as HTMLElement | null;
    },
    scrollIntoView: (options) => {
      scrollCalls.push(options);
    },
  };

  return {
    focusCalls,
    scrollCalls,
    target,
  };
}

test('danger zone link runtime scrolls immediately and focuses heading after delay', () => {
  const timer = createTimerHost();
  const target = createTarget();
  const state = createDangerZoneLinkRuntimeState();

  scheduleDangerZoneLinkFocus({
    delayMs: 300,
    state,
    target: target.target,
    timerHost: timer.host,
  });

  assert.equal(state.focusTimer, 'timer-1');
  assert.deepEqual(timer.delays, [300]);
  assert.deepEqual(target.scrollCalls, [{ behavior: 'smooth', block: 'start' }]);
  assert.deepEqual(target.focusCalls, []);

  timer.callbacks[0]?.();

  assert.equal(state.focusTimer, null);
  assert.deepEqual(target.focusCalls, [{ preventScroll: true }]);
});

test('danger zone link runtime cancels an older pending focus before scheduling a newer one', () => {
  const timer = createTimerHost();
  const target = createTarget();
  const state = createDangerZoneLinkRuntimeState();
  const deps = {
    delayMs: 300,
    state,
    target: target.target,
    timerHost: timer.host,
  };

  scheduleDangerZoneLinkFocus(deps);
  scheduleDangerZoneLinkFocus(deps);
  timer.callbacks[1]?.();

  assert.deepEqual(timer.clearedHandles, ['timer-1']);
  assert.equal(state.focusTimer, null);
  assert.deepEqual(target.scrollCalls, [
    { behavior: 'smooth', block: 'start' },
    { behavior: 'smooth', block: 'start' },
  ]);
  assert.deepEqual(target.focusCalls, [{ preventScroll: true }]);
});

test('danger zone link runtime tolerates a missing heading', () => {
  const timer = createTimerHost();
  const target = createTarget(false);
  const state = createDangerZoneLinkRuntimeState();

  scheduleDangerZoneLinkFocus({
    delayMs: 300,
    state,
    target: target.target,
    timerHost: timer.host,
  });
  timer.callbacks[0]?.();

  assert.equal(state.focusTimer, null);
  assert.deepEqual(target.focusCalls, []);
});

test('danger zone link runtime cleanup clears a pending focus once', () => {
  const timer = createTimerHost();
  const target = createTarget();
  const state = createDangerZoneLinkRuntimeState();

  scheduleDangerZoneLinkFocus({
    delayMs: 300,
    state,
    target: target.target,
    timerHost: timer.host,
  });
  cleanupDangerZoneLinkFocus(state, timer.host);
  cleanupDangerZoneLinkFocus(state, timer.host);

  assert.deepEqual(timer.clearedHandles, ['timer-1']);
  assert.equal(state.focusTimer, null);
});

test('danger zone link component delegates delayed focus to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/data/DangerZoneLink.tsx'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*cleanupDangerZoneLinkFocus,[\s\S]*createBrowserDangerZoneLinkTimerHost,[\s\S]*createDangerZoneLinkRuntimeState,[\s\S]*scheduleDangerZoneLinkFocus,[\s\S]*\} from '\.\/dangerZoneLink\.runtime';/,
  );
  assert.match(source, /const runtimeStateRef = useLazyRef\(\(\) => createDangerZoneLinkRuntimeState\(\)\);/);
  assert.match(source, /const timerHostRef = useLazyRef\(\(\) => createBrowserDangerZoneLinkTimerHost\(\)\);/);
  assert.match(source, /scheduleDangerZoneLinkFocus\(\{[\s\S]*delayMs: 300,[\s\S]*state: runtimeStateRef\.current,[\s\S]*target: el,/);
  assert.match(
    source,
    /timerHost: timerHostRef\.current,/,
  );
  assert.match(
    source,
    /cleanupDangerZoneLinkFocus\(runtimeStateRef\.current, timerHostRef\.current\);/,
  );
  assert.match(source, /cleanupDangerZoneLinkFocus\(runtimeStateRef\.current,/);
  assert.doesNotMatch(source, /globalThis\.setTimeout/);
  assert.doesNotMatch(source, /globalThis\.clearTimeout/);
  assert.doesNotMatch(source, /window\.setTimeout\(\(\) => \{[\s\S]*querySelector<HTMLElement>\('h2'\)/);
});

test('danger zone link runtime owns the browser timer host wiring', () => {
  const host = createBrowserDangerZoneLinkTimerHost();
  assert.equal(typeof host.setTimeout, 'function');
  assert.equal(typeof host.clearTimeout, 'function');

  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/data/dangerZoneLink.runtime.ts'),
    'utf8',
  );

  assert.match(source, /export function createBrowserDangerZoneLinkTimerHost\(\): DangerZoneLinkTimerHost/);
  assert.match(
    source,
    /globalThis\.clearTimeout\(handle as ReturnType<typeof globalThis\.setTimeout>\);/,
  );
  assert.match(source, /setTimeout: \(callback, delayMs\) => globalThis\.setTimeout\(callback, delayMs\),/);
});
