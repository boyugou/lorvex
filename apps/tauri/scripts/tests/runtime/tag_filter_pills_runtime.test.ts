import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  advanceTagFilterPillsTypeAhead,
  clearTagFilterPillsTypeAhead,
  createBrowserTagFilterPillsDismissRuntimeDeps,
  createBrowserTagFilterPillsTypeAheadTimerHost,
  findTagFilterPillsTypeAheadMatch,
  installTagFilterPillsDismissRuntime,
  resolveTagFilterPillsPanelPosition,
  shouldDismissTagFilterPillsFromTarget,
  type TagFilterPillsTypeAheadState,
  type TagFilterPillsTypeAheadTimerHost,
} from '../../../app/src/components/ui/TagFilterPills.runtime';

function createTypeAheadTimerHost() {
  const callbacks: Array<() => void> = [];
  const clearedHandles: unknown[] = [];
  const delays: number[] = [];
  const host: TagFilterPillsTypeAheadTimerHost = {
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

test('tag filter pills panel position clamps both viewport edges', () => {
  assert.deepEqual(
    resolveTagFilterPillsPanelPosition({ left: -24, bottom: 40 }, 480),
    { top: 44, left: 8 },
  );
  assert.deepEqual(
    resolveTagFilterPillsPanelPosition({ left: 460, bottom: 60 }, 480),
    { top: 64, left: 216 },
  );
  assert.deepEqual(
    resolveTagFilterPillsPanelPosition({ left: 120, bottom: 80 }, 480),
    { top: 84, left: 120 },
  );
});

test('tag filter pills dismiss predicate preserves trigger and panel targets', () => {
  const insideTarget = new EventTarget();
  const outsideTarget = new EventTarget();

  assert.equal(
    shouldDismissTagFilterPillsFromTarget(insideTarget, (target) => target === insideTarget),
    false,
  );
  assert.equal(
    shouldDismissTagFilterPillsFromTarget(outsideTarget, (target) => target === insideTarget),
    true,
  );
});

test('tag filter pills dismiss runtime closes on outside pointer and scroll then unregisters listeners', () => {
  const calls: string[] = [];
  let mouseDownListener: ((event: MouseEvent) => void) | undefined;
  let scrollListener: ((event: Event) => void) | undefined;
  const insideTarget = new EventTarget();
  const outsideTarget = new EventTarget();

  const cleanup = installTagFilterPillsDismissRuntime({
    addDocumentMouseDownListener: (listener) => {
      mouseDownListener = listener;
      return () => {
        mouseDownListener = undefined;
        calls.push('cleanup-mousedown');
      };
    },
    addDocumentScrollListener: (listener) => {
      scrollListener = listener;
      return () => {
        scrollListener = undefined;
        calls.push('cleanup-scroll');
      };
    },
    isInsideTarget: (target) => target === insideTarget,
    onDismiss: () => calls.push('dismiss'),
  });

  mouseDownListener?.({ target: insideTarget } as MouseEvent);
  scrollListener?.({ target: insideTarget } as Event);
  mouseDownListener?.({ target: outsideTarget } as MouseEvent);
  scrollListener?.({ target: outsideTarget } as Event);
  cleanup();

  assert.deepEqual(calls, [
    'dismiss',
    'dismiss',
    'cleanup-mousedown',
    'cleanup-scroll',
  ]);
  assert.equal(mouseDownListener, undefined);
  assert.equal(scrollListener, undefined);
});

test('tag filter pills dismiss runtime is inert without document hosts', () => {
  const cleanup = installTagFilterPillsDismissRuntime({
    addDocumentMouseDownListener: null,
    addDocumentScrollListener: null,
    isInsideTarget: () => false,
    onDismiss: () => {
      throw new Error('dismiss should not run without installed listeners');
    },
  });

  cleanup();
});

test('tag filter pills browser dismiss deps safely own document and Node host wiring', () => {
  const calls: string[] = [];
  let mouseDownListener: ((event: MouseEvent) => void) | undefined;
  let scrollListener: ((event: Event) => void) | undefined;
  const insideNode = {} as Node;
  const outsideNode = {} as Node;
  const documentTarget = {
    addEventListener: (type: string, listener: EventListener) => {
      if (type === 'mousedown') mouseDownListener = listener as (event: MouseEvent) => void;
      if (type === 'scroll') scrollListener = listener as (event: Event) => void;
    },
    removeEventListener: (type: string, listener: EventListener) => {
      if (type === 'mousedown' && mouseDownListener === listener) mouseDownListener = undefined;
      if (type === 'scroll' && scrollListener === listener) scrollListener = undefined;
    },
  };
  const trigger = { contains: (node: Node) => node === insideNode } as HTMLElement;
  const panel = { contains: () => false } as unknown as HTMLElement;

  const cleanup = installTagFilterPillsDismissRuntime(
    createBrowserTagFilterPillsDismissRuntimeDeps({
      documentTarget,
      getTrigger: () => trigger,
      getPanel: () => panel,
      nodeConstructor: Object as unknown as typeof Node,
      onDismiss: () => calls.push('dismiss'),
    }),
  );

  mouseDownListener?.({ target: insideNode } as MouseEvent);
  mouseDownListener?.({ target: outsideNode } as MouseEvent);
  scrollListener?.({ target: outsideNode } as Event);
  cleanup();

  assert.deepEqual(calls, ['dismiss', 'dismiss']);
  assert.equal(mouseDownListener, undefined);
  assert.equal(scrollListener, undefined);
});

test('tag filter pills browser dismiss deps are inert without document or Node hosts', () => {
  const panel = { contains: () => true } as unknown as HTMLElement;

  const noDocumentDeps = createBrowserTagFilterPillsDismissRuntimeDeps({
    documentTarget: undefined,
    getTrigger: () => panel,
    getPanel: () => panel,
    nodeConstructor: Object as unknown as typeof Node,
    onDismiss: () => assert.fail('dismiss should not run without document'),
  });

  assert.equal(noDocumentDeps.addDocumentMouseDownListener, null);
  assert.equal(noDocumentDeps.addDocumentScrollListener, null);
  assert.equal(noDocumentDeps.isInsideTarget({} as EventTarget), false);

  const noNodeDeps = createBrowserTagFilterPillsDismissRuntimeDeps({
    documentTarget: {
      addEventListener: () => undefined,
      removeEventListener: () => undefined,
    },
    getTrigger: () => panel,
    getPanel: () => panel,
    nodeConstructor: undefined,
    onDismiss: () => assert.fail('dismiss should not run without Node'),
  });

  assert.equal(noNodeDeps.isInsideTarget({} as EventTarget), false);
});

test('tag filter pills type-ahead finds the next matching tag from current focus', () => {
  const tags = ['Alpha', 'Beta', 'Alpine'];

  assert.equal(findTagFilterPillsTypeAheadMatch(tags, -1, 'a'), 0);
  assert.equal(findTagFilterPillsTypeAheadMatch(tags, 0, 'a'), 2);
  assert.equal(findTagFilterPillsTypeAheadMatch(tags, 2, 'b'), 1);
  assert.equal(findTagFilterPillsTypeAheadMatch(tags, 1, 'z'), null);
  assert.equal(findTagFilterPillsTypeAheadMatch([], 0, 'a'), null);
});

test('tag filter pills type-ahead accumulates a buffer, resets it by timer, and clears stale timers', () => {
  const timer = createTypeAheadTimerHost();
  const state: TagFilterPillsTypeAheadState = { timer: null, buffer: '' };

  assert.equal(advanceTagFilterPillsTypeAhead({
    state,
    typedChar: 'a',
    tags: ['Alpha', 'Beta', 'Alpine'],
    focusedIndex: -1,
    timerHost: timer.host,
  }), 0);
  assert.equal(state.buffer, 'a');
  assert.deepEqual(timer.delays, [500]);

  assert.equal(advanceTagFilterPillsTypeAhead({
    state,
    typedChar: 'l',
    tags: ['Alpha', 'Beta', 'Alpine'],
    focusedIndex: 0,
    timerHost: timer.host,
  }), 2);
  assert.equal(state.buffer, 'al');
  assert.deepEqual(timer.clearedHandles, ['timer-1']);

  timer.callbacks[1]?.();
  assert.deepEqual(state, { timer: null, buffer: '' });
});

test('tag filter pills type-ahead cleanup clears the pending timer and buffer', () => {
  const clearedHandles: unknown[] = [];
  const state: TagFilterPillsTypeAheadState = {
    timer: 'timer-pending',
    buffer: 'al',
  };

  clearTagFilterPillsTypeAhead(state, (handle) => {
    clearedHandles.push(handle);
  });

  assert.deepEqual(clearedHandles, ['timer-pending']);
  assert.deepEqual(state, { timer: null, buffer: '' });
});

test('tag filter pills component delegates position and dismissal wiring to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/ui/TagFilterPills.tsx'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/ui/TagFilterPills.runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*advanceTagFilterPillsTypeAhead,[\s\S]*clearTagFilterPillsTypeAhead,[\s\S]*createBrowserTagFilterPillsDismissRuntimeDeps,[\s\S]*createBrowserTagFilterPillsTypeAheadTimerHost,[\s\S]*installTagFilterPillsDismissRuntime,[\s\S]*resolveTagFilterPillsPanelPosition,[\s\S]*type TagFilterPillsTypeAheadState,[\s\S]*\} from '\.\/TagFilterPills\.runtime';/s,
  );
  assert.match(source, /const tagFilterPillsTypeAheadTimerHost = createBrowserTagFilterPillsTypeAheadTimerHost\(\);/);
  assert.match(
    source,
    /const cleanupDismiss = installTagFilterPillsDismissRuntime\(\s*createBrowserTagFilterPillsDismissRuntimeDeps\(\{[\s\S]*getTrigger: \(\) => triggerRef\.current,[\s\S]*getPanel: \(\) => panelRef\.current,[\s\S]*onDismiss:/s,
  );
  assert.match(
    source,
    /clearTagFilterPillsTypeAhead\([\s\S]*typeAheadRef\.current,[\s\S]*tagFilterPillsTypeAheadTimerHost\.clearTimeout,[\s\S]*\);/s,
  );
  assert.match(
    source,
    /const matchIndex = advanceTagFilterPillsTypeAhead\(\{[\s\S]*state: typeAheadRef\.current,[\s\S]*typedChar: char,[\s\S]*tags: filteredTags,[\s\S]*focusedIndex,[\s\S]*timerHost: tagFilterPillsTypeAheadTimerHost,[\s\S]*\}\);/s,
  );
  assert.match(source, /setPanelPos\(resolveTagFilterPillsPanelPosition\(rect, window\.innerWidth\)\);/);
  assert.doesNotMatch(source, /typeof document === 'undefined'/);
  assert.doesNotMatch(source, /target instanceof Node/);
  assert.doesNotMatch(source, /(?<!\.)\bsetTimeout\(/);
  assert.doesNotMatch(source, /(?<!\.)\bclearTimeout\(/);
  assert.doesNotMatch(source, /const handleClick = \(e: MouseEvent\) => \{/);
  assert.doesNotMatch(source, /const handleScroll = \(e: Event\) => \{/);

  assert.match(
    runtimeSource,
    /import \{[\s\S]*createBrowserAnchoredPopupDismissRuntimeDeps,[\s\S]*installAnchoredPopupDismissRuntime,[\s\S]*resolveAnchoredPopupPosition,[\s\S]*shouldDismissAnchoredPopupFromTarget,[\s\S]*\} from '\.\/portalDropdown\.runtime';/s,
  );
  assert.match(runtimeSource, /export function createBrowserTagFilterPillsTypeAheadTimerHost\(\): TagFilterPillsTypeAheadTimerHost/);
  assert.match(runtimeSource, /globalThis\.clearTimeout\(handle as ReturnType<typeof globalThis\.setTimeout>\);/);
  assert.match(runtimeSource, /setTimeout: \(callback, delayMs\) => globalThis\.setTimeout\(callback, delayMs\),/);
});

test('tag filter pills runtime owns the browser type-ahead timer host wiring', () => {
  const host = createBrowserTagFilterPillsTypeAheadTimerHost();
  assert.equal(typeof host.setTimeout, 'function');
  assert.equal(typeof host.clearTimeout, 'function');
});
