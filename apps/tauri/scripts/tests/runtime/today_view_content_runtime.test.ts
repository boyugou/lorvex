import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserTodayViewRefreshDelayTimerHost,
  mergeCanonicalOverdueSection,
  TODAY_VIEW_PULL_TO_REFRESH_FEEDBACK_DELAY_MS,
  waitForTodayViewPullToRefreshFeedback,
  type TodayViewRefreshDelayTimerHost,
} from '../../../app/src/components/today-view/TodayViewContent.runtime';

test('today view refresh feedback delay waits through the injected timer host', async () => {
  const callbacks: Array<() => void> = [];
  const delays: number[] = [];
  const host: TodayViewRefreshDelayTimerHost = {
    setTimeout: (callback, delayMs) => {
      callbacks.push(callback);
      delays.push(delayMs);
      return 'today-refresh-delay';
    },
  };

  let resolved = false;
  const pending = waitForTodayViewPullToRefreshFeedback({ timerHost: host }).then(() => {
    resolved = true;
  });

  assert.deepEqual(delays, [TODAY_VIEW_PULL_TO_REFRESH_FEEDBACK_DELAY_MS]);
  assert.equal(resolved, false);

  callbacks[0]?.();
  await pending;
  assert.equal(resolved, true);
});

test('today view content delegates refresh delay timer wiring to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/today-view/TodayViewContent.tsx'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/today-view/TodayViewContent.runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserTodayViewRefreshDelayTimerHost,[\s\S]*waitForTodayViewPullToRefreshFeedback,[\s\S]*\} from '\.\/TodayViewContent\.runtime';/s,
  );
  assert.match(source, /const todayViewRefreshDelayTimerHost = createBrowserTodayViewRefreshDelayTimerHost\(\);/);
  assert.match(
    source,
    /await waitForTodayViewPullToRefreshFeedback\(\{[\s\S]*timerHost: todayViewRefreshDelayTimerHost,[\s\S]*\}\);/s,
  );
  assert.doesNotMatch(source, /(?<!\.)\bsetTimeout\(/);

  assert.match(runtimeSource, /export function createBrowserTodayViewRefreshDelayTimerHost\(\): TodayViewRefreshDelayTimerHost/);
  assert.match(runtimeSource, /setTimeout: \(callback, delayMs\) => globalThis\.setTimeout\(callback, delayMs\),/);
});

test('today view runtime owns the browser refresh delay timer host wiring', () => {
  const host = createBrowserTodayViewRefreshDelayTimerHost();
  assert.equal(typeof host.setTimeout, 'function');
});

test('today view inserts a canonical overdue section when AI layout omits it', () => {
  const sections = [{ type: 'priority' as const }, { type: 'habits' as const }];

  assert.deepEqual(
    mergeCanonicalOverdueSection(sections, 3),
    [{ type: 'overdue_alert' }, ...sections],
  );
  assert.deepEqual(mergeCanonicalOverdueSection(sections, 0), sections);
  assert.deepEqual(
    mergeCanonicalOverdueSection([{ type: 'overdue_alert' as const, limit: 2 }, ...sections], 3),
    [{ type: 'overdue_alert', limit: 2 }, ...sections],
  );
});

test('today view loads overdue tasks independently of the optional overdue dashboard section', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/today-view/useTodayViewController.ts'),
    'utf8',
  );

  assert.match(source, /const shouldLoadOverdueTasks = overdueCount > 0;/);
  assert.match(source, /enabled: shouldLoadOverdueTasks,/);
  assert.match(source, /refetchInterval: shouldLoadOverdueTasks \? REFETCH_INTERVAL : false,/);
  assert.doesNotMatch(source, /enabled:\s*hasOverdueAlertSection && overdueCount > 0/);
  assert.doesNotMatch(source, /hasOverdueAlertSection && overdueCount > 0 && isOverdueTasks/);
});
