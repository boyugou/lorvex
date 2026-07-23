import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  MAX_TOASTS,
  __getToastsForTests,
  __resetToastsForTests,
  __setToastTimerHostForTests,
  toast,
} from '../../../app/src/lib/notifications/toast';
import {
  createBrowserToastTimerHost,
  scheduleToastTimer,
  type ToastTimerHost,
} from '../../../app/src/lib/notifications/toast.runtime';

test.after(() => {
  __setToastTimerHostForTests(null);
});

// These tests cover the store-level eviction + duration plumbing added
// under issue #2550. They exercise the module-level singleton directly
// via the exported test helpers rather than mounting React.
//
// Invariants under test:
//   1. A `priority` toast survives MAX_TOASTS overflow when non-priority
//      toasts (including single-task actionable ones) would otherwise
//      push it out.
//   2. Eviction prefers plain toasts over actionable toasts, and
//      actionable toasts over priority toasts.
//   3. When every visible toast is priority, the OLDEST priority is
//      dropped so new toasts can still appear — priority means
//      "resilient," not "immortal."
//   4. The actionable `options` object lets callers override the default
//      duration. We don't assert auto-dismiss timing end-to-end (that
//      would hang the test on setTimeout) — we only assert the toast
//      enters the store with the action attached, since the dismiss
//      path is covered by the shared setTimeout/dedup invariants.

function resetForContext(context: string): string {
  __setToastTimerHostForTests({
    setTimeout: () => null,
    clearTimeout: () => {},
  });
  __resetToastsForTests();
  // Every subtest uses a unique context-suffixed message so that the
  // module-level dedup window (1s for success) cannot swallow legitimate
  // successive toasts across assertions.
  return context;
}

test('toast runtime schedules timers through the injected host', () => {
  const callbacks: Array<() => void> = [];
  const delays: number[] = [];
  const host: ToastTimerHost = {
    setTimeout: (callback, delayMs) => {
      callbacks.push(callback);
      delays.push(delayMs);
      return `toast-timer-${callbacks.length}`;
    },
  };

  let callCount = 0;
  scheduleToastTimer(host, () => {
    callCount += 1;
  }, 220);

  assert.deepEqual(delays, [220]);
  assert.equal(callCount, 0);

  callbacks[0]?.();
  assert.equal(callCount, 1);
});

test('toast store delegates browser timer wiring to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/notifications/toast/store.ts'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/notifications/toast.runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserToastTimerHost,[\s\S]*scheduleToastTimer,[\s\S]*\} from '\.\.\/toast\.runtime';/s,
  );
  assert.match(source, /let toastTimerHost: ToastTimerHost = createBrowserToastTimerHost\(\);/);
  assert.match(
    source,
    /safetyCancellers\.set\(\s*id,\s*scheduleToastTimer\(toastTimerHost, \(\) => removeToast\(id\), EXIT_TRANSITION_MS\),\s*\);/s,
  );
  assert.match(source, /const cancel = safetyCancellers\.get\(id\);/);
  assert.match(source, /scheduleToastTimer\(toastTimerHost, \(\) => dismissToast\(id\), durationMs\);/);
  assert.doesNotMatch(source, /(?<!\.)\bsetTimeout\(/);

  assert.match(runtimeSource, /export function createBrowserToastTimerHost\(\): ToastTimerHost/);
  assert.match(runtimeSource, /setTimeout: \(callback, delayMs\) => globalThis\.setTimeout\(callback, delayMs\),/);
});

test('toast runtime owns the browser timer host wiring', () => {
  const host = createBrowserToastTimerHost();
  assert.equal(typeof host.setTimeout, 'function');
});

test('toast: priority toast survives MAX_TOASTS overflow', () => {
  const ctx = resetForContext('priority-survives');
  toast.success(
    `${ctx}-pinned`,
    { label: 'Undo', onClick: () => {} },
    undefined,
    { priority: true },
  );

  // Flood with MAX_TOASTS plain successes, each with a distinct context
  // so dedup doesn't drop them.
  for (let i = 0; i < MAX_TOASTS + 3; i++) {
    toast.success(`${ctx}-plain-${i}`, `${i}`);
  }

  const stack = __getToastsForTests();
  assert.ok(stack.length <= MAX_TOASTS, `stack length ${stack.length} exceeded MAX_TOASTS`);
  const pinned = stack.find((t) => t.message === `${ctx}-pinned`);
  assert.ok(pinned, 'priority toast should still be present');
  assert.equal(pinned?.priority, true);
});

