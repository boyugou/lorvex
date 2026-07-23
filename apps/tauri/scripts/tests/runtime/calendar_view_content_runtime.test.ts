import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  installCalendarViewShortcutRuntime,
  resolveCalendarViewShortcutAction,
  runCalendarViewShortcutAction,
  type CalendarViewShortcutAction,
} from '../../../app/src/components/calendar/CalendarViewContent.runtime';
import type { CalendarViewMode } from '../../../app/src/components/calendar/viewModePreference.logic';

const plainTarget = new EventTarget();
const ignoredTarget = new EventTarget();

function shouldIgnore(target: EventTarget | null): boolean {
  return target === ignoredTarget;
}

test('calendar view shortcut resolver maps navigation and view keys', () => {
  assert.equal(
    resolveCalendarViewShortcutAction({ key: 'ArrowLeft', target: plainTarget }, shouldIgnore),
    'previous',
  );
  assert.equal(
    resolveCalendarViewShortcutAction({ key: 'ArrowRight', target: plainTarget }, shouldIgnore),
    'next',
  );
  assert.equal(
    resolveCalendarViewShortcutAction({ key: 't', target: plainTarget }, shouldIgnore),
    'today',
  );
  assert.equal(
    resolveCalendarViewShortcutAction({ key: 'm', target: plainTarget }, shouldIgnore),
    'toggleViewMode',
  );
});

test('calendar view shortcut resolver ignores edited targets and modified shortcuts', () => {
  assert.equal(
    resolveCalendarViewShortcutAction({ key: 'ArrowLeft', target: ignoredTarget }, shouldIgnore),
    null,
  );
  assert.equal(
    resolveCalendarViewShortcutAction({ key: 'ArrowLeft', target: plainTarget, shiftKey: true }, shouldIgnore),
    null,
  );
  assert.equal(
    resolveCalendarViewShortcutAction({ key: 't', target: plainTarget, metaKey: true }, shouldIgnore),
    null,
  );
  assert.equal(
    resolveCalendarViewShortcutAction({ key: 'm', target: plainTarget, ctrlKey: true }, shouldIgnore),
    null,
  );
  assert.equal(
    resolveCalendarViewShortcutAction({ key: 'm', target: plainTarget, altKey: true }, shouldIgnore),
    null,
  );
  assert.equal(
    resolveCalendarViewShortcutAction({ key: 'x', target: plainTarget }, shouldIgnore),
    null,
  );
});

test('calendar view shortcut runner dispatches month and week actions', () => {
  const calls: string[] = [];
  const makeDeps = (viewMode: CalendarViewMode) => ({
    viewMode,
    goToPrevMonth: () => calls.push('prev-month'),
    goToPrevWeek: () => calls.push('prev-week'),
    goToNextMonth: () => calls.push('next-month'),
    goToNextWeek: () => calls.push('next-week'),
    goToToday: () => calls.push('today'),
    switchViewMode: (mode: CalendarViewMode) => calls.push(`switch:${mode}`),
  });

  const actions: CalendarViewShortcutAction[] = ['previous', 'next', 'today', 'toggleViewMode'];
  for (const action of actions) {
    runCalendarViewShortcutAction(action, makeDeps('month'));
  }
  for (const action of actions) {
    runCalendarViewShortcutAction(action, makeDeps('week'));
  }

  assert.deepEqual(calls, [
    'prev-month',
    'next-month',
    'today',
    'switch:week',
    'prev-week',
    'next-week',
    'today',
    'switch:month',
  ]);
});

test('calendar view shortcut runtime handles keys, prevents defaults, and unregisters cleanup', () => {
  let listener: EventListener | undefined;
  const calls: string[] = [];

  const cleanup = installCalendarViewShortcutRuntime({
    windowTarget: {
      addEventListener: (type, nextListener) => {
        assert.equal(type, 'keydown');
        listener = nextListener as EventListener;
      },
      removeEventListener: (type, nextListener) => {
        assert.equal(type, 'keydown');
        if (listener === nextListener) {
          listener = undefined;
          calls.push('cleanup');
        }
      },
    },
    viewMode: 'month',
    shouldIgnoreShortcutTarget: shouldIgnore,
    goToPrevMonth: () => calls.push('prev-month'),
    goToPrevWeek: () => calls.push('prev-week'),
    goToNextMonth: () => calls.push('next-month'),
    goToNextWeek: () => calls.push('next-week'),
    goToToday: () => calls.push('today'),
    switchViewMode: (mode) => calls.push(`switch:${mode}`),
  });

  listener?.({
    key: 'ArrowLeft',
    target: plainTarget,
    preventDefault: () => calls.push('prevent-left'),
  } as KeyboardEvent);
  listener?.({
    key: 'ArrowRight',
    target: ignoredTarget,
    preventDefault: () => calls.push('prevent-ignored'),
  } as KeyboardEvent);
  listener?.({
    key: 'm',
    target: plainTarget,
    preventDefault: () => calls.push('prevent-m'),
  } as KeyboardEvent);
  cleanup();

  assert.deepEqual(calls, [
    'prevent-left',
    'prev-month',
    'prevent-m',
    'switch:week',
    'cleanup',
  ]);
  assert.equal(listener, undefined);
});

test('calendar view shortcut runtime is a no-op without a window target', () => {
  const calls: string[] = [];

  const cleanup = installCalendarViewShortcutRuntime({
    windowTarget: undefined,
    viewMode: 'month',
    shouldIgnoreShortcutTarget: shouldIgnore,
    goToPrevMonth: () => calls.push('prev-month'),
    goToPrevWeek: () => calls.push('prev-week'),
    goToNextMonth: () => calls.push('next-month'),
    goToNextWeek: () => calls.push('next-week'),
    goToToday: () => calls.push('today'),
    switchViewMode: (mode) => calls.push(`switch:${mode}`),
  });

  cleanup();

  assert.deepEqual(calls, []);
});

test('calendar view component delegates global shortcuts to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/calendar/CalendarViewContent.tsx'),
    'utf8',
  );

  assert.match(
    source,
    /import \{ installCalendarViewShortcutRuntime \} from '\.\/CalendarViewContent\.runtime';/,
  );
  assert.match(source, /return installCalendarViewShortcutRuntime\(\{/);
  assert.match(source, /windowTarget: window,/);
  assert.match(source, /shouldIgnoreShortcutTarget: shouldIgnoreShortcut,/);
  assert.match(source, /switchViewMode,/);
  assert.doesNotMatch(source, /const onKeyDown = \(e: KeyboardEvent\) => \{/);
  assert.doesNotMatch(source, /window\.addEventListener\('keydown', onKeyDown\)/);
});
