import { describe, expect, it, vi } from 'vitest';

import {
  createBrowserTimeInputDropdownDismissRuntimeDeps,
  installTimeInputDropdownDismissRuntime,
  resolveTimeInputDropdownPosition,
} from './SettingsPrimitives.runtime';

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

describe('TimeInput dropdown dismiss runtime', () => {
  it('dismisses on outside scroll and window resize', () => {
    const trigger = new FakeNode();
    const panel = new FakeNode();
    const outside = new FakeNode();
    const calls: string[] = [];
    const documentTarget = createListenerTarget();
    const windowTarget = createListenerTarget();

    const cleanup = installTimeInputDropdownDismissRuntime(
      createBrowserTimeInputDropdownDismissRuntimeDeps({
        documentTarget: documentTarget as unknown as Document,
        windowTarget: windowTarget as unknown as Window,
        getTrigger: () => trigger as unknown as HTMLElement,
        getPanel: () => panel as unknown as HTMLElement,
        nodeConstructor: FakeNode as unknown as typeof Node,
        onEscapeDismiss: () => calls.push('escape'),
        onPointerDismiss: () => calls.push('pointer'),
        onScrollDismiss: () => calls.push('scroll'),
        onResizeDismiss: () => calls.push('resize'),
      }),
    );

    documentTarget.listeners.get('scroll')?.({ target: panel } as unknown as Event);
    documentTarget.listeners.get('scroll')?.({ target: outside } as unknown as Event);
    windowTarget.listeners.get('resize')?.({ target: outside } as unknown as Event);

    expect(calls).toEqual(['scroll', 'resize']);
    cleanup();
    expect(documentTarget.listeners.size).toBe(0);
    expect(windowTarget.listeners.size).toBe(0);
  });
});

describe('resolveTimeInputDropdownPosition', () => {
  it('clamps right-edge dropdowns using the explicit time picker width', () => {
    const position = resolveTimeInputDropdownPosition(
      {
        top: 40,
        left: 220,
        bottom: 68,
      },
      {
        viewportWidth: 260,
        viewportHeight: 500,
      },
    );

    expect(position).toEqual({
      top: 72,
      left: 76,
    });
  });

  it('falls back to viewport padding when the time picker is wider than the viewport', () => {
    const position = resolveTimeInputDropdownPosition(
      {
        top: 40,
        left: 120,
        bottom: 68,
      },
      {
        viewportWidth: 160,
        viewportHeight: 500,
      },
    );

    expect(position.left).toBe(8);
  });
});
