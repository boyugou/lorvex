import { beforeEach, describe, expect, it, vi } from 'vitest';

const stateSlots: Array<{ value: unknown; setter: (next: unknown) => void }> = [];
const memoSlots: Array<{ deps: readonly unknown[] | undefined; value: unknown }> = [];
const effectSlots: Array<{
  cleanup: void | (() => void);
  deps: readonly unknown[] | undefined;
  effect: (() => void | (() => void)) | null;
  pending: boolean;
}> = [];
let stateCursor = 0;
let memoCursor = 0;
let effectCursor = 0;

function depsEqual(left: readonly unknown[] | undefined, right: readonly unknown[] | undefined): boolean {
  if (left === undefined || right === undefined) return false;
  if (left.length !== right.length) return false;
  return left.every((value, index) => Object.is(value, right[index]));
}

vi.mock('react', () => ({
  useState: <T>(initial: T | (() => T)) => {
    const index = stateCursor++;
    if (index >= stateSlots.length) {
      const value = typeof initial === 'function' ? (initial as () => T)() : initial;
      stateSlots.push({
        value,
        setter: (next) => {
          const previous = stateSlots[index]!.value;
          stateSlots[index]!.value = typeof next === 'function'
            ? (next as (previousValue: unknown) => unknown)(previous)
            : next;
        },
      });
    }
    const slot = stateSlots[index]!;
    return [slot.value, slot.setter] as const;
  },
  useMemo: <T>(factory: () => T, deps?: readonly unknown[]) => {
    const index = memoCursor++;
    const previous = memoSlots[index];
    if (previous && depsEqual(previous.deps, deps)) {
      return previous.value as T;
    }
    const value = factory();
    memoSlots[index] = { deps, value };
    return value;
  },
  useCallback: <T extends (...args: never[]) => unknown>(callback: T, deps?: readonly unknown[]) => {
    const index = memoCursor++;
    const previous = memoSlots[index];
    if (previous && depsEqual(previous.deps, deps)) {
      return previous.value as T;
    }
    memoSlots[index] = { deps, value: callback };
    return callback;
  },
  useEffect: (effect: () => void | (() => void), deps?: readonly unknown[]) => {
    const index = effectCursor++;
    const previous = effectSlots[index];
    if (previous && depsEqual(previous.deps, deps)) {
      effectSlots[index] = previous;
      return;
    }
    effectSlots[index] = {
      cleanup: previous?.cleanup,
      deps,
      effect,
      pending: true,
    };
  },
}));

import type { Task } from '@/lib/ipc/tasks/models';
import { useTaskFilters } from './useTaskFilters';

function render<T>(hook: () => T): T {
  stateCursor = 0;
  memoCursor = 0;
  effectCursor = 0;
  const result = hook();
  for (const slot of effectSlots) {
    if (!slot.pending || !slot.effect) continue;
    if (typeof slot.cleanup === 'function') slot.cleanup();
    slot.cleanup = slot.effect();
    slot.pending = false;
  }
  return result;
}

function reset() {
  stateSlots.length = 0;
  memoSlots.length = 0;
  effectSlots.length = 0;
  stateCursor = 0;
  memoCursor = 0;
  effectCursor = 0;
}

const tasks = [
  { id: 'task-1', tags: ['deep-work', 'focus'] },
] as unknown as Task[];

describe('useTaskFilters persistence dependencies', () => {
  beforeEach(() => {
    vi.unstubAllGlobals();
    reset();
  });

  it('keeps persisted filter identities stable across fresh equal descriptors', () => {
    const first = render(() => useTaskFilters(tasks, {
      filterListIdKey: 'allTasks.filterListId',
      selectedTagsKey: 'allTasks.selectedTags',
    }));
    const second = render(() => useTaskFilters(tasks, {
      filterListIdKey: 'allTasks.filterListId',
      selectedTagsKey: 'allTasks.selectedTags',
    }));

    expect(second.selectedTags).toBe(first.selectedTags);
    expect(second.setFilterListId).toBe(first.setFilterListId);
    expect(second.toggleTag).toBe(first.toggleTag);
    expect(second.clearTagFilter).toBe(first.clearTagFilter);
    expect(second.replaceSelectedTags).toBe(first.replaceSelectedTags);
  });

  it('preserves persisted selected tags through an initial empty cold-load task snapshot', () => {
    const values = new Map<string, string>([
      ['lorvex:allTasks.selectedTags', JSON.stringify(['focus'])],
    ]);
    vi.stubGlobal('localStorage', {
      getItem: vi.fn((key: string) => values.get(key) ?? null),
      setItem: vi.fn((key: string, value: string) => {
        values.set(key, value);
      }),
      removeItem: vi.fn((key: string) => {
        values.delete(key);
      }),
    });
    const persistence = {
      filterListIdKey: 'allTasks.filterListId',
      selectedTagsKey: 'allTasks.selectedTags',
    };

    const cold = render(() => useTaskFilters([], persistence));
    expect([...cold.selectedTags]).toEqual(['focus']);
    expect(values.get('lorvex:allTasks.selectedTags')).toBe(JSON.stringify(['focus']));

    const loaded = render(() => useTaskFilters(tasks, persistence));
    expect([...loaded.selectedTags]).toEqual(['focus']);
    expect(loaded.allTags).toEqual(['deep-work', 'focus']);
    expect(values.get('lorvex:allTasks.selectedTags')).toBe(JSON.stringify(['focus']));
  });
});
