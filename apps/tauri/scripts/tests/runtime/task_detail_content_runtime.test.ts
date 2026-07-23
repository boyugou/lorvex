import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  installTaskDetailShortcutRuntime,
  resolveTaskDetailShortcutAction,
  runTaskDetailShortcutAction,
  type TaskDetailShortcutAction,
  type TaskDetailShortcutRuntimeController,
} from '../../../app/src/components/task-detail/content/TaskDetailContent.runtime';
import {
  createBrowserAnchoredPopupDismissRuntimeDeps,
  installAnchoredPopupDismissRuntime,
  resolveAnchoredPopupPosition,
  shouldDismissAnchoredPopupFromTarget,
} from '../../../app/src/components/ui/portalDropdown.runtime';
import {
  focusTaskDetailOverflowMenuItem,
  resolveTaskDetailOverflowKeyAction,
} from '../../../app/src/components/task-detail/content/detail-content/TaskDetailOverflowMenu.runtime';

const plainTarget = new EventTarget();
const ignoredTarget = new EventTarget();

function shouldIgnore(target: EventTarget | null): boolean {
  return target === ignoredTarget;
}

function makeController(overrides: Partial<TaskDetailShortcutRuntimeController> = {}) {
  const calls: string[] = [];
  const controller: TaskDetailShortcutRuntimeController = {
    isComplete: false,
    taskStatus: 'open',
    handleClose: () => calls.push('close'),
    handleComplete: () => calls.push('complete'),
    handleDefer: (date) => calls.push(`defer:${date ?? 'null'}`),
    handleReopen: () => calls.push('reopen'),
    ...overrides,
  };

  return { calls, controller };
}

test('task detail shortcut resolver maps command-enter actions and Escape', () => {
  assert.equal(
    resolveTaskDetailShortcutAction(
      { key: 'Enter', target: plainTarget, metaKey: true },
      { isComplete: false, taskStatus: 'open' },
      shouldIgnore,
    ),
    'complete',
  );
  assert.equal(
    resolveTaskDetailShortcutAction(
      { key: 'Enter', target: plainTarget, ctrlKey: true },
      { isComplete: true, taskStatus: 'done' },
      shouldIgnore,
    ),
    'reopen',
  );
  assert.equal(
    resolveTaskDetailShortcutAction(
      { key: 'Enter', target: plainTarget, metaKey: true, shiftKey: true },
      { isComplete: false, taskStatus: 'open' },
      shouldIgnore,
    ),
    'defer',
  );
  assert.equal(
    resolveTaskDetailShortcutAction(
      { key: 'Escape', target: plainTarget },
      { isComplete: false, taskStatus: 'open' },
      shouldIgnore,
    ),
    'close',
  );
});

test('task detail shortcut resolver blurs editable Escape and ignores composition plus invalid defer states', () => {
  const state = { isComplete: false, taskStatus: 'open' };
  assert.equal(
    resolveTaskDetailShortcutAction(
      { key: 'Escape', target: ignoredTarget },
      state,
      shouldIgnore,
      (target) => target === ignoredTarget,
    ),
    'blur-editable',
  );
  assert.equal(
    resolveTaskDetailShortcutAction(
      { key: 'Enter', target: plainTarget, metaKey: true, isComposing: true },
      state,
      shouldIgnore,
    ),
    null,
  );
  assert.equal(
    resolveTaskDetailShortcutAction({ key: 'Enter', target: plainTarget }, state, shouldIgnore),
    null,
  );
  assert.equal(
    resolveTaskDetailShortcutAction(
      { key: 'Enter', target: plainTarget, metaKey: true, shiftKey: true },
      { isComplete: false, taskStatus: 'cancelled' },
      shouldIgnore,
    ),
    null,
  );
  assert.equal(
    resolveTaskDetailShortcutAction(
      { key: 'Enter', target: plainTarget, metaKey: true, shiftKey: true },
      { isComplete: true, taskStatus: 'done' },
      shouldIgnore,
    ),
    null,
  );
});

test('task detail shortcut runner invokes the expected controller action', () => {
  const { calls, controller } = makeController();
  const actions: TaskDetailShortcutAction[] = ['complete', 'defer', 'reopen', 'close'];

  for (const action of actions) {
    runTaskDetailShortcutAction(action, controller);
  }

  assert.deepEqual(calls, ['complete', 'defer:null', 'reopen', 'close']);
});

