import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserTimeInputDropdownDismissRuntimeDeps,
  getNextTimeInputFocusIndex,
  getTimeInputInitialFocusIndex,
  installTimeInputDropdownDismissRuntime,
  resolveTimeInputDropdownPosition,
  shouldDismissTimeInputDropdownFromKeyEvent,
  shouldDismissTimeInputDropdownFromPointerTarget,
} from '../../../app/src/components/settings/SettingsPrimitives.runtime';

function buildKeyboardEvent(overrides: Partial<KeyboardEvent> = {}): KeyboardEvent {
  return {
    isComposing: false,
    key: 'Escape',
    preventDefault() {},
    stopPropagation() {},
    ...overrides,
  } as KeyboardEvent;
}

test('time input dropdown key predicate only accepts non-composing Escape', () => {
  assert.equal(shouldDismissTimeInputDropdownFromKeyEvent(buildKeyboardEvent()), true);
  assert.equal(
    shouldDismissTimeInputDropdownFromKeyEvent(buildKeyboardEvent({ key: 'Enter' })),
    false,
  );
  assert.equal(
    shouldDismissTimeInputDropdownFromKeyEvent(buildKeyboardEvent({ isComposing: true })),
    false,
  );
});

test('time input dropdown pointer predicate ignores trigger and listbox targets', () => {
  const insideTarget = new EventTarget();
  const outsideTarget = new EventTarget();

  assert.equal(
    shouldDismissTimeInputDropdownFromPointerTarget(
      insideTarget,
      (target) => target === insideTarget,
    ),
    false,
  );
  assert.equal(
    shouldDismissTimeInputDropdownFromPointerTarget(
      outsideTarget,
      (target) => target === insideTarget,
    ),
    true,
  );
});

test('time input dropdown position opens below by default and flips above near viewport bottom', () => {
  assert.deepEqual(
    resolveTimeInputDropdownPosition(
      { top: 100, left: 32, bottom: 132 },
      { viewportWidth: 800, viewportHeight: 600 },
    ),
    { top: 136, left: 32 },
  );
  assert.deepEqual(
    resolveTimeInputDropdownPosition(
      { top: 300, left: 32, bottom: 332 },
      { viewportWidth: 800, viewportHeight: 360 },
    ),
    { top: 56, left: 32 },
  );
});

test('time input keyboard focus helpers resolve selected, increment/decrement, and clamp edges', () => {
  const slots = ['00:00', '00:30', '01:00', '09:00', '23:30'] as const;

  assert.equal(getTimeInputInitialFocusIndex('01:00', slots), 2);
  assert.equal(getTimeInputInitialFocusIndex('09:15', slots), 3);
  assert.equal(getTimeInputInitialFocusIndex('09:15', ['00:00', '00:30']), 0);
  assert.equal(getTimeInputInitialFocusIndex('09:15', []), -1);

  assert.equal(getNextTimeInputFocusIndex('ArrowDown', 2, slots.length), 3);
  assert.equal(getNextTimeInputFocusIndex('ArrowUp', 2, slots.length), 1);
  assert.equal(getNextTimeInputFocusIndex('Home', 2, slots.length), 0);
  assert.equal(getNextTimeInputFocusIndex('End', 2, slots.length), slots.length - 1);
  assert.equal(getNextTimeInputFocusIndex('ArrowDown', slots.length - 1, slots.length), slots.length - 1);
  assert.equal(getNextTimeInputFocusIndex('ArrowUp', 0, slots.length), 0);
  assert.equal(getNextTimeInputFocusIndex('ArrowDown', -1, slots.length), 0);
  assert.equal(getNextTimeInputFocusIndex('Tab', 2, slots.length), 2);
  assert.equal(getNextTimeInputFocusIndex('ArrowDown', 2, 0), -1);
});

test('time input dropdown runtime prevents Escape, restores focus, dismisses outside clicks, and cleans up', () => {
  const calls: string[] = [];
  let keydownListener: ((event: KeyboardEvent) => void) | undefined;
  let mouseDownListener: ((event: MouseEvent) => void) | undefined;
  const insideTarget = new EventTarget();
  const outsideTarget = new EventTarget();

  const cleanup = installTimeInputDropdownDismissRuntime({
    addDocumentKeydownListener: (listener) => {
      keydownListener = listener;
      return () => {
        keydownListener = undefined;
        calls.push('cleanup-keydown');
      };
    },
    addDocumentMouseDownListener: (listener) => {
      mouseDownListener = listener;
      return () => {
        mouseDownListener = undefined;
        calls.push('cleanup-mousedown');
      };
    },
    isInsideTarget: (target) => target === insideTarget,
    onEscapeDismiss: () => calls.push('escape-dismiss'),
    onPointerDismiss: () => calls.push('pointer-dismiss'),
  });

  keydownListener?.(buildKeyboardEvent({
    preventDefault: () => calls.push('prevent'),
    stopPropagation: () => calls.push('stop'),
  }));
  mouseDownListener?.({ target: insideTarget } as MouseEvent);
  mouseDownListener?.({ target: outsideTarget } as MouseEvent);
  cleanup();

  assert.deepEqual(calls, [
    'prevent',
    'stop',
    'escape-dismiss',
    'pointer-dismiss',
    'cleanup-mousedown',
    'cleanup-keydown',
  ]);
  assert.equal(keydownListener, undefined);
  assert.equal(mouseDownListener, undefined);
});

