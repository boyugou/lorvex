import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

type EffectRecord = {
  cleanup?: (() => void) | undefined;
  deps?: ReadonlyArray<unknown> | undefined;
};

const stateSlots: unknown[] = [];
const refSlots: Array<{ current: unknown }> = [];
const effectSlots: EffectRecord[] = [];
let stateCursor = 0;
let refCursor = 0;
let effectCursor = 0;

function depsChanged(prev: ReadonlyArray<unknown> | undefined, next: ReadonlyArray<unknown> | undefined): boolean {
  if (!prev || !next) return true;
  if (prev.length !== next.length) return true;
  for (let index = 0; index < prev.length; index += 1) {
    if (!Object.is(prev[index], next[index])) return true;
  }
  return false;
}

vi.mock('react', () => ({
  useEffect: (effect: () => void | (() => void), deps?: ReadonlyArray<unknown>) => {
    const slotIndex = effectCursor++;
    const previous = effectSlots[slotIndex];
    if (!previous || depsChanged(previous.deps, deps)) {
      previous?.cleanup?.();
      const cleanup = effect() ?? undefined;
      effectSlots[slotIndex] = { cleanup, deps };
    }
  },
  useMemo: <T>(factory: () => T) => factory(),
  useRef: <T>(initial: T) => {
    if (refCursor >= refSlots.length) {
      refSlots.push({ current: initial });
    }
    return refSlots[refCursor++] as { current: T };
  },
  useState: <T>(initial: T) => {
    const slotIndex = stateCursor++;
    if (slotIndex >= stateSlots.length) {
      stateSlots.push(initial);
    }
    return [
      stateSlots[slotIndex] as T,
      (next: T | ((prev: T) => T)) => {
        const prev = stateSlots[slotIndex] as T;
        stateSlots[slotIndex] = typeof next === 'function'
          ? (next as (prev: T) => T)(prev)
          : next;
      },
    ] as const;
  },
}));

const { searchTasksMock } = vi.hoisted(() => ({
  searchTasksMock: vi.fn(),
}));

vi.mock('@/lib/ipc/tasks/queries', () => ({
  searchTasks: searchTasksMock,
}));

import { useTaskDetailRelationSearch } from './useTaskDetailRelationSearch';

function useRenderHook() {
  stateCursor = 0;
  refCursor = 0;
  effectCursor = 0;
  return useTaskDetailRelationSearch({ excludeIds: [] });
}

function resetHarness() {
  stateSlots.length = 0;
  refSlots.length = 0;
  for (const effect of effectSlots) {
    effect.cleanup?.();
  }
  effectSlots.length = 0;
  stateCursor = 0;
  refCursor = 0;
  effectCursor = 0;
}

describe('useTaskDetailRelationSearch', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    searchTasksMock.mockReset();
    resetHarness();
  });

  afterEach(() => {
    resetHarness();
    vi.useRealTimers();
  });

  it('clears loading when a short query cancels an in-flight search', async () => {
    searchTasksMock.mockReturnValue(new Promise(() => {}));
    let hook = useRenderHook();

    hook.setQuery('ab');
    hook = useRenderHook();
    vi.advanceTimersByTime(250);
    await Promise.resolve();
    hook = useRenderHook();

    expect(hook.loading).toBe(true);

    hook.setQuery('a');
    hook = useRenderHook();
    hook = useRenderHook();

    expect(hook.loading).toBe(false);
    expect(hook.results).toEqual([]);
  });
});