test('task detail shortcut runtime uses the latest controller, prevents defaults, and unregisters cleanup', () => {
  let listener: EventListener | undefined;
  const first = makeController();
  const second = makeController({ isComplete: true, taskStatus: 'done' });
  let current = first.controller;
  const calls: string[] = [];

  const cleanup = installTaskDetailShortcutRuntime({
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
    getController: () => current,
    shouldIgnoreShortcutTarget: shouldIgnore,
    isEditableTarget: (target) => target === ignoredTarget,
  });

  listener?.({
    key: 'Enter',
    target: plainTarget,
    metaKey: true,
    preventDefault: () => calls.push('prevent-complete'),
  } as KeyboardEvent);
  current = second.controller;
  listener?.({
    key: 'Enter',
    target: plainTarget,
    ctrlKey: true,
    preventDefault: () => calls.push('prevent-reopen'),
  } as KeyboardEvent);
  listener?.({
    key: 'Escape',
    target: ignoredTarget,
    preventDefault: () => calls.push('prevent-ignored'),
  } as KeyboardEvent);
  cleanup();

  assert.deepEqual(calls, ['prevent-complete', 'prevent-reopen', 'prevent-ignored', 'cleanup']);
  assert.deepEqual(first.calls, ['complete']);
  assert.deepEqual(second.calls, ['reopen']);
  assert.equal(listener, undefined);
});

test('task detail overflow position preserves trailing-edge anchoring through the shared popup resolver', () => {
  assert.deepEqual(
    resolveAnchoredPopupPosition({
      rect: { top: 10, left: 660, right: 700, bottom: 40 },
      viewportWidth: 900,
      popupWidth: 192,
      gap: 4,
      horizontalAlign: 'end',
    }),
    { top: 44, left: 508 },
  );
  assert.deepEqual(
    resolveAnchoredPopupPosition({
      rect: { top: 10, left: 880, right: 920, bottom: 40 },
      viewportWidth: 900,
      popupWidth: 192,
      gap: 4,
      horizontalAlign: 'end',
    }),
    { top: 44, left: 700 },
  );
});

test('task detail overflow keyboard resolver and focus helper wrap through enabled menu items', () => {
  assert.deepEqual(
    resolveTaskDetailOverflowKeyAction({ key: 'ArrowDown', currentIndex: -1, itemCount: 3 }),
    { type: 'focus', index: 0 },
  );
  assert.deepEqual(
    resolveTaskDetailOverflowKeyAction({ key: 'ArrowUp', currentIndex: -1, itemCount: 3 }),
    { type: 'focus', index: 2 },
  );
  assert.deepEqual(
    resolveTaskDetailOverflowKeyAction({ key: 'Home', currentIndex: 2, itemCount: 3 }),
    { type: 'focus', index: 0 },
  );
  assert.deepEqual(
    resolveTaskDetailOverflowKeyAction({ key: 'End', currentIndex: 0, itemCount: 3 }),
    { type: 'focus', index: 2 },
  );
  assert.deepEqual(
    resolveTaskDetailOverflowKeyAction({ key: 'Escape', currentIndex: 0, itemCount: 3 }),
    { type: 'close' },
  );
  assert.deepEqual(
    resolveTaskDetailOverflowKeyAction({ key: 'ArrowDown', currentIndex: -1, itemCount: 0 }),
    { type: 'none' },
  );

  const calls: string[] = [];
  const items = [
    { focus: () => calls.push('item-0') },
    { focus: () => calls.push('item-1') },
    { focus: () => calls.push('item-2') },
  ] as HTMLElement[];
  const panel = { focus: () => calls.push('panel') } as HTMLElement;

  assert.equal(
    focusTaskDetailOverflowMenuItem({ items, panel, index: 3 }),
    0,
  );
  assert.equal(
    focusTaskDetailOverflowMenuItem({ items, panel, index: -1 }),
    2,
  );
  assert.equal(
    focusTaskDetailOverflowMenuItem({ items: [], panel, index: 0 }),
    null,
  );
  assert.deepEqual(calls, ['item-0', 'item-2', 'panel']);
});