test('toast: eviction prefers plain > actionable > priority', () => {
  const ctx = resetForContext('eviction-order');
  // Layer 1: plain toast (should be sacrificed first)
  toast.success(`${ctx}-plain`, `${ctx}-plain`);
  // Layer 2: actionable but non-priority (single-task undo)
  toast.success(
    `${ctx}-actionable`,
    { label: 'Undo', onClick: () => {} },
    `${ctx}-actionable`,
  );
  // Layer 3: priority bulk-undo
  toast.success(
    `${ctx}-priority`,
    { label: 'Undo', onClick: () => {} },
    undefined,
    { priority: true },
  );
  // Fill to MAX_TOASTS with more actionable (non-priority) toasts so the
  // plain toast is the sole sacrifice candidate on the next push.
  for (let i = 0; i < MAX_TOASTS - 3; i++) {
    toast.success(
      `${ctx}-filler-${i}`,
      { label: 'Undo', onClick: () => {} },
      `${ctx}-filler-${i}`,
    );
  }

  // Push one more — overflow by 1. Plain should be evicted.
  toast.success(
    `${ctx}-trigger`,
    { label: 'Undo', onClick: () => {} },
    `${ctx}-trigger`,
  );
  let stack = __getToastsForTests();
  assert.equal(stack.length, MAX_TOASTS);
  assert.ok(!stack.some((t) => t.message === `${ctx}-plain`), 'plain toast should be gone first');
  assert.ok(stack.some((t) => t.message === `${ctx}-actionable`), 'actionable still present');
  assert.ok(stack.some((t) => t.message === `${ctx}-priority`), 'priority still present');

  // Push again — now only actionable vs priority remain as candidates;
  // the actionable toast should be sacrificed before the priority one.
  toast.success(
    `${ctx}-trigger2`,
    { label: 'Undo', onClick: () => {} },
    `${ctx}-trigger2`,
  );
  stack = __getToastsForTests();
  assert.equal(stack.length, MAX_TOASTS);
  assert.ok(!stack.some((t) => t.message === `${ctx}-actionable`), 'actionable toast evicted next');
  assert.ok(stack.some((t) => t.message === `${ctx}-priority`), 'priority still protected');
});

test('toast: when all visible are priority, oldest priority drops', () => {
  const ctx = resetForContext('all-priority');
  // MAX_TOASTS + 1 priority toasts — one must drop, and it must be the
  // oldest (FIFO) since none are sacrificable under the normal rules.
  for (let i = 0; i < MAX_TOASTS + 1; i++) {
    toast.success(
      `${ctx}-${i}`,
      { label: 'Undo', onClick: () => {} },
      `${ctx}-${i}`,
      { priority: true },
    );
  }
  const stack = __getToastsForTests();
  assert.equal(stack.length, MAX_TOASTS);
  // Oldest (index 0) is `${ctx}-0`; should have been evicted.
  assert.ok(!stack.some((t) => t.message === `${ctx}-0`), 'oldest priority toast evicted');
  assert.ok(stack.some((t) => t.message === `${ctx}-${MAX_TOASTS}`), 'newest priority still present');
});

test('toast: actionable options carry an Undo action into the store', () => {
  const ctx = resetForContext('action-label');
  toast.success(
    `${ctx}-msg`,
    { label: 'Undo', onClick: () => {} },
    undefined,
    { durationMs: 9000, priority: true },
  );
  const stack = __getToastsForTests();
  const item = stack.find((t) => t.message === `${ctx}-msg`);
  assert.ok(item, 'toast should be in store');
  assert.equal(item?.action?.label, 'Undo');
  assert.equal(item?.priority, true);
});
