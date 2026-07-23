import { describe, expect, it, vi } from 'vitest';

import {
  installEventFormEscapeRuntime,
  shouldCancelEventFormFromKey,
} from './EventForm.runtime';

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

describe('EventForm Escape ownership', () => {
  it('ignores Escape already consumed by a nested overlay', () => {
    expect(shouldCancelEventFormFromKey({
      key: 'Escape',
      isComposing: false,
      defaultPrevented: true,
    })).toBe(false);
  });

  it('ignores Escape outside the form root so portaled overlays stay topmost', () => {
    const inside = new FakeNode();
    const outside = new FakeNode();
    const root = new FakeNode([inside]);
    expect(shouldCancelEventFormFromKey({
      key: 'Escape',
      isComposing: false,
      defaultPrevented: false,
      target: outside as unknown as EventTarget,
      formRoot: root,
    })).toBe(false);
  });

  it('cancels focused form Escape and unregisters the listener', () => {
    const inside = new FakeNode();
    const root = new FakeNode([inside]);
    const calls: string[] = [];
    const documentTarget = createListenerTarget();
    const cleanup = installEventFormEscapeRuntime({
      documentTarget,
      getFormRoot: () => root as unknown as HTMLElement,
      getOnCancel: () => () => calls.push('cancel'),
    });

    const preventDefault = vi.fn();
    documentTarget.listeners.get('keydown')?.({
      key: 'Escape',
      isComposing: false,
      defaultPrevented: false,
      target: inside,
      preventDefault,
    } as unknown as KeyboardEvent);

    expect(preventDefault).toHaveBeenCalledOnce();
    expect(calls).toEqual(['cancel']);
    cleanup();
    expect(documentTarget.listeners.size).toBe(0);
  });
});
