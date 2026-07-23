import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  clearTaskCardCompletionRefresh,
  scheduleTaskCardCompletionRefresh,
  type TaskCardCompletionRefreshTimerHost,
} from '../../../app/src/components/task-card/taskCardCompletionRefresh.runtime';

const repoRoot = process.cwd();

function createTimerHost() {
  const clearedHandles: unknown[] = [];
  const callbacks: Array<() => void> = [];
  const delays: number[] = [];
  const host: TaskCardCompletionRefreshTimerHost = {
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

test('task card completion refresh schedules delayed cache invalidation', () => {
  const timer = createTimerHost();
  let refreshCount = 0;

  const handle = scheduleTaskCardCompletionRefresh({
    delayMs: 260,
    refresh: () => {
      refreshCount += 1;
    },
    timerHost: timer.host,
  });

  assert.equal(handle, 'timer-1');
  assert.deepEqual(timer.delays, [260]);
  assert.equal(refreshCount, 0);

  timer.callbacks[0]?.();
  assert.equal(refreshCount, 1);
});

test('task card completion refresh clears scheduled handles through the host', () => {
  const timer = createTimerHost();

  clearTaskCardCompletionRefresh(timer.host, 'timer-1');

  assert.deepEqual(timer.clearedHandles, ['timer-1']);
});

test('task card controller delegates complete refresh delay to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-card/useTaskCardController.ts'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-card/taskCardCompletionRefresh.runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserTaskCardCompletionRefreshTimerHost,[\s\S]*scheduleTaskCardCompletionRefresh,[\s\S]*\} from '\.\/taskCardCompletionRefresh\.runtime';/,
  );
  assert.match(source, /scheduleTaskCardCompletionRefresh\(\{[\s\S]*delayMs: TASK_COMPLETE_ANIMATION_DELAY_MS,[\s\S]*refresh: \(\) => \{[\s\S]*invalidateTaskCaches\(\);[\s\S]*\},/);
  assert.match(
    source,
    /timerHost: createBrowserTaskCardCompletionRefreshTimerHost\(\),/,
  );
  assert.match(source, /abortToken: token,/);
  assert.doesNotMatch(source, /globalThis\.setTimeout/);

  assert.match(
    runtimeSource,
    /export function createBrowserTaskCardCompletionRefreshTimerHost\(\): TaskCardCompletionRefreshTimerHost \{/,
  );
  assert.match(
    runtimeSource,
    /globalThis\.clearTimeout\(handle as ReturnType<typeof globalThis\.setTimeout>\);/,
  );
  assert.match(
    runtimeSource,
    /setTimeout: \(callback, delayMs\) => globalThis\.setTimeout\(callback, delayMs\),/,
  );
});

test('swipeable task card actions delegate complete refresh scheduling and clearing', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-card/useSwipeableTaskCardActions.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*clearTaskCardCompletionRefresh,[\s\S]*createBrowserTaskCardCompletionRefreshTimerHost,[\s\S]*scheduleTaskCardCompletionRefresh,[\s\S]*\} from '\.\/taskCardCompletionRefresh\.runtime';/,
  );
  assert.match(source, /completeTimerRef\.current = scheduleTaskCardCompletionRefresh\(\{/);
  assert.match(
    source,
    /timerHost: createBrowserTaskCardCompletionRefreshTimerHost\(\),/,
  );
  assert.match(
    source,
    /clearTaskCardCompletionRefresh\(\s*createBrowserTaskCardCompletionRefreshTimerHost\(\),\s*completeTimerRef\.current,\s*\);/s,
  );
  assert.doesNotMatch(source, /completeTimerRef\.current = window\.setTimeout/);
  assert.doesNotMatch(source, /window\.clearTimeout\(completeTimerRef\.current\)/);
  assert.doesNotMatch(source, /globalThis\.setTimeout/);
  assert.doesNotMatch(source, /globalThis\.clearTimeout/);
});
