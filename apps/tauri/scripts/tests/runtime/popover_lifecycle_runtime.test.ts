import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  clearPopoverPendingHideTimer,
  createBrowserPopoverPendingHideTimerHost,
  schedulePopoverPendingHide,
  type PopoverPendingHideTimerHost,
  type PopoverPendingHideTimerRef,
} from '../../../app/src/components/popover-window/controller/lifecycle.runtime';

const repoRoot = process.cwd();

function createTimerHost() {
  const callbacks: Array<() => void> = [];
  const clearedHandles: unknown[] = [];
  const delays: number[] = [];
  const host: PopoverPendingHideTimerHost = {
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

test('popover pending-hide runtime schedules one delayed callback and clears ref after firing', () => {
  const timer = createTimerHost();
  const pendingHideTimerRef: PopoverPendingHideTimerRef = { current: null };
  let fired = 0;

  schedulePopoverPendingHide(pendingHideTimerRef, timer.host, 160, () => {
    fired += 1;
  });

  assert.equal(pendingHideTimerRef.current, 'timer-1');
  assert.deepEqual(timer.delays, [160]);

  timer.callbacks[0]?.();

  assert.equal(fired, 1);
  assert.equal(pendingHideTimerRef.current, null);
});

test('popover pending-hide runtime clears an older timer before scheduling a newer one', () => {
  const timer = createTimerHost();
  const pendingHideTimerRef: PopoverPendingHideTimerRef = { current: null };

  schedulePopoverPendingHide(pendingHideTimerRef, timer.host, 160, () => {});
  schedulePopoverPendingHide(pendingHideTimerRef, timer.host, 160, () => {});

  assert.deepEqual(timer.clearedHandles, ['timer-1']);
  assert.equal(pendingHideTimerRef.current, 'timer-2');
});

test('popover pending-hide runtime cleanup clears a pending timer once', () => {
  const timer = createTimerHost();
  const pendingHideTimerRef: PopoverPendingHideTimerRef = {
    current: 'timer-pending' as ReturnType<typeof globalThis.setTimeout>,
  };

  clearPopoverPendingHideTimer(pendingHideTimerRef, timer.host);
  clearPopoverPendingHideTimer(pendingHideTimerRef, timer.host);

  assert.deepEqual(timer.clearedHandles, ['timer-pending']);
  assert.equal(pendingHideTimerRef.current, null);
});

test('popover lifecycle delegates pending-hide timer wiring through the browser host seam', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/popover-window/controller/lifecycle.ts'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/popover-window/controller/lifecycle.runtime.ts'),
    'utf8',
  );

  assert.ok(
    source.includes(
      'createBrowserPopoverPendingHideTimerHost,',
    ),
  );
  assert.ok(source.includes('const popoverPendingHideTimerHost = createBrowserPopoverPendingHideTimerHost();'));
  assert.ok(source.includes('clearPopoverPendingHideTimer(pendingHideTimerRef, popoverPendingHideTimerHost);'));
  assert.ok(source.includes('schedulePopoverPendingHide('));
  assert.ok(source.includes('popoverPendingHideTimerHost,'));
  assert.ok(!source.includes('globalThis.setTimeout'));
  assert.ok(!source.includes('globalThis.clearTimeout'));
  assert.ok(!source.includes('window.setTimeout(() => {'));
  assert.ok(!source.includes('window.clearTimeout(pendingHideTimerRef.current)'));

  assert.ok(runtimeSource.includes('export function createBrowserPopoverPendingHideTimerHost(): PopoverPendingHideTimerHost'));
  assert.ok(
    runtimeSource.includes(
      'globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);',
    ),
  );
  assert.ok(runtimeSource.includes('setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),'));
});

test('popover pending-hide runtime owns the browser timer host wiring', () => {
  const host = createBrowserPopoverPendingHideTimerHost();
  assert.equal(typeof host.setTimeout, 'function');
  assert.equal(typeof host.clearTimeout, 'function');
});
