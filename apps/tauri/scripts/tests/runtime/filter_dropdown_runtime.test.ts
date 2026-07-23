import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  advanceFilterDropdownTypeAhead,
  clearFilterDropdownTypeAhead,
  createBrowserFilterDropdownTypeAheadTimerHost,
  findFilterDropdownTypeAheadMatch,
  scheduleFilterDropdownInitialFocus,
  type FilterDropdownTypeAheadState,
} from '../../../app/src/components/ui/FilterDropdown.runtime';

const OPTIONS = [
  { label: 'Alpha' },
  { label: 'Beta' },
  { label: 'Bravo' },
  { label: 'Gamma' },
] as const;

test('filter dropdown type-ahead finds the next matching option from current focus', () => {
  assert.equal(findFilterDropdownTypeAheadMatch(OPTIONS, 0, 'b'), 1);
  assert.equal(findFilterDropdownTypeAheadMatch(OPTIONS, 0, 'B'), 1);
  assert.equal(findFilterDropdownTypeAheadMatch(OPTIONS, 1, 'b'), 2);
  assert.equal(findFilterDropdownTypeAheadMatch(OPTIONS, 2, 'b'), 1);
  assert.equal(findFilterDropdownTypeAheadMatch(OPTIONS, 0, 'z'), null);
  assert.equal(findFilterDropdownTypeAheadMatch([], 0, 'b'), null);
});

test('filter dropdown type-ahead accumulates a buffer, resets it by timer, and clears stale timers', () => {
  const state: FilterDropdownTypeAheadState = { timer: 'old', buffer: '' };
  const cleared: unknown[] = [];
  const scheduled: Array<() => void> = [];

  const firstMatch = advanceFilterDropdownTypeAhead({
    state,
    typedChar: 'B',
    options: OPTIONS,
    focusedIndex: 0,
    timerHost: {
      clearTimeout: (handle) => cleared.push(handle),
      setTimeout: (callback) => {
        scheduled.push(callback);
        return `timer-${scheduled.length}`;
      },
    },
  });

  assert.equal(firstMatch, 1);
  assert.equal(state.buffer, 'b');
  assert.equal(state.timer, 'timer-1');
  assert.deepEqual(cleared, ['old']);

  const secondMatch = advanceFilterDropdownTypeAhead({
    state,
    typedChar: 'e',
    options: OPTIONS,
    focusedIndex: 0,
    timerHost: {
      clearTimeout: (handle) => cleared.push(handle),
      setTimeout: (callback) => {
        scheduled.push(callback);
        return `timer-${scheduled.length}`;
      },
    },
  });

  assert.equal(secondMatch, 1);
  assert.equal(state.buffer, 'be');
  assert.equal(state.timer, 'timer-2');
  assert.deepEqual(cleared, ['old', 'timer-1']);

  scheduled.at(-1)?.();
  assert.equal(state.buffer, '');
  assert.equal(state.timer, null);
});

test('filter dropdown type-ahead cleanup clears the pending timer and buffer', () => {
  const state: FilterDropdownTypeAheadState = { timer: 0, buffer: 'br' };
  const cleared: unknown[] = [];

  clearFilterDropdownTypeAhead(state, (handle) => cleared.push(handle));

  assert.deepEqual(cleared, [0]);
  assert.deepEqual(state, { timer: null, buffer: '' });
});

test('filter dropdown initial focus runtime focuses on the next animation frame', () => {
  let frameCallback: (() => void) | undefined;
  const calls: string[] = [];

  scheduleFilterDropdownInitialFocus({
    requestAnimationFrame: (callback) => {
      frameCallback = callback;
      return 'frame-1';
    },
    focusOption: () => calls.push('focus'),
  });

  frameCallback?.();

  assert.deepEqual(calls, ['focus']);
});

test('filter dropdown initial focus runtime can cancel a pending animation frame', () => {
  let frameCallback: (() => void) | undefined;
  const calls: string[] = [];

  const cleanup = scheduleFilterDropdownInitialFocus({
    requestAnimationFrame: (callback) => {
      frameCallback = callback;
      return 'frame-1';
    },
    cancelAnimationFrame: (handle) => calls.push(`cancel:${String(handle)}`),
    focusOption: () => calls.push('focus'),
  });

  cleanup();
  frameCallback?.();

  assert.deepEqual(calls, ['cancel:frame-1']);
});

test('filter dropdown component delegates type-ahead and focus scheduling to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/ui/FilterDropdown.tsx'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/ui/FilterDropdown.runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*advanceFilterDropdownTypeAhead,[\s\S]*clearFilterDropdownTypeAhead,[\s\S]*createBrowserFilterDropdownTypeAheadTimerHost,[\s\S]*scheduleFilterDropdownInitialFocus,[\s\S]*\} from '\.\/FilterDropdown\.runtime';/s,
  );
  assert.match(
    source,
    /import \{[\s\S]*createBrowserPortalDropdownDismissRuntimeDeps,[\s\S]*resolveAnchoredPopupPosition,[\s\S]*startPortalDropdownDismissRuntime,[\s\S]*\} from '\.\/portalDropdown\.runtime';/s,
  );
  assert.match(source, /startPortalDropdownDismissRuntime\(\s*createBrowserPortalDropdownDismissRuntimeDeps\(\{/);
  assert.match(source, /getTrigger: \(\) => triggerRef\.current,/);
  assert.match(source, /getPanel: \(\) => panelRef\.current,/);
  assert.match(source, /const filterDropdownTypeAheadTimerHost = createBrowserFilterDropdownTypeAheadTimerHost\(\);/);
  assert.match(source, /clearFilterDropdownTypeAhead\(\s+typeAheadRef\.current,/);
  assert.match(source, /filterDropdownTypeAheadTimerHost\.clearTimeout/);
  assert.match(source, /if \(open\) return;\s+clearFilterDropdownTypeAhead\(\s+typeAheadRef\.current,\s+filterDropdownTypeAheadTimerHost\.clearTimeout,\s+\);/);
  assert.match(source, /return scheduleFilterDropdownInitialFocus\(\{/);
  assert.match(source, /const matchIndex = advanceFilterDropdownTypeAhead\(\{/);
  assert.match(source, /timerHost: filterDropdownTypeAheadTimerHost,/);
  assert.doesNotMatch(source, /documentTarget: document,/);
  assert.doesNotMatch(source, /windowTarget: window,/);
  assert.doesNotMatch(source, /const node = target as Node \| null;/);
  assert.doesNotMatch(source, /function clearDropdownTimeout/);
  assert.doesNotMatch(source, /function setDropdownTimeout/);
  assert.doesNotMatch(source, /setTimeout\(callback, delayMs\)/);
  assert.doesNotMatch(source, /clearTimeout\(handle/);
  assert.doesNotMatch(source, /requestAnimationFrame\(\(\) => \{/);
  assert.doesNotMatch(source, /ta\.timer = setTimeout/);

  assert.match(runtimeSource, /export function createBrowserFilterDropdownTypeAheadTimerHost\(\): FilterDropdownTypeAheadTimerHost/);
  assert.match(runtimeSource, /globalThis\.clearTimeout\(handle as ReturnType<typeof globalThis\.setTimeout>\);/);
  assert.match(runtimeSource, /setTimeout: \(callback, delayMs\) => globalThis\.setTimeout\(callback, delayMs\),/);
});

test('filter dropdown runtime owns the browser type-ahead timer host wiring', () => {
  const host = createBrowserFilterDropdownTypeAheadTimerHost();
  assert.equal(typeof host.setTimeout, 'function');
  assert.equal(typeof host.clearTimeout, 'function');
});