test('time input dropdown browser dismiss deps delegate document and Node wiring to shared runtime', () => {
  const calls: string[] = [];
  let keydownListener: ((event: KeyboardEvent) => void) | undefined;
  let mouseDownListener: ((event: MouseEvent) => void) | undefined;
  const insideNode = {} as Node;
  const outsideNode = {} as Node;
  const documentTarget = {
    addEventListener: (type: string, listener: EventListener, options?: boolean | AddEventListenerOptions) => {
      if (type === 'keydown' && options === true) keydownListener = listener as (event: KeyboardEvent) => void;
      if (type === 'mousedown') mouseDownListener = listener as (event: MouseEvent) => void;
    },
    removeEventListener: (type: string, listener: EventListener, options?: boolean | EventListenerOptions) => {
      if (type === 'keydown' && options === true && keydownListener === listener) keydownListener = undefined;
      if (type === 'mousedown' && mouseDownListener === listener) mouseDownListener = undefined;
    },
  };
  const trigger = { contains: (node: Node) => node === insideNode } as HTMLElement;
  const panel = { contains: () => false } as unknown as HTMLElement;

  const cleanup = installTimeInputDropdownDismissRuntime(
    createBrowserTimeInputDropdownDismissRuntimeDeps({
      documentTarget,
      getTrigger: () => trigger,
      getPanel: () => panel,
      nodeConstructor: Object as unknown as typeof Node,
      onEscapeDismiss: () => calls.push('escape-dismiss'),
      onPointerDismiss: () => calls.push('pointer-dismiss'),
    }),
  );

  mouseDownListener?.({ target: insideNode } as MouseEvent);
  mouseDownListener?.({ target: outsideNode } as MouseEvent);
  keydownListener?.(buildKeyboardEvent());
  cleanup();

  assert.deepEqual(calls, ['pointer-dismiss', 'escape-dismiss']);
  assert.equal(keydownListener, undefined);
  assert.equal(mouseDownListener, undefined);
});

test('time input dropdown runtime is inert without document hosts', () => {
  const cleanup = installTimeInputDropdownDismissRuntime({
    addDocumentKeydownListener: null,
    addDocumentMouseDownListener: null,
    isInsideTarget: () => false,
    onEscapeDismiss: () => {
      throw new Error('escape dismiss should not run without installed listeners');
    },
    onPointerDismiss: () => {
      throw new Error('pointer dismiss should not run without installed listeners');
    },
  });

  cleanup();
});

test('settings time input delegates document dismissal wiring to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/settings/SettingsPrimitives.tsx'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/settings/SettingsPrimitives.runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserTimeInputDropdownDismissRuntimeDeps,[\s\S]*getNextTimeInputFocusIndex,[\s\S]*getTimeInputInitialFocusIndex,[\s\S]*installTimeInputDropdownDismissRuntime,[\s\S]*resolveTimeInputDropdownPosition,[\s\S]*\} from '\.\/SettingsPrimitives\.runtime';/s,
  );
  assert.match(
    source,
    /setPosition\(resolveTimeInputDropdownPosition\(rect, \{[\s\S]*viewportWidth: window\.innerWidth,[\s\S]*viewportHeight: window\.innerHeight,[\s\S]*\}\)\);/s,
  );
  assert.match(
    source,
    /const closeDropdown = useCallback\(\(restoreFocus = false\) => \{[\s\S]*setOpen\(false\);[\s\S]*if \(restoreFocus\) \{[\s\S]*triggerRef\.current\?\.focus\(\);[\s\S]*\}[\s\S]*\}, \[\]\);/s,
  );
  assert.match(
    source,
    /return installTimeInputDropdownDismissRuntime\(\s*createBrowserTimeInputDropdownDismissRuntimeDeps\(\{[\s\S]*getTrigger: \(\) => triggerRef\.current,[\s\S]*getPanel: \(\) => listRef\.current,[\s\S]*onEscapeDismiss:[\s\S]*closeDropdown\(true\);[\s\S]*onPointerDismiss:/s,
  );
  assert.match(source, /const listboxId = useId\(\);/);
  assert.match(source, /const optionRefs = useRef<Array<HTMLDivElement \| null>>\(\[\]\);/);
  assert.match(source, /onKeyDown=\{handleTriggerKeyDown\}/);
  assert.match(source, /onKeyDown=\{handleListKeyDown\}/);
  assert.match(source, /aria-controls=\{open \? listboxId : undefined\}/);
  assert.match(source, /aria-activedescendant=\{activeDescendantId\}/);
  assert.match(source, /tabIndex=\{activeIndex === index \? 0 : -1\}/);
  assert.doesNotMatch(source, /const onKeyDown = \(e: KeyboardEvent\) => \{/);
  assert.doesNotMatch(source, /const onPointerDown = \(e: MouseEvent\) => \{/);
  assert.match(
    runtimeSource,
    /import \{[\s\S]*createBrowserAnchoredPopupDismissRuntimeDeps,[\s\S]*installAnchoredPopupDismissRuntime,[\s\S]*resolveAnchoredPopupPosition,[\s\S]*shouldDismissAnchoredPopupFromKeyEvent,[\s\S]*shouldDismissAnchoredPopupFromTarget,[\s\S]*\} from '\.\.\/ui\/portalDropdown\.runtime';/s,
  );
});
