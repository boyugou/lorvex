import { describe, expect, it, vi } from 'vitest';

import {
  installHabitFormEscapeRuntime,
  shouldRequestHabitFormCloseFromEscape,
} from './AddHabitForm.runtime';

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
    addEventListener: vi.fn((type: string, listener: EventListener, options?: AddEventListenerOptions | boolean) => {
      expect(options).toBeUndefined();
      listeners.set(type, listener);
    }),
    removeEventListener: vi.fn((type: string) => {
      listeners.delete(type);
    }),
  };
}

describe('AddHabitForm Escape ownership', () => {
  it('ignores default-prevented Escape from nested overlays', () => {
    expect(shouldRequestHabitFormCloseFromEscape({
      key: 'Escape',
      isComposing: false,
      defaultPrevented: true,
    })).toBe(false);
  });

  it('ignores Escape outside the form root', () => {
    const root = new FakeNode();
    const outside = new FakeNode();

    expect(shouldRequestHabitFormCloseFromEscape({
      key: 'Escape',
      isComposing: false,
      defaultPrevented: false,
      target: outside as unknown as EventTarget,
      formRoot: root,
    })).toBe(false);
  });

  it('requests close for focused form Escape without capture-phase bypass', () => {
    const inside = new FakeNode();
    const root = new FakeNode([inside]);
    const requestClose = vi.fn();
    const windowTarget = createListenerTarget();
    const cleanup = installHabitFormEscapeRuntime({
      windowTarget,
      getFormRoot: () => root as unknown as HTMLElement,
      requestClose,
    });
    const preventDefault = vi.fn();

    windowTarget.listeners.get('keydown')?.({
      key: 'Escape',
      isComposing: false,
      defaultPrevented: false,
      target: inside,
      preventDefault,
    } as unknown as KeyboardEvent);

    expect(preventDefault).toHaveBeenCalledOnce();
    expect(requestClose).toHaveBeenCalledOnce();
    cleanup();
    expect(windowTarget.listeners.size).toBe(0);
  });
});
