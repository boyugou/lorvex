import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserSqliteRetryTimerHost,
  waitForBusyRetryDelay,
  type SqliteRetryTimerHost,
} from '../../../app/src/lib/recovery/sqliteRetry.runtime';

const repoRoot = process.cwd();

function createTimerHost() {
  const callbacks: Array<() => void> = [];
  const delays: number[] = [];
  const host: SqliteRetryTimerHost = {
    setTimeout: (callback, delayMs) => {
      callbacks.push(callback);
      delays.push(delayMs);
      return `timer-${callbacks.length}` as ReturnType<typeof globalThis.setTimeout>;
    },
  };

  return {
    callbacks,
    delays,
    host,
  };
}

test('waitForBusyRetryDelay resolves immediately for non-positive delays', async () => {
  const timer = createTimerHost();

  await waitForBusyRetryDelay(0, timer.host);
  await waitForBusyRetryDelay(-10, timer.host);

  assert.deepEqual(timer.delays, []);
});

test('waitForBusyRetryDelay schedules the requested delay and resolves when the host fires', async () => {
  const timer = createTimerHost();
  let settled = false;

  const wait = waitForBusyRetryDelay(125, timer.host).then(() => {
    settled = true;
  });

  assert.deepEqual(timer.delays, [125]);
  assert.equal(settled, false);

  timer.callbacks[0]?.();
  await wait;

  assert.equal(settled, true);
});

test('sqlite busy retry delegates delay scheduling through the browser host seam', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/recovery/sqliteRetry.ts'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/recovery/sqliteRetry.runtime.ts'),
    'utf8',
  );

  assert.ok(
    source.includes('createBrowserSqliteRetryTimerHost,'),
  );
  assert.ok(source.includes('const sqliteRetryTimerHost = createBrowserSqliteRetryTimerHost();'));
  assert.ok(source.includes('await waitForBusyRetryDelay(delayMs, sqliteRetryTimerHost, signal);'));
  assert.ok(!source.includes('globalThis.setTimeout'));
  assert.ok(
    runtimeSource.includes('export function createBrowserSqliteRetryTimerHost(): SqliteRetryTimerHost'),
  );
  assert.ok(runtimeSource.includes('setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),'));
  assert.ok(!source.includes('window.setTimeout('));
});

test('sqlite busy retry runtime owns the browser timer host wiring', () => {
  const host = createBrowserSqliteRetryTimerHost();
  assert.equal(typeof host.setTimeout, 'function');
});
