import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  clearTaskDetailRelationSearchTimer,
  createBrowserTaskDetailRelationSearchTimerHost,
  createTaskDetailRelationSearchTimerState,
  scheduleTaskDetailRelationSearch,
  TASK_DETAIL_RELATION_SEARCH_DEBOUNCE_MS,
  type TaskDetailRelationSearchTimerHost,
} from '../../../app/src/components/task-detail/content/useTaskDetailRelationSearch.runtime';

function createSearchTimerHost() {
  const callbacks: Array<() => void> = [];
  const clearedHandles: unknown[] = [];
  const delays: number[] = [];
  const host: TaskDetailRelationSearchTimerHost = {
    clearTimeout: (handle) => {
      clearedHandles.push(handle);
    },
    setTimeout: (callback, delayMs) => {
      callbacks.push(callback);
      delays.push(delayMs);
      return `relation-search-timer-${callbacks.length}`;
    },
  };

  return {
    callbacks,
    clearedHandles,
    delays,
    host,
  };
}

test('task detail relation search scheduling replaces stale timers and runs the search', () => {
  const timer = createSearchTimerHost();
  const state = createTaskDetailRelationSearchTimerState();
  let searchCount = 0;

  scheduleTaskDetailRelationSearch({
    state,
    timerHost: timer.host,
    runSearch: () => {
      searchCount += 1;
    },
  });
  assert.equal(state.timer, 'relation-search-timer-1');
  assert.deepEqual(timer.delays, [TASK_DETAIL_RELATION_SEARCH_DEBOUNCE_MS]);

  scheduleTaskDetailRelationSearch({
    state,
    timerHost: timer.host,
    runSearch: () => {
      searchCount += 1;
    },
  });
  assert.deepEqual(timer.clearedHandles, ['relation-search-timer-1']);
  assert.equal(state.timer, 'relation-search-timer-2');

  timer.callbacks[1]?.();
  assert.equal(searchCount, 1);
  assert.equal(state.timer, null);
});

test('task detail relation search cleanup clears the pending debounce timer', () => {
  const timer = createSearchTimerHost();
  const state = createTaskDetailRelationSearchTimerState();

  scheduleTaskDetailRelationSearch({
    state,
    timerHost: timer.host,
    runSearch: () => {},
  });
  clearTaskDetailRelationSearchTimer(state, timer.host.clearTimeout);

  assert.deepEqual(timer.clearedHandles, ['relation-search-timer-1']);
  assert.equal(state.timer, null);
});

test('task detail relation search hook delegates timer wiring to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/task-detail/content/useTaskDetailRelationSearch.ts'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/task-detail/content/useTaskDetailRelationSearch.runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*clearTaskDetailRelationSearchTimer,[\s\S]*createBrowserTaskDetailRelationSearchTimerHost,[\s\S]*createTaskDetailRelationSearchTimerState,[\s\S]*scheduleTaskDetailRelationSearch,[\s\S]*type TaskDetailRelationSearchTimerState,[\s\S]*\} from '\.\/useTaskDetailRelationSearch\.runtime';/s,
  );
  assert.match(source, /const taskDetailRelationSearchTimerHost = createBrowserTaskDetailRelationSearchTimerHost\(\);/);
  assert.match(
    source,
    /scheduleTaskDetailRelationSearch\(\{[\s\S]*state: debounceRef\.current,[\s\S]*timerHost: taskDetailRelationSearchTimerHost,[\s\S]*runSearch: \(\) => \{[\s\S]*searchTasks\(query, false\)[\s\S]*\},[\s\S]*\}\);/s,
  );
  assert.match(
    source,
    /clearTaskDetailRelationSearchTimer\([\s\S]*debounceRef\.current,[\s\S]*taskDetailRelationSearchTimerHost\.clearTimeout,[\s\S]*\);/s,
  );
  assert.doesNotMatch(source, /(?<!\.)\bsetTimeout\(/);
  assert.doesNotMatch(source, /(?<!\.)\bclearTimeout\(/);

  assert.match(runtimeSource, /export function createBrowserTaskDetailRelationSearchTimerHost\(\): TaskDetailRelationSearchTimerHost/);
  assert.match(runtimeSource, /globalThis\.clearTimeout\(handle as ReturnType<typeof globalThis\.setTimeout>\);/);
  assert.match(runtimeSource, /setTimeout: \(callback, delayMs\) => globalThis\.setTimeout\(callback, delayMs\),/);
});

test('task detail relation search runtime owns the browser timer host wiring', () => {
  const host = createBrowserTaskDetailRelationSearchTimerHost();
  assert.equal(typeof host.setTimeout, 'function');
  assert.equal(typeof host.clearTimeout, 'function');
});
