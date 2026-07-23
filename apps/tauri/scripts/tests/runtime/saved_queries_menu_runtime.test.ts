import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserSavedQueriesMenuDismissRuntimeDeps,
  focusSavedQueriesMenuInitialTarget,
  installSavedQueriesMenuDismissRuntime,
  resolveSavedQueriesMenuPosition,
  shouldDismissSavedQueriesMenuFromKeyEvent,
  shouldDismissSavedQueriesMenuFromPointerTarget,
} from '../../../app/src/components/ui/SavedQueriesMenu.runtime';

function buildKeyboardEvent(overrides: Partial<KeyboardEvent> = {}): KeyboardEvent {
  return {
    isComposing: false,
    key: 'Escape',
    preventDefault() {},
    stopPropagation() {},
    ...overrides,
  } as KeyboardEvent;
}

test('saved queries menu position clamps both viewport edges', () => {
  assert.deepEqual(
    resolveSavedQueriesMenuPosition({ left: -40, bottom: 100 }, 500),
    { top: 104, left: 8 },
  );
  assert.deepEqual(
    resolveSavedQueriesMenuPosition({ left: 480, bottom: 120 }, 500),
    { top: 124, left: 232 },
  );
  assert.deepEqual(
    resolveSavedQueriesMenuPosition({ left: 120, bottom: 140 }, 500),
    { top: 144, left: 120 },
  );
});

test('saved queries menu dismiss predicates ignore inside targets and composing Escape', () => {
  const insideTarget = new EventTarget();
  const outsideTarget = new EventTarget();

  assert.equal(
    shouldDismissSavedQueriesMenuFromPointerTarget(
      insideTarget,
      (target) => target === insideTarget,
    ),
    false,
  );
  assert.equal(
    shouldDismissSavedQueriesMenuFromPointerTarget(
      outsideTarget,
      (target) => target === insideTarget,
    ),
    true,
  );
  assert.equal(shouldDismissSavedQueriesMenuFromKeyEvent(buildKeyboardEvent()), true);
  assert.equal(
    shouldDismissSavedQueriesMenuFromKeyEvent(buildKeyboardEvent({ key: 'Enter' })),
    false,
  );
  assert.equal(
    shouldDismissSavedQueriesMenuFromKeyEvent(buildKeyboardEvent({ isComposing: true })),
    false,
  );
});

test('saved queries menu initial focus keeps owned focus, then targets loading, row, and name input states', () => {
  const calls: string[] = [];
  const panel = { focus: () => calls.push('panel') } as HTMLElement;
  const firstItem = { focus: () => calls.push('first-item') } as HTMLElement;
  const nameInput = { focus: () => calls.push('name-input') } as HTMLElement;
  const ownedActive = {};

  assert.equal(
    focusSavedQueriesMenuInitialTarget({
      panel,
      activeElement: ownedActive,
      isActiveElementInPanel: (activeElement) => activeElement === ownedActive,
      isLoading: false,
      savedQueryCount: 1,
      firstItem,
      nameInput,
    }),
    'active-element',
  );
  assert.equal(
    focusSavedQueriesMenuInitialTarget({
      panel,
      activeElement: null,
      isActiveElementInPanel: () => false,
      isLoading: true,
      savedQueryCount: 1,
      firstItem,
      nameInput,
    }),
    'panel',
  );
  assert.equal(
    focusSavedQueriesMenuInitialTarget({
      panel,
      activeElement: null,
      isActiveElementInPanel: () => false,
      isLoading: false,
      savedQueryCount: 1,
      firstItem,
      nameInput,
    }),
    'first-item',
  );
  assert.equal(
    focusSavedQueriesMenuInitialTarget({
      panel,
      activeElement: null,
      isActiveElementInPanel: () => false,
      isLoading: false,
      savedQueryCount: 0,
      firstItem,
      nameInput,
    }),
    'name-input',
  );
  assert.equal(
    focusSavedQueriesMenuInitialTarget({
      panel: null,
      activeElement: null,
      isActiveElementInPanel: () => false,
      isLoading: false,
      savedQueryCount: 0,
      firstItem,
      nameInput,
    }),
    'none',
  );
  assert.equal(
    focusSavedQueriesMenuInitialTarget({
      panel,
      activeElement: null,
      isActiveElementInPanel: () => false,
      isLoading: false,
      savedQueryCount: 1,
      firstItem: null,
      nameInput,
    }),
    'panel',
  );
  assert.equal(
    focusSavedQueriesMenuInitialTarget({
      panel,
      activeElement: null,
      isActiveElementInPanel: () => false,
      isLoading: false,
      savedQueryCount: 0,
      firstItem,
      nameInput: null,
    }),
    'panel',
  );
  assert.deepEqual(calls, ['panel', 'first-item', 'name-input', 'panel', 'panel']);
});

