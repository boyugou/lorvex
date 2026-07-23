import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import type { RecentUndoToken } from '../../../app/src/lib/undoTokenStore';
import {
  createBrowserRecentUndoTokenIntervalHost,
  installRecentUndoTokenSnapshotRuntime,
  type RecentUndoTokenIntervalHost,
} from '../../../app/src/components/command-palette/controller/recentUndoTokens.runtime';

const repoRoot = process.cwd();

function createTimerHost() {
  const callbacks: Array<() => void> = [];
  const clearedHandles: unknown[] = [];
  const delays: number[] = [];
  const host: RecentUndoTokenIntervalHost = {
    clearInterval: (handle) => {
      clearedHandles.push(handle);
    },
    setInterval: (callback, delayMs) => {
      callbacks.push(callback);
      delays.push(delayMs);
      return `interval-${callbacks.length}`;
    },
  };

  return {
    callbacks,
    clearedHandles,
    delays,
    host,
  };
}

function token(label: string, expiresAt: number): RecentUndoToken {
  return {
    expiresAt,
    label,
    recordedAt: expiresAt - 1000,
    token: `token-${label}`,
  };
}

test('command palette recent undo runtime snapshots immediately, ticks, and clears interval', () => {
  const timer = createTimerHost();
  const published: RecentUndoToken[][] = [];
  const snapshots = [
    [token('first', 1000)],
    [token('second', 2000)],
  ];

  const cleanup = installRecentUndoTokenSnapshotRuntime({
    intervalHost: timer.host,
    intervalMs: 500,
    publishTokens: (tokens) => {
      published.push(tokens);
    },
    snapshotTokens: () => snapshots.shift() ?? [],
  });

  assert.deepEqual(timer.delays, [500]);
  assert.equal(timer.callbacks.length, 1);
  assert.deepEqual(published.map((items) => items.map((item) => item.label)), [['first']]);

  timer.callbacks[0]?.();
  cleanup();

  assert.deepEqual(published.map((items) => items.map((item) => item.label)), [
    ['first'],
    ['second'],
  ]);
  assert.deepEqual(timer.clearedHandles, ['interval-1']);
});

test('command palette recent undo runtime snapshots once without a browser interval host', () => {
  const published: RecentUndoToken[][] = [];

  const cleanup = installRecentUndoTokenSnapshotRuntime({
    intervalHost: null,
    intervalMs: 500,
    publishTokens: (tokens) => {
      published.push(tokens);
    },
    snapshotTokens: () => [token('headless', 3000)],
  });
  cleanup();

  assert.deepEqual(published.map((items) => items.map((item) => item.label)), [['headless']]);
});

test('command palette results delegates recent undo polling to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/command-palette/controller/results.ts'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/command-palette/controller/recentUndoTokens.runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserRecentUndoTokenIntervalHost,[\s\S]*installRecentUndoTokenSnapshotRuntime,[\s\S]*\} from '\.\/recentUndoTokens\.runtime';/s,
  );
  assert.match(source, /const recentUndoTokenIntervalHost = createBrowserRecentUndoTokenIntervalHost\(\);/);
  assert.match(
    source,
    /installRecentUndoTokenSnapshotRuntime\(\{[\s\S]*intervalHost: recentUndoTokenIntervalHost,[\s\S]*intervalMs: 500,[\s\S]*publishTokens: setTokens,[\s\S]*snapshotTokens: listRecentUndoTokens,/,
  );
  assert.doesNotMatch(source, /globalThis\.(setInterval|clearInterval)/);
  assert.doesNotMatch(source, /const id = window\.setInterval/);
  assert.doesNotMatch(source, /window\.clearInterval\(id\)/);

  assert.match(runtimeSource, /export function createBrowserRecentUndoTokenIntervalHost\(\): RecentUndoTokenIntervalHost \| null/);
  assert.match(runtimeSource, /globalThis\.clearInterval\(handle as ReturnType<typeof globalThis\.setInterval>\);/);
  assert.match(runtimeSource, /setInterval: \(callback, delayMs\) => globalThis\.setInterval\(callback, delayMs\),/);
});

test('command palette recent undo runtime owns the browser interval host wiring', () => {
  const host = createBrowserRecentUndoTokenIntervalHost();
  if (host === null) {
    assert.equal(typeof window, 'undefined');
    return;
  }
  assert.equal(typeof host.setInterval, 'function');
  assert.equal(typeof host.clearInterval, 'function');
});
