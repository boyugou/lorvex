import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  buildUiViewStateSnapshot,
} from '../../../app/src/app-shell/main-window/useUiViewStatePersistence';
import {
  createBrowserUiViewStatePersistenceTimerHost,
  installUiViewStatePersistenceRuntime,
  type UiViewStatePersistenceTimerHost,
} from '../../../app/src/app-shell/main-window/useUiViewStatePersistence.runtime';

const repoRoot = process.cwd();

function createTimerHost() {
  const callbacks: Array<() => void> = [];
  const clearedHandles: unknown[] = [];
  const delays: number[] = [];
  const host: UiViewStatePersistenceTimerHost = {
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

test('ui view state persistence runtime schedules one delayed flush and clears it', () => {
  const timer = createTimerHost();
  let flushCount = 0;

  const cleanup = installUiViewStatePersistenceRuntime({
    delayMs: 500,
    flush: () => {
      flushCount += 1;
    },
    timerHost: timer.host,
  });

  assert.deepEqual(timer.delays, [500]);
  timer.callbacks[0]?.();
  cleanup();

  assert.equal(flushCount, 1);
  assert.deepEqual(timer.clearedHandles, ['timer-1']);
});

test('ui view state snapshot projects list and search views into the MCP contract shape', () => {
  const now = new Date('2026-04-23T19:15:00.000Z');

  assert.deepEqual(
    buildUiViewStateSnapshot({
      view: { type: 'list', listId: 'list-123' },
      selectedTaskId: 'task-1',
      focusModeActive: true,
      focusModeTaskId: 'focus-1',
    }, now),
    {
      last_updated_at: '2026-04-23T19:15:00.000Z',
      active_view: 'list:list-123',
      selected_task_id: 'task-1',
      search_query: null,
      list_filter_id: 'list-123',
      tag_filters: [],
      priority_filter: null,
      focus_mode_active: true,
      focus_mode_task_id: 'focus-1',
    },
  );

  assert.deepEqual(
    buildUiViewStateSnapshot({
      view: { type: 'all_tasks', initialSearch: '  inbox zero  ' },
      selectedTaskId: null,
      focusModeActive: false,
      focusModeTaskId: 'stale-focus-id',
    }, now),
    {
      last_updated_at: '2026-04-23T19:15:00.000Z',
      active_view: 'all_tasks',
      selected_task_id: null,
      search_query: 'inbox zero',
      list_filter_id: null,
      tag_filters: [],
      priority_filter: null,
      focus_mode_active: false,
      focus_mode_task_id: null,
    },
  );
});

test('ui view state snapshot fails closed for blank all-tasks search input', () => {
  const snapshot = buildUiViewStateSnapshot({
    view: { type: 'all_tasks', initialSearch: '   ' },
    selectedTaskId: null,
    focusModeActive: false,
    focusModeTaskId: null,
  }, new Date('2026-04-23T19:15:00.000Z'));

  assert.equal(snapshot.active_view, 'all_tasks');
  assert.equal(snapshot.search_query, null);
  assert.equal(snapshot.list_filter_id, null);
});

test('ui view state persistence hook delegates debounce timers through the browser host seam', () => {
  const hookSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/app-shell/main-window/useUiViewStatePersistence.ts'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/app-shell/main-window/useUiViewStatePersistence.runtime.ts'),
    'utf8',
  );

  assert.ok(
    hookSource.includes(
      'createBrowserUiViewStatePersistenceTimerHost,',
    ),
  );
  assert.ok(hookSource.includes('const uiViewStatePersistenceTimerHost = createBrowserUiViewStatePersistenceTimerHost();'));
  assert.ok(hookSource.includes('return installUiViewStatePersistenceRuntime({'));
  assert.ok(hookSource.includes('delayMs: DEBOUNCE_MS,'));
  assert.ok(hookSource.includes('timerHost: uiViewStatePersistenceTimerHost,'));
  assert.ok(!hookSource.includes('globalThis.setTimeout'));
  assert.ok(!hookSource.includes('globalThis.clearTimeout'));
  assert.ok(!hookSource.includes('window.setTimeout('));
  assert.ok(!hookSource.includes('window.clearTimeout('));

  assert.ok(runtimeSource.includes('export function createBrowserUiViewStatePersistenceTimerHost(): UiViewStatePersistenceTimerHost'));
  assert.ok(
    runtimeSource.includes(
      'globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);',
    ),
  );
  assert.ok(
    runtimeSource.includes('setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),'),
  );
  assert.ok(runtimeSource.includes('export function installUiViewStatePersistenceRuntime('));
  assert.ok(runtimeSource.includes('const handle = options.timerHost.setTimeout(() => {'));
  assert.ok(runtimeSource.includes('options.timerHost.clearTimeout(handle);'));
});

test('ui view state persistence runtime owns the browser timer host wiring', () => {
  const host = createBrowserUiViewStatePersistenceTimerHost();
  assert.equal(typeof host.setTimeout, 'function');
  assert.equal(typeof host.clearTimeout, 'function');
});