test('saved queries menu dismiss runtime closes on outside click and Escape, then unregisters listeners', () => {
  const calls: string[] = [];
  let mouseDownListener: ((event: MouseEvent) => void) | undefined;
  let keydownListener: ((event: KeyboardEvent) => void) | undefined;
  const insideTarget = new EventTarget();
  const outsideTarget = new EventTarget();

  const cleanup = installSavedQueriesMenuDismissRuntime({
    addDocumentMouseDownListener: (listener) => {
      mouseDownListener = listener;
      return () => {
        mouseDownListener = undefined;
        calls.push('cleanup-mousedown');
      };
    },
    addDocumentKeydownListener: (listener) => {
      keydownListener = listener;
      return () => {
        keydownListener = undefined;
        calls.push('cleanup-keydown');
      };
    },
    isInsideTarget: (target) => target === insideTarget,
    onDismiss: () => calls.push('dismiss'),
  });

  mouseDownListener?.({ target: insideTarget } as MouseEvent);
  mouseDownListener?.({ target: outsideTarget } as MouseEvent);
  keydownListener?.(buildKeyboardEvent({
    preventDefault: () => calls.push('prevent'),
    stopPropagation: () => calls.push('stop'),
  }));
  cleanup();

  assert.deepEqual(calls, [
    'dismiss',
    'prevent',
    'stop',
    'dismiss',
    'cleanup-mousedown',
    'cleanup-keydown',
  ]);
  assert.equal(mouseDownListener, undefined);
  assert.equal(keydownListener, undefined);
});

test('saved queries menu dismiss runtime is inert without document hosts', () => {
  const cleanup = installSavedQueriesMenuDismissRuntime({
    addDocumentMouseDownListener: null,
    addDocumentKeydownListener: null,
    isInsideTarget: () => false,
    onDismiss: () => {
      throw new Error('dismiss should not run without installed listeners');
    },
  });

  cleanup();
});

test('saved queries menu browser dismiss deps safely own document and Node host wiring', () => {
  const calls: string[] = [];
  let mouseDownListener: ((event: MouseEvent) => void) | undefined;
  let keydownListener: ((event: KeyboardEvent) => void) | undefined;
  const insideNode = {} as Node;
  const outsideNode = {} as Node;
  const documentTarget = {
    addEventListener: (type: string, listener: EventListener) => {
      if (type === 'mousedown') mouseDownListener = listener as (event: MouseEvent) => void;
      if (type === 'keydown') keydownListener = listener as (event: KeyboardEvent) => void;
    },
    removeEventListener: (type: string, listener: EventListener) => {
      if (type === 'mousedown' && mouseDownListener === listener) mouseDownListener = undefined;
      if (type === 'keydown' && keydownListener === listener) keydownListener = undefined;
    },
  };
  const trigger = { contains: (node: Node) => node === insideNode } as HTMLElement;
  const panel = { contains: () => false } as unknown as HTMLElement;

  const cleanup = installSavedQueriesMenuDismissRuntime(
    createBrowserSavedQueriesMenuDismissRuntimeDeps({
      documentTarget,
      getTrigger: () => trigger,
      getPanel: () => panel,
      nodeConstructor: Object as unknown as typeof Node,
      onDismiss: () => calls.push('dismiss'),
    }),
  );

  mouseDownListener?.({ target: insideNode } as MouseEvent);
  mouseDownListener?.({ target: outsideNode } as MouseEvent);
  keydownListener?.(buildKeyboardEvent({
    preventDefault: () => calls.push('prevent'),
    stopPropagation: () => calls.push('stop'),
  }));
  cleanup();

  assert.deepEqual(calls, ['dismiss', 'prevent', 'stop', 'dismiss']);
  assert.equal(mouseDownListener, undefined);
  assert.equal(keydownListener, undefined);
});

