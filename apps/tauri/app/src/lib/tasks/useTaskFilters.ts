import { useCallback, useMemo, useState } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import { parseTags } from '../format';
import type { PriorityFilterValue } from './priorityFilter';
import {
  isStringArray,
  isStringOrNull,
  useLocalStorageBackedState,
} from '../storage/useLocalStorageBackedState';

/** Shared filter parameters accepted by `applyTaskFilters`. */
interface TaskFilterParams {
  /** Filter to tasks belonging to a specific list. */
  listId?: string | null;
  /** Filter to tasks with a specific priority value. */
  priority?: PriorityFilterValue;
  /** Filter to tasks that have at least one of the given tags. */
  tags?: Set<string>;
  /** Case-insensitive substring search across title and body (and optionally tags). */
  search?: string;
  /** When true, the search query also matches against raw tag strings. */
  searchTags?: boolean;
}

/**
 * Pure function that applies the standard task filter combo (list, priority, tags, search).
 * Controllers can call this directly inside `useMemo` and layer additional domain-specific
 * filters on top.
 */
export function applyTaskFilters(tasks: Task[], filters: TaskFilterParams): Task[] {
  let result = tasks;

  if (filters.listId) {
    result = result.filter((task) => task.list_id === filters.listId);
  }
  if (filters.priority != null) {
    result = result.filter((task) => task.priority === filters.priority);
  }
  if (filters.tags && filters.tags.size > 0) {
    const tagSet = filters.tags;
    result = result.filter((task) => {
      const taskTags = parseTags(task.tags);
      return taskTags.some((tag) => tagSet.has(tag));
    });
  }
  if (filters.search) {
    const q = filters.search.trim().toLowerCase();
    if (q) {
      result = result.filter((task) => {
        const haystack = filters.searchTags
          ? `${task.title} ${task.body ?? ''} ${task.tags ?? ''}`.toLowerCase()
          : `${task.title} ${task.body ?? ''}`.toLowerCase();
        return haystack.includes(q);
      });
    }
  }

  return result;
}

export function replaceSelectedTaskFilterTags(tags: Iterable<string>): Set<string> {
  return new Set(tags);
}

export function pruneSelectedTaskFilterTags(
  selectedTags: Set<string>,
  availableTags: readonly string[],
): Set<string> {
  if (selectedTags.size === 0) {
    return selectedTags;
  }

  const availableTagSet = new Set(availableTags);
  const next = new Set<string>();
  for (const tag of selectedTags) {
    if (availableTagSet.has(tag)) {
      next.add(tag);
    }
  }

  return next.size === selectedTags.size ? selectedTags : next;
}

interface UseTaskFiltersPersistence {
  /** localStorage key for `filterListId`. Stored as a JSON string or null. */
  filterListIdKey: string;
  /** localStorage key for `selectedTags`. Stored as a JSON `string[]`. */
  selectedTagsKey: string;
}

const UNUSED_TASK_FILTER_LIST_ID_KEY = '__task-filter-unused-list-id__';
const UNUSED_TASK_FILTER_SELECTED_TAGS_KEY = '__task-filter-unused-selected-tags__';

interface ResolvedTaskFiltersPersistence {
  hasPersistence: boolean;
  filterListIdKey: string;
  selectedTagsKey: string;
}

export function resolveTaskFiltersPersistence(
  persistence?: UseTaskFiltersPersistence,
): ResolvedTaskFiltersPersistence {
  return {
    hasPersistence: persistence !== undefined,
    filterListIdKey: persistence?.filterListIdKey ?? UNUSED_TASK_FILTER_LIST_ID_KEY,
    selectedTagsKey: persistence?.selectedTagsKey ?? UNUSED_TASK_FILTER_SELECTED_TAGS_KEY,
  };
}

function sortedStringSetValues(values: ReadonlySet<string>): string[] {
  return [...values].sort();
}

function stringArraysEqual(left: readonly string[], right: readonly string[]): boolean {
  if (left.length !== right.length) return false;
  return left.every((value, index) => value === right[index]);
}

export function selectedTaskFilterTagsPersistenceArray(
  previous: string[],
  nextTags: ReadonlySet<string>,
): string[] {
  const nextArray = sortedStringSetValues(nextTags);
  return stringArraysEqual(previous, nextArray) ? previous : nextArray;
}

/**
 * when `persistence` is supplied, the filter pills
 * round-trip through `localStorage` so a refresh / window-reopen
 * doesn't silently drop the user's filters. Omit `persistence` to keep
 * the legacy in-memory-only behavior — used by transient surfaces
 * (focus-mode picker, etc.) where stored filters would feel stale.
 */
export function useTaskFilters(tasks: Task[], persistence?: UseTaskFiltersPersistence) {
  const {
    hasPersistence,
    filterListIdKey,
    selectedTagsKey,
  } = resolveTaskFiltersPersistence(persistence);
  const [filterListIdLocal, setFilterListIdLocal] = useState<string | null>(null);
  const [selectedTagsLocal, setSelectedTagsLocal] = useState<Set<string>>(new Set());

  const [filterListIdPersisted, setFilterListIdPersisted] = useLocalStorageBackedState<string | null>(
    filterListIdKey,
    null,
    isStringOrNull,
  );
  const [selectedTagsArrayPersisted, setSelectedTagsArrayPersisted] = useLocalStorageBackedState<string[]>(
    selectedTagsKey,
    [],
    isStringArray,
  );

  const filterListId = hasPersistence ? filterListIdPersisted : filterListIdLocal;
  const setFilterListId = hasPersistence ? setFilterListIdPersisted : setFilterListIdLocal;

  const persistedTagsSet = useMemo(
    () => (hasPersistence ? new Set(selectedTagsArrayPersisted) : null),
    [hasPersistence, selectedTagsArrayPersisted],
  );
  const selectedTags = persistedTagsSet ?? selectedTagsLocal;
  const setSelectedTags = useCallback(
    (next: React.SetStateAction<Set<string>>) => {
      if (hasPersistence) {
        setSelectedTagsArrayPersisted((prev) => {
          const prevSet = new Set(prev);
          const nextSet =
            typeof next === 'function' ? (next as (p: Set<string>) => Set<string>)(prevSet) : next;
          return selectedTaskFilterTagsPersistenceArray(prev, nextSet);
        });
      } else {
        setSelectedTagsLocal(next);
      }
    },
    [hasPersistence, setSelectedTagsArrayPersisted],
  );

  const toggleTag = useCallback((tag: string) => {
    setSelectedTags((prev) => {
      const next = new Set(prev);
      if (next.has(tag)) next.delete(tag);
      else next.add(tag);
      return next;
    });
  }, [setSelectedTags]);

  const clearTagFilter = useCallback(() => setSelectedTags(new Set()), [setSelectedTags]);

  const allTags = useMemo(() => {
    const tagSet = new Set<string>();
    for (const task of tasks) {
      for (const tag of parseTags(task.tags)) tagSet.add(tag);
    }
    return [...tagSet].sort();
  }, [tasks]);

  const replaceSelectedTags = useCallback((tags: Iterable<string>) => {
    setSelectedTags(replaceSelectedTaskFilterTags(tags));
  }, [setSelectedTags]);

  return {
    filterListId,
    setFilterListId,
    selectedTags,
    toggleTag,
    clearTagFilter,
    replaceSelectedTags,
    allTags,
  };
}
