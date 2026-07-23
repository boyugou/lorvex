import { beforeEach, describe, expect, it, vi } from 'vitest';

const reactRuntime = vi.hoisted(() => {
  let stateSlots: unknown[] = [];
  let refSlots: Array<{ current: unknown }> = [];
  let stateCursor = 0;
  let refCursor = 0;

  return {
    beginRender() {
      stateCursor = 0;
      refCursor = 0;
    },
    reset() {
      stateSlots = [];
      refSlots = [];
      stateCursor = 0;
      refCursor = 0;
    },
    useCallback<T extends (...args: never[]) => unknown>(fn: T): T {
      return fn;
    },
    useEffect(effect: () => void | (() => void)) {
      effect();
    },
    useId() {
      return 'hashtag-listbox';
    },
    useLayoutEffect(effect: () => void | (() => void)) {
      effect();
    },
    useMemo<T>(factory: () => T): T {
      return factory();
    },
    useRef<T>(initial: T): { current: T } {
      const index = refCursor;
      refCursor += 1;
      if (!refSlots[index]) {
        refSlots[index] = { current: initial };
      }
      return refSlots[index] as { current: T };
    },
    useState<T>(initial: T): [T, (next: T | ((prev: T) => T)) => void] {
      const index = stateCursor;
      stateCursor += 1;
      if (stateSlots[index] === undefined) {
        stateSlots[index] = initial;
      }
      return [
        stateSlots[index] as T,
        (next) => {
          const prev = stateSlots[index] as T;
          stateSlots[index] = typeof next === 'function'
            ? (next as (value: T) => T)(prev)
            : next;
        },
      ];
    },
  };
});

vi.mock('react', async () => {
  const actual = await vi.importActual<typeof import('react')>('react');
  return {
    ...actual,
    useCallback: reactRuntime.useCallback,
    useEffect: reactRuntime.useEffect,
    useId: reactRuntime.useId,
    useLayoutEffect: reactRuntime.useLayoutEffect,
    useMemo: reactRuntime.useMemo,
    useRef: reactRuntime.useRef,
    useState: reactRuntime.useState,
  };
});

vi.mock('@tanstack/react-query', () => ({
  useQuery: () => ({
    data: [
      { display_name: 'focus', color: null },
      { display_name: 'food', color: '#22c55e' },
      { display_name: 'follow-up', color: '#f97316' },
    ],
  }),
}));

vi.mock('@/lib/ipc/tasks/queries', () => ({
  getAllTags: vi.fn(),
}));

import { useHashtagAutocomplete } from './useHashtagAutocomplete';

function installDocumentStub(input: HTMLInputElement) {
  vi.stubGlobal('document', {
    activeElement: input,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
  });
}

function createInput(value: string): HTMLInputElement {
  return {
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    selectionStart: value.length,
    setSelectionRange: vi.fn(),
  } as unknown as HTMLInputElement;
}

describe('useHashtagAutocomplete dismissal', () => {
  beforeEach(() => {
    reactRuntime.reset();
    vi.unstubAllGlobals();
  });

  it('reopens suggestions after Escape when the typed hashtag fragment changes', () => {
    const input = createInput('Email #fo');
    installDocumentStub(input);
    const inputRef = { current: input };
    const onAcceptTag = vi.fn();

    function RenderAutocomplete(value: string) {
      input.selectionStart = value.length;
      reactRuntime.beginRender();
      return useHashtagAutocomplete({
        inputRef,
        value,
        onAcceptTag,
      });
    }

    RenderAutocomplete('Email #fo');
    const opened = RenderAutocomplete('Email #fo');
    expect(opened.open).toBe(true);
    expect(opened.suggestions.map((tag) => tag.display_name)).toContain('focus');

    const escapeEvent = {
      key: 'Escape',
      preventDefault: vi.fn(),
    };
    expect(opened.onInputKeyDown(escapeEvent as never)).toBe(true);
    expect(escapeEvent.preventDefault).toHaveBeenCalledOnce();

    const dismissed = RenderAutocomplete('Email #fo');
    expect(dismissed.open).toBe(false);

    RenderAutocomplete('Email #foo');
    RenderAutocomplete('Email #foo');
    const reopened = RenderAutocomplete('Email #foo');

    expect(reopened.open).toBe(true);
    expect(reopened.suggestions.map((tag) => tag.display_name)).toEqual(['food']);
  });
});
