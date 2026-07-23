import { describe, expect, test, vi } from 'vitest';

import {
  createFocusRestoreMachine,
  isRestorableHTMLElement,
} from './focusRestore.logic';

// Focus restoration: when a modal/sheet/popover opens, snapshot the
// current active element; when it closes, refocus that element if
// it's still around. The machine is a tiny state holder + a guarded
// refocus, so its tests pin the guards (null snapshot, snapshot's
// element no longer in the DOM, snapshot is "isRestorable" but in a
// hidden subtree). A regression that calls `policy.focus(null)` or
// silently swallows a `false` close return would lose accessibility-
// critical focus management.

describe('createFocusRestoreMachine', () => {
  test('open + close happy path: snapshots and refocuses', () => {
    const focus = vi.fn();
    const machine = createFocusRestoreMachine<string>({
      isRestorable: () => true,
      focus,
    });

    machine.open('button-A');
    expect(machine.snapshot()).toBe('button-A');

    const restored = machine.close();
    expect(restored).toBe(true);
    expect(focus).toHaveBeenCalledTimes(1);
    expect(focus).toHaveBeenCalledWith('button-A');
    // After close, snapshot is cleared so re-close is a no-op.
    expect(machine.snapshot()).toBeNull();
  });

  test('close without open: false, focus never called', () => {
    const focus = vi.fn();
    const machine = createFocusRestoreMachine<string>({
      isRestorable: () => true,
      focus,
    });
    expect(machine.close()).toBe(false);
    expect(focus).not.toHaveBeenCalled();
  });

  test('open with null active element: close returns false', () => {
    // Browsers can have `document.activeElement = body` which the
    // caller normalizes to null. The machine must not call focus on
    // a null target.
    const focus = vi.fn();
    const machine = createFocusRestoreMachine<string>({
      isRestorable: () => true,
      focus,
    });
    machine.open(null);
    expect(machine.close()).toBe(false);
    expect(focus).not.toHaveBeenCalled();
  });

  test('snapshot is no longer restorable: close returns false, focus not called', () => {
    // The element was removed from the DOM (or moved offscreen)
    // between open and close. Don't call focus — the policy guard
    // exists exactly to avoid focusing a detached node.
    const focus = vi.fn();
    const isRestorable = vi.fn().mockReturnValue(false);
    const machine = createFocusRestoreMachine<string>({
      isRestorable,
      focus,
    });
    machine.open('detached');
    expect(machine.close()).toBe(false);
    expect(isRestorable).toHaveBeenCalledWith('detached');
    expect(focus).not.toHaveBeenCalled();
  });

  test('close clears snapshot even when refocus is refused', () => {
    // Important invariant: snapshot is consumed regardless of
    // whether refocus actually fires. Otherwise a non-restorable
    // close would leave the stale reference in memory and a
    // subsequent open call would see it briefly.
    const machine = createFocusRestoreMachine<string>({
      isRestorable: () => false,
      focus: vi.fn(),
    });
    machine.open('detached');
    expect(machine.snapshot()).toBe('detached');
    machine.close();
    expect(machine.snapshot()).toBeNull();
  });

  test('re-open before close overwrites the previous snapshot', () => {
    const focus = vi.fn();
    const machine = createFocusRestoreMachine<string>({
      isRestorable: () => true,
      focus,
    });
    machine.open('first');
    machine.open('second');
    expect(machine.snapshot()).toBe('second');
    machine.close();
    expect(focus).toHaveBeenCalledExactlyOnceWith('second');
  });
});

describe('isRestorableHTMLElement', () => {
  // Test runs in the default `node` Vitest environment (per
  // app/vitest.config.ts). Stub the HTMLElement shape rather than
  // pulling jsdom — `isRestorableHTMLElement` only consults
  // `isConnected` and `getClientRects`, so a structural stub matches
  // the function's actual contract surface.
  function stubElement(overrides: Partial<HTMLElement>): HTMLElement {
    return overrides as unknown as HTMLElement;
  }

  test('disconnected element is not restorable', () => {
    expect(isRestorableHTMLElement(stubElement({ isConnected: false }))).toBe(false);
  });

  test('connected element with no client rects (display:none) is not restorable', () => {
    const stub = stubElement({
      isConnected: true,
      getClientRects: () => ({ length: 0 } as unknown as DOMRectList),
    });
    expect(isRestorableHTMLElement(stub)).toBe(false);
  });

  test('connected element with at least one client rect is restorable', () => {
    const stub = stubElement({
      isConnected: true,
      getClientRects: () => ({ length: 1 } as unknown as DOMRectList),
    });
    expect(isRestorableHTMLElement(stub)).toBe(true);
  });

  test('connected element without getClientRects support is restorable (defensive arm)', () => {
    // Older jsdom or non-browser hosts may not implement
    // `getClientRects`. The implementation falls through to "treat as
    // restorable" rather than refusing to restore — accessibility
    // takes priority over the offscreen heuristic.
    expect(isRestorableHTMLElement(stubElement({ isConnected: true }))).toBe(true);
  });
});