test('task detail overflow dismissal uses shared anchored popup runtime with trigger and panel ownership', () => {
  const insideTarget = new EventTarget();
  const panelTarget = new EventTarget();
  const outsideTarget = new EventTarget();
  let listener: EventListener | undefined;
  let scrollListener: EventListener | undefined;
  let resizeListener: EventListener | undefined;
  const calls: string[] = [];

  assert.equal(
    shouldDismissAnchoredPopupFromTarget(insideTarget, (target) => target === insideTarget),
    false,
  );
  assert.equal(
    shouldDismissAnchoredPopupFromTarget(outsideTarget, (target) => target === insideTarget),
    true,
  );

  const cleanup = installAnchoredPopupDismissRuntime(createBrowserAnchoredPopupDismissRuntimeDeps({
    documentTarget: {
      addEventListener: (type, nextListener) => {
        if (type === 'pointerdown') {
          listener = nextListener as EventListener;
        } else if (type === 'scroll') {
          scrollListener = nextListener as EventListener;
        }
      },
      removeEventListener: (type, nextListener) => {
        if (type === 'pointerdown' && listener === nextListener) {
          listener = undefined;
          calls.push('pointer-cleanup');
        }
        if (type === 'scroll' && scrollListener === nextListener) {
          scrollListener = undefined;
          calls.push('scroll-cleanup');
        }
      },
    },
    windowTarget: {
      addEventListener: (type, nextListener) => {
        assert.equal(type, 'resize');
        resizeListener = nextListener as EventListener;
      },
      removeEventListener: (type, nextListener) => {
        assert.equal(type, 'resize');
        if (resizeListener === nextListener) {
          resizeListener = undefined;
          calls.push('resize-cleanup');
        }
      },
    },
    getTrigger: () => ({
      contains: (target: EventTarget | null) => target === insideTarget,
    } as HTMLElement),
    getPanel: () => ({
      contains: (target: EventTarget | null) => target === panelTarget,
    } as HTMLElement),
    nodeConstructor: EventTarget as unknown as typeof Node,
    onPointerDismiss: () => calls.push('pointer-dismiss'),
    onScrollDismiss: () => calls.push('scroll-dismiss'),
    onResizeDismiss: () => calls.push('resize-dismiss'),
    listenForScroll: true,
    listenForResize: true,
    pointerEventType: 'pointerdown',
  }));

  listener?.({ target: insideTarget } as Event);
  listener?.({ target: panelTarget } as Event);
  listener?.({ target: outsideTarget } as Event);
  scrollListener?.({ target: insideTarget } as Event);
  scrollListener?.({ target: outsideTarget } as Event);
  resizeListener?.({ target: outsideTarget } as Event);
  cleanup();

  assert.deepEqual(calls, [
    'pointer-dismiss',
    'scroll-dismiss',
    'resize-dismiss',
    'pointer-cleanup',
    'scroll-cleanup',
    'resize-cleanup',
  ]);
  assert.equal(listener, undefined);
  assert.equal(scrollListener, undefined);
  assert.equal(resizeListener, undefined);
});

test('task detail content component delegates shortcuts and overflow menu to shared anchored popup runtime', () => {
  const source = [
    fs.readFileSync(
      path.join(process.cwd(), 'app/src/components/task-detail/content/TaskDetailContent.tsx'),
      'utf8',
    ),
    fs.readFileSync(
      path.join(process.cwd(), 'app/src/components/task-detail/content/detail-content/TaskDetailOverflowMenu.tsx'),
      'utf8',
    ),
  ].join('\n');

  assert.match(source, /installTaskDetailShortcutRuntime/);
  assert.match(source, /createBrowserAnchoredPopupDismissRuntimeDeps/);
  assert.match(source, /installAnchoredPopupDismissRuntime/);
  assert.match(source, /resolveAnchoredPopupPosition/);
  assert.match(source, /resolveTaskDetailOverflowKeyAction/);
  assert.match(source, /focusTaskDetailOverflowMenuItem/);
  assert.match(source, /horizontalAlign:\s*'end'/);
  assert.match(source, /getPanel:\s*\(\)\s*=>\s*overflowPanelRef\.current/);
  assert.match(source, /shouldIgnoreShortcutTarget: shouldIgnoreShortcut,/);
  assert.match(source, /handleDefer: ctrl\.handleDefer,/);
  assert.doesNotMatch(source, /const onKeyDown = \(e: KeyboardEvent\) => \{/);
  assert.doesNotMatch(source, /document\.addEventListener\('mousedown', handler\)/);
  assert.doesNotMatch(source, /installTaskDetailOverflowDismissRuntime/);
  assert.doesNotMatch(source, /resolveTaskDetailOverflowPosition/);
});
