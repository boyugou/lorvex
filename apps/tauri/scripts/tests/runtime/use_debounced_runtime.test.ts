import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserDebounceTimerHost,
  scheduleDebouncedUpdate,
  type DebounceTimerHost,
} from '../../../app/src/lib/useDebounced.runtime';

test('useDebounced runtime schedules the trailing update through the injected host', () => {
  const callbacks: Array<() => void> = [];
  const clearedHandles: unknown[] = [];
  const delays: number[] = [];
  const host: DebounceTimerHost = {
    clearTimeout: (handle) => {
      clearedHandles.push(handle);
    },
    setTimeout: (callback, delayMs) => {
      callbacks.push(callback);
      delays.push(delayMs);
      return `debounce-timer-${callbacks.length}`;
    },
  };

  let updateCount = 0;
  const cleanup = scheduleDebouncedUpdate(host, () => {
    updateCount += 1;
  }, 300);

  assert.deepEqual(delays, [300]);
  assert.equal(updateCount, 0);

  callbacks[0]?.();
  assert.equal(updateCount, 1);

  cleanup();
  assert.deepEqual(clearedHandles, ['debounce-timer-1']);
});

test('useDebounced delegates browser timer wiring to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/useDebounced.ts'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/useDebounced.runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserDebounceTimerHost,[\s\S]*scheduleDebouncedUpdate,[\s\S]*\} from '\.\/useDebounced\.runtime';/s,
  );
  assert.match(source, /const debounceTimerHost = createBrowserDebounceTimerHost\(\);/);
  assert.match(
    source,
    /return scheduleDebouncedUpdate\([\s\S]*debounceTimerHost,[\s\S]*\(\) => setDebounced\(value\),[\s\S]*delay,[\s\S]*\);/s,
  );
  assert.doesNotMatch(source, /(?<!\.)\bsetTimeout\(/);
  assert.doesNotMatch(source, /(?<!\.)\bclearTimeout\(/);

  assert.match(runtimeSource, /export function createBrowserDebounceTimerHost\(\): DebounceTimerHost/);
  assert.match(runtimeSource, /globalThis\.clearTimeout\(handle as ReturnType<typeof globalThis\.setTimeout>\);/);
  assert.match(runtimeSource, /setTimeout: \(callback, delayMs\) => globalThis\.setTimeout\(callback, delayMs\),/);
});

test('useDebounced runtime owns the browser timer host wiring', () => {
  const host = createBrowserDebounceTimerHost();
  assert.equal(typeof host.setTimeout, 'function');
  assert.equal(typeof host.clearTimeout, 'function');
});
