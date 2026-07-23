import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  clearTaskListKeyboardHintDismiss,
  createBrowserTaskListKeyboardFocusHost,
  createBrowserTaskListKeyboardHost,
  createBrowserTaskListKeyboardHintTimerHost,
  installTaskListKeyboardRuntime,
  isTaskListKeyboardDocumentBodyTarget,
  scheduleTaskListKeyboardHintDismiss,
  syncTaskListKeyboardFocus,
  TASK_LIST_KEYBOARD_HINT_DISMISS_DELAY_MS,
  type TaskListKeyboardFocusHost,
  type TaskListKeyboardHintTimerHost,
  type TaskListKeyboardHintTimerState,
  type TaskListKeyboardRuntimeDeps,
} from '../../../app/src/lib/tasks/useTaskListKeyboard.runtime';

function createRuntimeDeps(
  overrides: Partial<TaskListKeyboardRuntimeDeps> = {},
): TaskListKeyboardRuntimeDeps & {
  calls: string[];
  readonly installedListener: ((event: KeyboardEvent) => void) | undefined;
} {
  const calls: string[] = [];
  let listener: ((event: KeyboardEvent) => void) | undefined;

  return {
    calls,
    addWindowKeydownListener: (nextListener) => {
      listener = nextListener;
      calls.push('install');
      return () => {
        listener = undefined;
        calls.push('cleanup');
      };
    },
    disabled: false,
    onKeyDown: (event) => {
      calls.push(`keydown:${event.key}`);
    },
    ...overrides,
    get installedListener() {
      return listener;
    },
  };
}

test('task list keyboard runtime installs a keydown listener, delegates events, and cleans up', () => {
  const deps = createRuntimeDeps();

  const cleanup = installTaskListKeyboardRuntime(deps);
  deps.installedListener?.({ key: 'j' } as KeyboardEvent);
  cleanup();

  assert.deepEqual(deps.calls, ['install', 'keydown:j', 'cleanup']);
  assert.equal(deps.installedListener, undefined);
});

test('task list keyboard runtime is inert when disabled or when no window host exists', () => {
  const disabledDeps = createRuntimeDeps({ disabled: true });
  installTaskListKeyboardRuntime(disabledDeps)();

  const headlessDeps = createRuntimeDeps({ addWindowKeydownListener: null });
  installTaskListKeyboardRuntime(headlessDeps)();

  assert.deepEqual(disabledDeps.calls, []);
  assert.deepEqual(headlessDeps.calls, []);
});

function createHintTimerHost() {
  const callbacks: Array<() => void> = [];
  const clearedHandles: unknown[] = [];
  const delays: number[] = [];
  const host: TaskListKeyboardHintTimerHost = {
    clearTimeout: (handle) => {
      clearedHandles.push(handle);
    },
    setTimeout: (callback, delayMs) => {
      callbacks.push(callback);
      delays.push(delayMs);
      return `hint-timer-${callbacks.length}`;
    },
  };

  return {
    callbacks,
    clearedHandles,
    delays,
    host,
  };
}

test('task list keyboard hint dismiss scheduling replaces stale timers and runs the dismiss callback', () => {
  const timer = createHintTimerHost();
  const state: TaskListKeyboardHintTimerState = { handle: null };
  let dismissCount = 0;

  scheduleTaskListKeyboardHintDismiss({
    state,
    timerHost: timer.host,
    onDismiss: () => {
      dismissCount += 1;
    },
  });
  assert.equal(state.handle, 'hint-timer-1');
  assert.deepEqual(timer.delays, [TASK_LIST_KEYBOARD_HINT_DISMISS_DELAY_MS]);

  scheduleTaskListKeyboardHintDismiss({
    state,
    timerHost: timer.host,
    onDismiss: () => {
      dismissCount += 1;
    },
  });
  assert.deepEqual(timer.clearedHandles, ['hint-timer-1']);
  assert.equal(state.handle, 'hint-timer-2');

  timer.callbacks[1]?.();
  assert.equal(dismissCount, 1);
  assert.equal(state.handle, null);
});

test('task list keyboard hint dismiss cleanup clears the pending timer', () => {
  const clearedHandles: unknown[] = [];
  const state: TaskListKeyboardHintTimerState = { handle: 'hint-timer' };

  clearTaskListKeyboardHintDismiss(state, (handle) => {
    clearedHandles.push(handle);
  });

  assert.deepEqual(clearedHandles, ['hint-timer']);
  assert.equal(state.handle, null);
});