test('saved queries menu browser dismiss deps are inert without document or Node hosts', () => {
  const panel = { contains: () => true } as unknown as HTMLElement;

  const noDocumentDeps = createBrowserSavedQueriesMenuDismissRuntimeDeps({
    documentTarget: undefined,
    getTrigger: () => panel,
    getPanel: () => panel,
    nodeConstructor: Object as unknown as typeof Node,
    onDismiss: () => assert.fail('dismiss should not run without document'),
  });

  assert.equal(noDocumentDeps.addDocumentMouseDownListener, null);
  assert.equal(noDocumentDeps.addDocumentKeydownListener, null);
  assert.equal(noDocumentDeps.isInsideTarget({} as EventTarget), false);

  const noNodeDeps = createBrowserSavedQueriesMenuDismissRuntimeDeps({
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

test('saved queries menu component delegates position and dismissal wiring to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/ui/SavedQueriesMenu.tsx'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/ui/SavedQueriesMenu.runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserSavedQueriesMenuDismissRuntimeDeps,[\s\S]*installSavedQueriesMenuDismissRuntime,[\s\S]*resolveSavedQueriesMenuPosition,[\s\S]*\} from '\.\/SavedQueriesMenu\.runtime';/s,
  );
  assert.match(
    source,
    /return installSavedQueriesMenuDismissRuntime\(\s*createBrowserSavedQueriesMenuDismissRuntimeDeps\(\{[\s\S]*getTrigger: \(\) => triggerRef\.current,[\s\S]*getPanel: \(\) => panelRef\.current,[\s\S]*onDismiss:/s,
  );
  assert.match(source, /setPanelPos\(resolveSavedQueriesMenuPosition\(rect, window\.innerWidth\)\);/);
  assert.match(source, /aria-controls=\{open \? menuId : undefined\}/);
  assert.match(source, /id=\{menuId\}/);
  assert.match(source, /focusSavedQueriesMenuInitialTarget/);
  assert.match(source, /firstItem: firstSavedQueryButtonRef\.current/);
  assert.match(source, /nameInput: newNameInputRef\.current/);
  assert.doesNotMatch(source, /typeof document === 'undefined'/);
  assert.doesNotMatch(source, /target instanceof Node/);
  assert.doesNotMatch(source, /window\.addEventListener\('keydown'/);
  assert.doesNotMatch(source, /const handleClick = \(e: MouseEvent\) => \{/);
  assert.doesNotMatch(source, /const handleKey = \(e: KeyboardEvent\) => \{/);
  assert.match(
    runtimeSource,
    /import \{[\s\S]*createBrowserAnchoredPopupDismissRuntimeDeps,[\s\S]*installAnchoredPopupDismissRuntime,[\s\S]*resolveAnchoredPopupPosition,[\s\S]*shouldDismissAnchoredPopupFromKeyEvent,[\s\S]*shouldDismissAnchoredPopupFromTarget,[\s\S]*\} from '\.\/portalDropdown\.runtime';/s,
  );
});
