import { describe, expect, it, vi } from 'vitest';

import {
  createBrowserAnchoredPopupDismissRuntimeDeps,
  installAnchoredPopupDismissRuntime,
  resolveAnchoredPopupPosition,
} from './portalDropdown.runtime';

class FakeNode {
  constructor(private readonly children: FakeNode[] = []) {}

  contains(target: unknown): boolean {
    return target === this || this.children.includes(target as FakeNode);
  }
}

function createListenerTarget() {
  const listeners = new Map<string, EventListener>();
  return {
    listeners,
    addEventListener: vi.fn((type: string, listener: EventListener) => {
      listeners.set(type, listener);
    }),
    removeEventListener: vi.fn((type: string) => {
      listeners.delete(type);
    }),
  };
}

describe('createBrowserAnchoredPopupDismissRuntimeDeps', () => {
  it('treats both trigger and portaled panel descendants as inside targets', () => {
    const triggerChild = new FakeNode();
    const panelChild = new FakeNode();
    const trigger = new FakeNode([triggerChild]);
    const panel = new FakeNode([panelChild]);
    const outside = new FakeNode();

    const deps = createBrowserAnchoredPopupDismissRuntimeDeps({
      documentTarget: createListenerTarget(),
      getTrigger: () => trigger as unknown as HTMLElement,
      getPanel: () => panel as unknown as HTMLElement,
      nodeConstructor: FakeNode as unknown as typeof Node,
    });

    expect(deps.isInsideTarget(triggerChild as unknown as EventTarget)).toBe(true);
    expect(deps.isInsideTarget(panelChild as unknown as EventTarget)).toBe(true);
    expect(deps.isInsideTarget(outside as unknown as EventTarget)).toBe(false);
  });
});

describe('installAnchoredPopupDismissRuntime', () => {
  it('dismisses on outside pointer, scroll, resize, and Escape while preserving inside clicks', () => {
    const trigger = new FakeNode();
    const panel = new FakeNode();
    const outside = new FakeNode();
    const calls: string[] = [];
    const documentTarget = createListenerTarget();
    const windowTarget = createListenerTarget();
    const deps = createBrowserAnchoredPopupDismissRuntimeDeps({
      documentTarget,
      windowTarget,
      getTrigger: () => trigger as unknown as HTMLElement,
      getPanel: () => panel as unknown as HTMLElement,
      nodeConstructor: FakeNode as unknown as typeof Node,
      onPointerDismiss: () => calls.push('pointer'),
      onScrollDismiss: () => calls.push('scroll'),
      onEscapeDismiss: () => calls.push('escape'),
      onResizeDismiss: () => calls.push('resize'),
      listenForScroll: true,
      listenForEscape: true,
      listenForResize: true,
      pointerEventType: 'pointerdown',
    });

    const cleanup = installAnchoredPopupDismissRuntime(deps);

    documentTarget.listeners.get('pointerdown')?.({ target: panel } as unknown as Event);
    documentTarget.listeners.get('pointerdown')?.({ target: outside } as unknown as Event);
    documentTarget.listeners.get('scroll')?.({ target: outside } as unknown as Event);
    documentTarget.listeners.get('keydown')?.({
      key: 'Escape',
      isComposing: false,
      preventDefault: vi.fn(),
      stopPropagation: vi.fn(),
    } as unknown as KeyboardEvent);
    windowTarget.listeners.get('resize')?.({ target: outside } as unknown as Event);

    expect(calls).toEqual(['pointer', 'scroll', 'escape', 'resize']);
    cleanup();
    expect(documentTarget.listeners.size).toBe(0);
    expect(windowTarget.listeners.size).toBe(0);
  });
});

describe('resolveAnchoredPopupPosition', () => {
  it('flips anchored popups above the trigger and clamps horizontally', () => {
    const position = resolveAnchoredPopupPosition({
      rect: {
        top: 220,
        left: 260,
        right: 320,
        bottom: 250,
      },
      viewportWidth: 320,
      viewportHeight: 280,
      popupWidth: 180,
      popupHeight: 100,
      flipVertically: true,
    });

    expect(position).toEqual({
      top: 116,
      left: 132,
    });
  });

  it('keeps anchored popups below the trigger when there is room', () => {
    const position = resolveAnchoredPopupPosition({
      rect: {
        top: 40,
        left: 24,
        bottom: 64,
      },
      viewportWidth: 360,
      viewportHeight: 640,
      popupWidth: 180,
      popupHeight: 120,
      flipVertically: true,
    });

    expect(position).toEqual({
      top: 68,
      left: 24,
    });
  });
});