test('task list keyboard hook delegates global listener wiring to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/tasks/useTaskListKeyboard.ts'),
    'utf8',
  );
  const keydownSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/tasks/useTaskListKeyboard.keydown.ts'),
    'utf8',
  );

  assert.match(source, /import \{ createTaskListKeyboardKeydownHandler \} from '\.\/useTaskListKeyboard\.keydown';/);
  assert.match(
    source,
    /import \{[\s\S]*clearTaskListKeyboardHintDismiss,[\s\S]*createBrowserTaskListKeyboardFocusHost,[\s\S]*createBrowserTaskListKeyboardHost,[\s\S]*createBrowserTaskListKeyboardHintTimerHost,[\s\S]*installTaskListKeyboardRuntime,[\s\S]*scheduleTaskListKeyboardHintDismiss,[\s\S]*syncTaskListKeyboardFocus,[\s\S]*type TaskListKeyboardHintTimerState,[\s\S]*\} from '\.\/useTaskListKeyboard\.runtime';/s,
  );
  assert.match(source, /const taskListKeyboardFocusHost = createBrowserTaskListKeyboardFocusHost\(\);/);
  assert.match(source, /const taskListKeyboardHost = createBrowserTaskListKeyboardHost\(\);/);
  assert.match(source, /const taskListKeyboardHintTimerHost = createBrowserTaskListKeyboardHintTimerHost\(\);/);
  assert.match(
    source,
    /scheduleTaskListKeyboardHintDismiss\(\{[\s\S]*state: hintTimerRef\.current,[\s\S]*timerHost: taskListKeyboardHintTimerHost,[\s\S]*onDismiss: \(\) => setShowHints\(false\),[\s\S]*\}\);/s,
  );
  assert.match(
    source,
    /clearTaskListKeyboardHintDismiss\([\s\S]*hintTimerRef\.current,[\s\S]*taskListKeyboardHintTimerHost\.clearTimeout,[\s\S]*\);/s,
  );
  assert.match(
    source,
    /return installTaskListKeyboardRuntime\(\{[\s\S]*disabled,[\s\S]*onKeyDown,[\s\S]*\.\.\.taskListKeyboardHost,[\s\S]*\}\);/,
  );
  assert.doesNotMatch(source, /window\.addEventListener\('keydown'/);
  assert.doesNotMatch(source, /window\.removeEventListener\('keydown'/);
  assert.match(
    source,
    /syncTaskListKeyboardFocus\(\{[\s\S]*focusedId,[\s\S]*focusHost: taskListKeyboardFocusHost,[\s\S]*\}\);/,
  );
  assert.doesNotMatch(source, /document\.querySelector/);
  assert.doesNotMatch(source, /document\.activeElement/);
  assert.match(
    keydownSource,
    /import \{[\s\S]*isTaskListKeyboardDocumentBodyTarget,[\s\S]*type TaskListKeyboardHost,[\s\S]*\} from '\.\/useTaskListKeyboard\.runtime';/s,
  );
  assert.match(keydownSource, /isTaskListKeyboardDocumentBodyTarget\(event\.target, taskListKeyboardHost\)/);
  assert.doesNotMatch(source, /document\.body/);
  assert.doesNotMatch(
    source,
    /return \(\) => window\.removeEventListener\('keydown', onKeyDown\)/,
  );
  assert.doesNotMatch(source, /(?<!\.)\bsetTimeout\(/);
  assert.doesNotMatch(source, /(?<!\.)\bclearTimeout\(/);
});

test('task list keyboard runtime owns the browser hint timer host wiring', () => {
  const host = createBrowserTaskListKeyboardHintTimerHost();
  assert.equal(typeof host.setTimeout, 'function');
  assert.equal(typeof host.clearTimeout, 'function');
});

test('task list keyboard runtime owns the browser keydown host wiring', () => {
  const listeners = new Map<string, (event: KeyboardEvent) => void>();
  const originalWindow = globalThis.window;

  Object.defineProperty(globalThis, 'window', {
    configurable: true,
    value: {
      addEventListener: (type: string, listener: (event: KeyboardEvent) => void) => {
        listeners.set(type, listener);
      },
      removeEventListener: (type: string, listener: (event: KeyboardEvent) => void) => {
        if (listeners.get(type) === listener) listeners.delete(type);
      },
    },
  });

  try {
    const host = createBrowserTaskListKeyboardHost();
    let calls = 0;
    const remove = host.addWindowKeydownListener?.(() => {
      calls += 1;
    });

    listeners.get('keydown')?.({ key: 'j' } as KeyboardEvent);
    assert.equal(calls, 1);
    remove?.();
    assert.equal(listeners.size, 0);
  } finally {
    Object.defineProperty(globalThis, 'window', { configurable: true, value: originalWindow });
  }
});

test('task list keyboard body target guard reads body through the injected host', () => {
  const body = {};
  const host = {
    getDocumentBody: () => body as EventTarget,
  };

  assert.equal(isTaskListKeyboardDocumentBodyTarget(body as EventTarget, host), true);
  assert.equal(isTaskListKeyboardDocumentBodyTarget({} as EventTarget, host), false);
  assert.equal(isTaskListKeyboardDocumentBodyTarget(body as EventTarget, {
    getDocumentBody: () => null,
  }), false);
});

test('task list keyboard focus runtime scrolls and focuses through the injected host', () => {
  const calls: string[] = [];
  const focusable = {
    focus: (options?: FocusOptions) => {
      calls.push(`focus:${String(options?.preventScroll)}`);
    },
  };
  const activeOutside = {};
  const taskElement = {
    isConnected: true,
    contains: (element: unknown) => element === focusable,
    querySelector: (selector: string) => {
      calls.push(`query:${selector}`);
      return focusable;
    },
    scrollIntoView: (options?: ScrollIntoViewOptions) => {
      calls.push(`scroll:${options?.block}:${options?.behavior}`);
    },
  };
  const focusHost: TaskListKeyboardFocusHost = {
    findTaskElement: (taskId) => {
      calls.push(`find:${taskId}`);
      return taskElement;
    },
    getActiveElement: () => activeOutside as Element,
  };

  syncTaskListKeyboardFocus({
    focusedId: 'task-1',
    focusHost,
  });

  assert.deepEqual(calls, [
    'find:task-1',
    'scroll:nearest:instant',
    'query:button[aria-label], [role="button"][tabindex], button:not([disabled])',
    'focus:true',
  ]);
});

test('task list keyboard focus runtime preserves active focus inside the task row', () => {
  let focusCalls = 0;
  const focusable = {
    focus: () => {
      focusCalls += 1;
    },
  };
  const activeInside = {};
  const taskElement = {
    isConnected: true,
    contains: (element: unknown) => element === activeInside,
    querySelector: () => focusable,
    scrollIntoView: () => {},
  };
  const focusHost: TaskListKeyboardFocusHost = {
    findTaskElement: () => taskElement,
    getActiveElement: () => activeInside as Element,
  };

  syncTaskListKeyboardFocus({
    focusedId: 'task-1',
    focusHost,
  });

  assert.equal(focusCalls, 0);
});

test('task list keyboard focus host escapes task ids before querying data attributes', () => {
  const selectors: string[] = [];
  const originalDocument = globalThis.document;

  Object.defineProperty(globalThis, 'document', {
    configurable: true,
    value: {
      activeElement: null,
      querySelector: (selector: string) => {
        selectors.push(selector);
        return null;
      },
    },
  });

  try {
    const focusHost = createBrowserTaskListKeyboardFocusHost();
    focusHost.findTaskElement('task"\\id');
  } finally {
    Object.defineProperty(globalThis, 'document', { configurable: true, value: originalDocument });
  }

  assert.deepEqual(selectors, ['[data-task-id="task\\"\\\\id"]']);
});

test('task list keyboard runtime keeps bare timeout wiring inside the browser host factory', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/tasks/useTaskListKeyboard.runtime.ts'),
    'utf8',
  );
  const nonHostSource = source.replace(
    /export function createBrowserTaskListKeyboardHintTimerHost\(\): TaskListKeyboardHintTimerHost \{[\s\S]*?\n\}/,
    '',
  );

  assert.doesNotMatch(nonHostSource, /(?<!\.)\bsetTimeout\(/);
  assert.doesNotMatch(nonHostSource, /(?<!\.)\bclearTimeout\(/);
});
