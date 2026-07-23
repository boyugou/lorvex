import { beforeEach, describe, expect, it, vi } from 'vitest';

const hookRuntime = vi.hoisted(() => ({
  stateSlots: [] as unknown[],
  memoSlots: [] as Array<{ deps: readonly unknown[]; value: unknown }>,
  effectSlots: [] as Array<{ deps: readonly unknown[] }>,
  pendingEffects: [] as Array<() => void>,
  stateCursor: 0,
  memoCursor: 0,
  effectCursor: 0,
}));

function depsChanged(prev: readonly unknown[] | undefined, next: readonly unknown[]): boolean {
  if (!prev || prev.length !== next.length) return true;
  return next.some((dep, index) => !Object.is(dep, prev[index]));
}

vi.mock('react', () => ({
  useState: <T>(initial: T | (() => T)) => {
    const slot = hookRuntime.stateCursor;
    hookRuntime.stateCursor += 1;
    if (slot >= hookRuntime.stateSlots.length) {
      hookRuntime.stateSlots.push(typeof initial === 'function' ? (initial as () => T)() : initial);
    }

    const setState = (next: T | ((prev: T) => T)) => {
      const prev = hookRuntime.stateSlots[slot] as T;
      hookRuntime.stateSlots[slot] = typeof next === 'function' ? (next as (prev: T) => T)(prev) : next;
    };

    return [hookRuntime.stateSlots[slot] as T, setState] as const;
  },
  useMemo: <T>(factory: () => T, deps: readonly unknown[]) => {
    const slot = hookRuntime.memoCursor;
    hookRuntime.memoCursor += 1;
    const cached = hookRuntime.memoSlots[slot];
    if (!cached || depsChanged(cached.deps, deps)) {
      const value = factory();
      hookRuntime.memoSlots[slot] = { deps, value };
      return value;
    }
    return cached.value as T;
  },
  useCallback: <T extends (...args: never[]) => unknown>(callback: T, deps: readonly unknown[]) => {
    const slot = hookRuntime.memoCursor;
    hookRuntime.memoCursor += 1;
    const cached = hookRuntime.memoSlots[slot];
    if (!cached || depsChanged(cached.deps, deps)) {
      hookRuntime.memoSlots[slot] = { deps, value: callback };
      return callback;
    }
    return cached.value as T;
  },
  useEffect: (effect: () => void, deps: readonly unknown[]) => {
    const slot = hookRuntime.effectCursor;
    hookRuntime.effectCursor += 1;
    const cached = hookRuntime.effectSlots[slot];
    if (!cached || depsChanged(cached.deps, deps)) {
      hookRuntime.effectSlots[slot] = { deps };
      hookRuntime.pendingEffects.push(effect);
    }
  },
}));

import { useCurrentPickerFocusIndex } from './useCurrentPickerFocusIndex';

const OPTIONS = [
  { key: 'today' },
  { key: 'tomorrow' },
  { key: 'weekend' },
  { key: 'none' },
] as const;

function PickerFocusHarness({
  currentKey,
  options,
}: {
  currentKey: string;
  options: readonly { key: string }[];
}) {
  return useCurrentPickerFocusIndex({ currentKey, options });
}

function render(currentKey: string, options: readonly { key: string }[] = OPTIONS) {
  hookRuntime.stateCursor = 0;
  hookRuntime.memoCursor = 0;
  hookRuntime.effectCursor = 0;

  const result = PickerFocusHarness({ currentKey, options });
  const pendingEffects = hookRuntime.pendingEffects.splice(0);
  for (const effect of pendingEffects) effect();
  return result;
}

function reset() {
  hookRuntime.stateSlots.length = 0;
  hookRuntime.memoSlots.length = 0;
  hookRuntime.effectSlots.length = 0;
  hookRuntime.pendingEffects.length = 0;
  hookRuntime.stateCursor = 0;
  hookRuntime.memoCursor = 0;
  hookRuntime.effectCursor = 0;
}

describe('useCurrentPickerFocusIndex', () => {
  beforeEach(reset);

  it('initializes focus at the current option', () => {
    const [focusIdx] = render('weekend');

    expect(focusIdx).toBe(2);
  });

  it('falls back to the first option for custom or missing current keys', () => {
    const [focusIdx] = render('custom');

    expect(focusIdx).toBe(0);
  });

  it('does not reset arrow-key navigation when the current option is unchanged', () => {
    const [, setFocusIdx] = render('weekend');
    setFocusIdx((prev) => prev + 1);

    const [focusIdx] = render('weekend');

    expect(focusIdx).toBe(3);
  });

  it('reanchors focus when the current option changes', () => {
    render('weekend');

    const [focusIdx] = render('tomorrow');

    expect(focusIdx).toBe(1);
  });

  it('clamps to the current option when the option set changes', () => {
    render('weekend');

    const [focusIdx] = render('none', [{ key: 'today' }, { key: 'none' }]);

    expect(focusIdx).toBe(1);
  });
});
