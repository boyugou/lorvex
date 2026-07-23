import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

import {
  clampPortalDropdownLeft,
  createBrowserAnchoredPopupDismissRuntimeDeps,
  createBrowserPortalDropdownDismissRuntimeDeps,
  installAnchoredPopupDismissRuntime,
  resolveAnchoredPopupPosition,
  resolveFilterDropdownPanelPosition,
  resolvePortalDropdownListboxPosition,
  shouldDismissAnchoredPopupFromKeyEvent,
  shouldDismissAnchoredPopupFromTarget,
  startPortalDropdownDismissRuntime,
} from '../../../app/src/components/ui/portalDropdown.runtime';

function buildKeyboardEvent(overrides: Partial<KeyboardEvent> = {}): KeyboardEvent {
  return {
    isComposing: false,
    key: 'Escape',
    preventDefault() {},
    stopPropagation() {},
    ...overrides,
  } as KeyboardEvent;
}

test('clampPortalDropdownLeft keeps portal panels inside both viewport edges', () => {
  assert.equal(clampPortalDropdownLeft(-40, 160, 500), 8);
  assert.equal(clampPortalDropdownLeft(420, 160, 500), 332);
  assert.equal(clampPortalDropdownLeft(120, 160, 500), 120);
});

test('resolveFilterDropdownPanelPosition clamps both narrow and overflowing trigger positions', () => {
  assert.deepEqual(
    resolveFilterDropdownPanelPosition({ left: -24, bottom: 40 }, 320, 160),
    { top: 44, left: 8 },
  );
  assert.deepEqual(
    resolveFilterDropdownPanelPosition({ left: 280, bottom: 50 }, 320, 160),
    { top: 54, left: 152 },
  );
});

test('resolvePortalDropdownListboxPosition clamps width and chooses the upward branch when below space is tighter', () => {
  assert.deepEqual(
    resolvePortalDropdownListboxPosition(
      { top: 260, left: -20, right: 340, bottom: 292, width: 360 },
      320,
      300,
    ),
    {
      top: 256,
      left: 8,
      width: 304,
      openUpward: true,
    },
  );
});

test('startPortalDropdownDismissRuntime ignores inside events, dismisses outside activity, and unregisters listeners', () => {
  const documentListeners = new Map<string, EventListener>();
  const windowListeners = new Map<string, EventListener>();
  const dismissed: string[] = [];

  const cleanup = startPortalDropdownDismissRuntime({
    documentTarget: {
      addEventListener: (type, listener) => {
        documentListeners.set(type, listener as EventListener);
      },
      removeEventListener: (type, listener) => {
        if (documentListeners.get(type) === listener) {
          documentListeners.delete(type);
        }
      },
    },
    windowTarget: {
      addEventListener: (type, listener) => {
        windowListeners.set(type, listener as EventListener);
      },
      removeEventListener: (type, listener) => {
        if (windowListeners.get(type) === listener) {
          windowListeners.delete(type);
        }
      },
    },
    isEventInside: (target) => target === 'inside',
    onDismiss: () => dismissed.push('dismiss'),
  });

  documentListeners.get('pointerdown')?.({ target: 'inside' } as Event);
  documentListeners.get('scroll')?.({ target: 'inside' } as Event);
  assert.deepEqual(dismissed, []);

  documentListeners.get('pointerdown')?.({ target: 'outside' } as Event);
  documentListeners.get('scroll')?.({ target: 'outside' } as Event);
  windowListeners.get('resize')?.(new Event('resize'));
  assert.deepEqual(dismissed, ['dismiss', 'dismiss', 'dismiss']);

  cleanup();
  assert.equal(documentListeners.size, 0);
  assert.equal(windowListeners.size, 0);
});

