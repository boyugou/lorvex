import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  installPopoverTaskDeferMenuDismissRuntime,
  resolvePopoverTaskDeferMenuPosition,
  shouldDismissPopoverTaskDeferMenuFromKeyEvent,
  shouldDismissPopoverTaskDeferMenuFromPointerTarget,
} from '../../../app/src/components/popover-window/PopoverTaskItem.runtime';

function buildKeyboardEvent(overrides: Partial<KeyboardEvent> = {}): KeyboardEvent {
  return {
    isComposing: false,
    key: 'Escape',
    stopPropagation() {},
    ...overrides,
  } as KeyboardEvent;
}

test('popover task defer menu position opens down when there is room', () => {
  assert.deepEqual(
    resolvePopoverTaskDeferMenuPosition({ left: 24, top: 100, bottom: 124 }, 300),
    { left: 24, top: 128 },
  );
});

test('popover task defer menu position opens up and clamps top into the viewport', () => {
  assert.deepEqual(
    resolvePopoverTaskDeferMenuPosition({ left: 24, top: 220, bottom: 244 }, 280),
    { left: 24, top: 156 },
  );
  assert.deepEqual(
    resolvePopoverTaskDeferMenuPosition({ left: 24, top: 20, bottom: 44 }, 80),
    { left: 24, top: 4 },
  );
});

test('popover task defer menu pointer and key predicates ignore inside targets and composing Escape', () => {
  const insideTarget = new EventTarget();
  const outsideTarget = new EventTarget();
  const isInside = (target: EventTarget | null) => target === insideTarget;

  assert.equal(shouldDismissPopoverTaskDeferMenuFromPointerTarget(insideTarget, isInside), false);
  assert.equal(shouldDismissPopoverTaskDeferMenuFromPointerTarget(outsideTarget, isInside), true);
  assert.equal(shouldDismissPopoverTaskDeferMenuFromKeyEvent(buildKeyboardEvent()), true);
  assert.equal(
    shouldDismissPopoverTaskDeferMenuFromKeyEvent(buildKeyboardEvent({ key: 'Enter' })),
    false,
  );
  assert.equal(
    shouldDismissPopoverTaskDeferMenuFromKeyEvent(buildKeyboardEvent({ isComposing: true })),
    false,
  );
});

test('popover task defer menu dismiss runtime closes on outside click and Escape, then cleans up', () => {
  const calls: string[] = [];
  let mouseDownListener: ((event: MouseEvent) => void) | undefined;
  let keydownListener: ((event: KeyboardEvent) => void) | undefined;
  const insideTarget = new EventTarget();
  const outsideTarget = new EventTarget();

  const cleanup = installPopoverTaskDeferMenuDismissRuntime({
    addWindowMouseDownListener: (listener) => {
      mouseDownListener = listener;
      return () => {
        mouseDownListener = undefined;
        calls.push('cleanup-mousedown');
      };
    },
    addWindowKeydownListener: (listener) => {
      keydownListener = listener;
      return () => {
        keydownListener = undefined;
        calls.push('cleanup-keydown');
      };
    },
    isInsideMenuOrTrigger: (target) => target === insideTarget,
    onDismiss: () => calls.push('dismiss'),
  });

  mouseDownListener?.({ target: insideTarget } as MouseEvent);
  mouseDownListener?.({ target: outsideTarget } as MouseEvent);
  keydownListener?.(buildKeyboardEvent({ key: 'Enter' }));
  keydownListener?.(buildKeyboardEvent({ isComposing: true }));
  keydownListener?.(buildKeyboardEvent({ stopPropagation: () => calls.push('stop') }));
  cleanup();

  assert.deepEqual(calls, [
    'dismiss',
    'stop',
    'dismiss',
    'cleanup-mousedown',
    'cleanup-keydown',
  ]);
  assert.equal(mouseDownListener, undefined);
  assert.equal(keydownListener, undefined);
});

test('popover task defer menu dismiss runtime is inert without window hosts', () => {
  const cleanup = installPopoverTaskDeferMenuDismissRuntime({
    addWindowMouseDownListener: null,
    addWindowKeydownListener: null,
    isInsideMenuOrTrigger: () => false,
    onDismiss: () => {
      throw new Error('dismiss should not run without installed listeners');
    },
  });

  cleanup();
});

test('popover task item delegates defer menu position and dismissal wiring to runtime helpers', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/popover-window/PopoverTaskItem.tsx'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*installPopoverTaskDeferMenuDismissRuntime,[\s\S]*resolvePopoverTaskDeferMenuPosition,[\s\S]*\} from '\.\/PopoverTaskItem\.runtime';/s,
  );
  assert.match(source, /setDeferMenuPos\(resolvePopoverTaskDeferMenuPosition\(/);
  assert.match(
    source,
    /return installPopoverTaskDeferMenuDismissRuntime\(\{[\s\S]*addWindowMouseDownListener: typeof window === 'undefined'[\s\S]*window\.addEventListener\('mousedown', listener, true\);[\s\S]*addWindowKeydownListener: typeof window === 'undefined'[\s\S]*window\.addEventListener\('keydown', listener, true\);[\s\S]*isInsideMenuOrTrigger:[\s\S]*onDismiss: \(\) => setDeferMenuOpen\(false\),/s,
  );
  assert.doesNotMatch(source, /const handleClick = \(e: MouseEvent\) => \{/);
  assert.doesNotMatch(source, /const handleKey = \(e: KeyboardEvent\) => \{/);
});
