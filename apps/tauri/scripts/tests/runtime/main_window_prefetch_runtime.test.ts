import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserMainWindowPrefetchHost,
  installMainWindowPrefetchRuntime,
} from '../../../app/src/app-shell/main-window/runtime/useMainWindowPrefetch.runtime';

test('main window prefetch runtime prefers requestIdleCallback and cancels it on cleanup', () => {
  const prefetchCalls: string[] = [];
  const cancelled: unknown[] = [];

  const handle = installMainWindowPrefetchRuntime({
    cancelIdleCallback: (idleHandle) => {
      cancelled.push(idleHandle);
    },
    clearTimeout: () => {
      throw new Error('timeout fallback should not be used');
    },
    fallbackDelayMs: 0,
    prefetch: () => {
      prefetchCalls.push('prefetch');
    },
    requestIdleCallback: (callback) => {
      callback();
      return 'idle-handle';
    },
    setTimeout: () => {
      throw new Error('timeout fallback should not be used');
    },
  });

  assert.deepEqual(prefetchCalls, ['prefetch']);
  handle.dispose();
  assert.deepEqual(cancelled, ['idle-handle']);
});

test('main window prefetch runtime falls back to timeout and clears it on cleanup', () => {
  const callbacks: Array<() => void> = [];
  const cleared: unknown[] = [];
  const prefetchCalls: string[] = [];

  const handle = installMainWindowPrefetchRuntime({
    cancelIdleCallback: null,
    clearTimeout: (timeoutHandle) => {
      cleared.push(timeoutHandle);
    },
    fallbackDelayMs: 0,
    prefetch: () => {
      prefetchCalls.push('prefetch');
    },
    requestIdleCallback: null,
    setTimeout: (callback, delayMs) => {
      assert.equal(delayMs, 0);
      callbacks.push(callback);
      return 'timeout-handle';
    },
  });

  assert.deepEqual(prefetchCalls, []);
  callbacks[0]?.();
  assert.deepEqual(prefetchCalls, ['prefetch']);
  handle.dispose();
  assert.deepEqual(cleared, ['timeout-handle']);
});

test('main window app delegates deferred prefetch browser scheduling to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/app-shell/MainWindowApp.tsx'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/app-shell/main-window/runtime/useMainWindowPrefetch.runtime.ts'),
    'utf8',
  );
  const prefetchEffectSource = source.slice(
    source.indexOf('useEffect(() => {'),
    source.indexOf('return (', source.indexOf('useEffect(() => {')),
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserMainWindowPrefetchHost,[\s\S]*installMainWindowPrefetchRuntime,[\s\S]*\} from '\.\/main-window\/runtime\/useMainWindowPrefetch\.runtime';/s,
  );
  assert.match(source, /const mainWindowPrefetchHost = createBrowserMainWindowPrefetchHost\(\);/);
  assert.match(
    prefetchEffectSource,
    /installMainWindowPrefetchRuntime\(\{[\s\S]*fallbackDelayMs: 0,[\s\S]*import\('\.\.\/components\/AllTasksView'\);[\s\S]*import\('\.\.\/components\/UpcomingView'\);[\s\S]*import\('\.\.\/components\/ListView'\);[\s\S]*\.\.\.mainWindowPrefetchHost,[\s\S]*\}\);/s,
  );
  assert.doesNotMatch(prefetchEffectSource, /setTimeout\(/);
  assert.doesNotMatch(prefetchEffectSource, /clearTimeout\(/);
  assert.doesNotMatch(prefetchEffectSource, /requestIdleCallback/);
  assert.doesNotMatch(prefetchEffectSource, /cancelIdleCallback/);

  assert.match(runtimeSource, /export function createBrowserMainWindowPrefetchHost\(\): MainWindowPrefetchBrowserHost/);
  assert.match(runtimeSource, /globalThis\.clearTimeout\(handle as ReturnType<typeof globalThis\.setTimeout>\);/);
  assert.match(runtimeSource, /setTimeout: \(callback, delayMs\) => globalThis\.setTimeout\(callback, delayMs\),/);
});

test('main window prefetch runtime owns the browser scheduling host wiring', () => {
  const host = createBrowserMainWindowPrefetchHost();
  assert.equal(typeof host.setTimeout, 'function');
  assert.equal(typeof host.clearTimeout, 'function');
});