test('startPortalDropdownDismissRuntime delegates through the anchored popup runtime implementation', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/ui/portalDropdown.runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /export function startPortalDropdownDismissRuntime\([\s\S]*return installAnchoredPopupDismissRuntime\(\{[\s\S]*addDocumentPointerDownListener:[\s\S]*addDocumentScrollListener:[\s\S]*addWindowResizeListener:[\s\S]*onPointerDismiss: onDismiss,[\s\S]*onScrollDismiss: onDismiss,[\s\S]*onResizeDismiss: onDismiss,[\s\S]*\}\);/s,
  );
  assert.doesNotMatch(source, /const handlePointerDown = \(event: Event\) => \{/);
  assert.doesNotMatch(source, /const handleResize = \(\) => \{/);
});

test('browser portal dropdown dismiss deps guard document, window, and Node hosts', () => {
  class FakeNode {}

  const documentListeners = new Map<string, EventListener>();
  const windowListeners = new Map<string, EventListener>();
  const dismissed: string[] = [];
  const insideNode = new FakeNode() as unknown as Node;
  const outsideNode = new FakeNode() as unknown as Node;
  const trigger = { contains: (node: Node) => node === insideNode } as HTMLElement;
  const panel = { contains: () => false } as unknown as HTMLElement;

  const cleanup = startPortalDropdownDismissRuntime(
    createBrowserPortalDropdownDismissRuntimeDeps({
      documentTarget: {
        addEventListener: (type, listener) => {
          documentListeners.set(type, listener as EventListener);
        },
        removeEventListener: (type, listener) => {
          if (documentListeners.get(type) === listener) documentListeners.delete(type);
        },
      },
      windowTarget: {
        addEventListener: (type, listener) => {
          windowListeners.set(type, listener as EventListener);
        },
        removeEventListener: (type, listener) => {
          if (windowListeners.get(type) === listener) windowListeners.delete(type);
        },
      },
      getTrigger: () => trigger,
      getPanel: () => panel,
      nodeConstructor: FakeNode as unknown as typeof Node,
      onDismiss: () => dismissed.push('dismiss'),
    }),
  );

  documentListeners.get('pointerdown')?.({ target: insideNode } as Event);
  documentListeners.get('pointerdown')?.({ target: outsideNode } as Event);
  documentListeners.get('scroll')?.({ target: {} } as Event);
  windowListeners.get('resize')?.(new Event('resize'));
  cleanup();

  assert.deepEqual(dismissed, ['dismiss', 'dismiss', 'dismiss']);
  assert.equal(documentListeners.size, 0);
  assert.equal(windowListeners.size, 0);
});

test('browser portal dropdown dismiss deps are inert without document or Node hosts', () => {
  const panel = { contains: () => true } as unknown as HTMLElement;

  const noDocumentDeps = createBrowserPortalDropdownDismissRuntimeDeps({
    documentTarget: undefined,
    windowTarget: undefined,
    getTrigger: () => panel,
    getPanel: () => panel,
    nodeConstructor: Object as unknown as typeof Node,
    onDismiss: () => assert.fail('dismiss should not run without document'),
  });

  assert.equal(noDocumentDeps.documentTarget, undefined);
  assert.equal(noDocumentDeps.windowTarget, undefined);
  assert.equal(noDocumentDeps.isEventInside({} as EventTarget), false);

  const noNodeDeps = createBrowserPortalDropdownDismissRuntimeDeps({
    documentTarget: {
      addEventListener: () => undefined,
      removeEventListener: () => undefined,
    },
    windowTarget: undefined,
    getTrigger: () => panel,
    getPanel: () => panel,
    nodeConstructor: undefined,
    onDismiss: () => assert.fail('dismiss should not run without Node'),
  });

  assert.equal(noNodeDeps.isEventInside({} as EventTarget), false);
});

test('resolveAnchoredPopupPosition clamps horizontally and flips above when requested', () => {
  assert.deepEqual(
    resolveAnchoredPopupPosition({
      rect: { top: 100, left: -40, bottom: 132 },
      viewportWidth: 500,
      popupWidth: 260,
      viewportHeight: 700,
      popupHeight: 280,
      gap: 6,
      viewportPadding: 8,
      verticalMargin: 12,
      flipVertically: true,
    }),
    { top: 138, left: 8 },
  );
  assert.deepEqual(
    resolveAnchoredPopupPosition({
      rect: { top: 360, left: 480, bottom: 392 },
      viewportWidth: 500,
      popupWidth: 260,
      viewportHeight: 520,
      popupHeight: 280,
      gap: 6,
      viewportPadding: 8,
      verticalMargin: 12,
      flipVertically: true,
    }),
    { top: 74, left: 232 },
  );
  assert.deepEqual(
    resolveAnchoredPopupPosition({
      rect: { top: 100, left: 700, right: 740, bottom: 132 },
      viewportWidth: 900,
      popupWidth: 192,
      gap: 4,
      horizontalAlign: 'end',
    }),
    { top: 136, left: 548 },
  );
});

test('resolveAnchoredPopupPosition keeps flipped panels inside the top viewport padding', () => {
  assert.deepEqual(
    resolveAnchoredPopupPosition({
      rect: { top: 282, left: 100, bottom: 314 },
      viewportWidth: 500,
      popupWidth: 180,
      viewportHeight: 360,
      popupHeight: 280,
      gap: 6,
      viewportPadding: 8,
      verticalMargin: 8,
      flipVertically: true,
    }),
    { top: 8, left: 100 },
  );
});

test('anchored popup dismiss predicates preserve inside targets and composing Escape', () => {
  const insideTarget = new EventTarget();
  const outsideTarget = new EventTarget();
  const isInsideTarget = (target: EventTarget | null) => target === insideTarget;

  assert.equal(shouldDismissAnchoredPopupFromTarget(insideTarget, isInsideTarget), false);
  assert.equal(shouldDismissAnchoredPopupFromTarget(outsideTarget, isInsideTarget), true);
  assert.equal(shouldDismissAnchoredPopupFromKeyEvent(buildKeyboardEvent()), true);
  assert.equal(
    shouldDismissAnchoredPopupFromKeyEvent(buildKeyboardEvent({ key: 'Enter' })),
    false,
  );
  assert.equal(
    shouldDismissAnchoredPopupFromKeyEvent(buildKeyboardEvent({ isComposing: true })),
    false,
  );
});

test('anchored popup dismiss runtime wires pointer, scroll, and Escape cleanup through one host', () => {
  const calls: string[] = [];
  let mouseDownListener: ((event: MouseEvent) => void) | undefined;
  let scrollListener: ((event: Event) => void) | undefined;
  let keydownListener: ((event: KeyboardEvent) => void) | undefined;
  const insideTarget = new EventTarget();
  const outsideTarget = new EventTarget();

  const cleanup = installAnchoredPopupDismissRuntime({
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
    addDocumentKeydownListener: (listener) => {
      keydownListener = listener;
      return () => {
        keydownListener = undefined;
        calls.push('cleanup-keydown');
      };
    },
    isInsideTarget: (target) => target === insideTarget,
    onPointerDismiss: () => calls.push('pointer-dismiss'),
    onScrollDismiss: () => calls.push('scroll-dismiss'),
    onEscapeDismiss: () => calls.push('escape-dismiss'),
  });

  mouseDownListener?.({ target: insideTarget } as MouseEvent);
  scrollListener?.({ target: insideTarget } as Event);
  mouseDownListener?.({ target: outsideTarget } as MouseEvent);
  scrollListener?.({ target: outsideTarget } as Event);
  keydownListener?.(buildKeyboardEvent({
    preventDefault: () => calls.push('prevent'),
    stopPropagation: () => calls.push('stop'),
  }));
  cleanup();

  assert.deepEqual(calls, [
    'pointer-dismiss',
    'scroll-dismiss',
    'prevent',
    'stop',
    'escape-dismiss',
    'cleanup-mousedown',
    'cleanup-scroll',
    'cleanup-keydown',
  ]);
  assert.equal(mouseDownListener, undefined);
  assert.equal(scrollListener, undefined);
  assert.equal(keydownListener, undefined);
});

test('anchored popup browser deps safely own document and Node host wiring', () => {
  const calls: string[] = [];
  let mouseDownListener: ((event: MouseEvent) => void) | undefined;
  let scrollListener: ((event: Event) => void) | undefined;
  let keydownListener: ((event: KeyboardEvent) => void) | undefined;
  const optionPhase = (options?: boolean | AddEventListenerOptions | EventListenerOptions) =>
    options === true || (typeof options === 'object' && options.capture === true)
      ? 'capture'
      : 'bubble';
  const insideNode = {} as Node;
  const outsideNode = {} as Node;
  const documentTarget = {
    addEventListener: (type: string, listener: EventListener, options?: boolean | AddEventListenerOptions) => {
      calls.push(`add:${type}:${optionPhase(options)}`);
      if (type === 'mousedown') mouseDownListener = listener as (event: MouseEvent) => void;
      if (type === 'scroll') scrollListener = listener as (event: Event) => void;
      if (type === 'keydown') keydownListener = listener as (event: KeyboardEvent) => void;
    },
    removeEventListener: (type: string, listener: EventListener, options?: boolean | EventListenerOptions) => {
      calls.push(`remove:${type}:${optionPhase(options)}`);
      if (type === 'mousedown' && mouseDownListener === listener) mouseDownListener = undefined;
      if (type === 'scroll' && scrollListener === listener) scrollListener = undefined;
      if (type === 'keydown' && keydownListener === listener) keydownListener = undefined;
    },
  };
  const trigger = { contains: (node: Node) => node === insideNode } as HTMLElement;
  const panel = { contains: () => false } as unknown as HTMLElement;

  const cleanup = installAnchoredPopupDismissRuntime(
    createBrowserAnchoredPopupDismissRuntimeDeps({
      documentTarget,
      getTrigger: () => trigger,
      getPanel: () => panel,
      nodeConstructor: Object as unknown as typeof Node,
      onPointerDismiss: () => calls.push('pointer-dismiss'),
      onScrollDismiss: () => calls.push('scroll-dismiss'),
      onEscapeDismiss: () => calls.push('escape-dismiss'),
      listenForScroll: true,
      listenForEscape: true,
      keydownCapture: true,
    }),
  );

  mouseDownListener?.({ target: insideNode } as MouseEvent);
  mouseDownListener?.({ target: outsideNode } as MouseEvent);
  scrollListener?.({ target: outsideNode } as Event);
  keydownListener?.(buildKeyboardEvent());
  cleanup();

  assert.deepEqual(calls, [
    'add:mousedown:bubble',
    'add:scroll:capture',
    'add:keydown:capture',
    'pointer-dismiss',
    'scroll-dismiss',
    'escape-dismiss',
    'remove:mousedown:bubble',
    'remove:scroll:capture',
    'remove:keydown:capture',
  ]);
  assert.equal(mouseDownListener, undefined);
  assert.equal(scrollListener, undefined);
  assert.equal(keydownListener, undefined);
});
