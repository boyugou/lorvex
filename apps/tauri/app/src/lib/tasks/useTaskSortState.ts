import { useCallback, useState } from 'react';
import type { SortDirection, SortKey } from './taskSorting';
import { SORT_KEYS } from './taskSorting';
import { getUIStateString, setUIState } from '../storage/uiState';

/** Options for configuring the sort state hook. */
interface UseTaskSortStateOptions {
  /**
   * Canonical prefixed-key stem used with the `lorvex:` helpers.
   * e.g. `'allTasks.'` -> stored as `lorvex:allTasks.sortKey`.
   *
   * If omitted, sort state is in-memory only (not persisted).
   */
  storagePrefix?: string | undefined;
  /** Default sort key. Defaults to 'default'. */
  defaultSortKey?: SortKey | undefined;
  /** Default sort direction. Defaults to 'asc'. */
  defaultSortDirection?: SortDirection | undefined;
}

function readStoredSortKey(prefix: string | undefined, fallback: SortKey): SortKey {
  if (!prefix) return fallback;
  const v = getUIStateString(prefix + 'sortKey', '');
  if (v && (SORT_KEYS as readonly string[]).includes(v)) return v as SortKey;
  return fallback;
}

function readStoredSortDirection(prefix: string | undefined, fallback: SortDirection): SortDirection {
  if (!prefix) return fallback;
  const v = getUIStateString(prefix + 'sortDirection', '');
  if (v === 'asc' || v === 'desc') return v;
  return fallback;
}

function writePref(prefix: string | undefined, key: string, value: string): void {
  if (!prefix) return;
  setUIState(prefix + key, value);
}

/**
 * Manages sort key and direction state, with optional localStorage persistence.
 * Used by AllTasksView (with persistence) and ListView (without).
 */
export function useTaskSortState(options: UseTaskSortStateOptions = {}) {
  const { storagePrefix, defaultSortKey = 'default', defaultSortDirection = 'asc' } = options;

  const [sortKey, setSortKeyRaw] = useState<SortKey>(
    () => readStoredSortKey(storagePrefix, defaultSortKey),
  );
  const [sortDirection, setSortDirectionRaw] = useState<SortDirection>(
    () => readStoredSortDirection(storagePrefix, defaultSortDirection),
  );

  const setSortKey = useCallback((v: SortKey) => {
    setSortKeyRaw(v);
    writePref(storagePrefix, 'sortKey', v);
  }, [storagePrefix]);

  const setSortDirection = useCallback((v: SortDirection) => {
    setSortDirectionRaw(v);
    writePref(storagePrefix, 'sortDirection', v);
  }, [storagePrefix]);

  const toggleSortDirection = useCallback(() => {
    setSortDirectionRaw((prev) => {
      const next = prev === 'asc' ? 'desc' : 'asc';
      writePref(storagePrefix, 'sortDirection', next);
      return next;
    });
  }, [storagePrefix]);

  return {
    sortKey,
    setSortKey,
    sortDirection,
    setSortDirection,
    toggleSortDirection,
  };
}
