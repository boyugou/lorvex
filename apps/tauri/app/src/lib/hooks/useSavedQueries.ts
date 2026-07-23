/**
 * React hook around the saved-query IPC surface.
 *
 * Each list-shaped view (AllTasks, Someday, Upcoming, Kanban,
 * Eisenhower) owns a small piece of filter UI state. This hook
 * lets the view persist a snapshot of that state under a named
 * preset, list all presets for the view, load one back into its
 * filter state, and delete one — using the standard TanStack
 * Query cache so every mount of `<SavedQueriesMenu>` across the
 * app stays coherent when any of them mutates.
 *
 * The `filter_json` payload is entirely view-owned: each view
 * passes its own `serialize` / `deserialize` pair, so this hook
 * stays generic.
 */

import { useCallback } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import { deleteSavedQuery, listSavedQueries, loadSavedQuery, saveQuery } from '@/lib/ipc/savedQueries';
import type { SavedQuery, SavedQueryViewType } from '@/lib/ipc/savedQueries';
import {
  createSavedQueriesListQueryOptions,
  invalidateSavedQueries,
} from './useSavedQueries.logic';

interface UseSavedQueriesResult {
  /** Ordered, case-insensitive by name. */
  savedQueries: SavedQuery[];
  isLoading: boolean;
  isSaving: boolean;
  isDeleting: boolean;
  /** Upsert by (viewType, name). Re-saving an existing name overwrites in place. */
  save: (name: string, filterJson: string) => Promise<SavedQuery>;
  /** Fetch one preset's blob — caller feeds it into its `deserialize`. */
  load: (id: string) => Promise<SavedQuery | null>;
  remove: (id: string) => Promise<void>;
}

export function useSavedQueries(viewType: SavedQueryViewType): UseSavedQueriesResult {
  const queryClient = useQueryClient();

  const { data = [], isLoading } = useQuery(
    createSavedQueriesListQueryOptions(viewType, listSavedQueries),
  );

  const invalidate = useCallback(() => {
    invalidateSavedQueries(queryClient, viewType);
  }, [queryClient, viewType]);

  const saveMutation = useMutation({
    mutationFn: ({ name, filterJson }: { name: string; filterJson: string }) =>
      saveQuery(viewType, name, filterJson),
    onSuccess: () => invalidate(),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteSavedQuery(id),
    onSuccess: () => invalidate(),
  });

  const save = useCallback(
    (name: string, filterJson: string) =>
      saveMutation.mutateAsync({ name, filterJson }),
    [saveMutation],
  );

  const load = useCallback((id: string) => loadSavedQuery(id), []);
  const remove = useCallback(
    (id: string) => deleteMutation.mutateAsync(id),
    [deleteMutation],
  );

  return {
    savedQueries: data,
    isLoading,
    isSaving: saveMutation.isPending,
    isDeleting: deleteMutation.isPending,
    save,
    load,
    remove,
  };
}
