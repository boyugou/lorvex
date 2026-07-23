import type { QueryClient } from '@tanstack/react-query';

import type { SavedQuery, SavedQueryViewType } from '@/lib/ipc/savedQueries';
import { QUERY_KEYS } from '../query/queryKeys';
import { STALE_DEFAULT } from '../query/timing';

type SavedQueriesKey = ReturnType<typeof QUERY_KEYS.savedQueries>;

export function savedQueriesKey(viewType: SavedQueryViewType): SavedQueriesKey {
  return QUERY_KEYS.savedQueries(viewType);
}

type ListSavedQueriesFn = (
  viewType: SavedQueryViewType,
  signal?: AbortSignal,
) => Promise<SavedQuery[]>;

export function createSavedQueriesListQueryOptions(
  viewType: SavedQueryViewType,
  listFn: ListSavedQueriesFn,
) {
  return {
    queryKey: savedQueriesKey(viewType),
    queryFn: ({ signal }: { signal: AbortSignal }) => listFn(viewType, signal),
    staleTime: STALE_DEFAULT,
  };
}

export function invalidateSavedQueries(
  queryClient: QueryClient,
  viewType: SavedQueryViewType,
): void {
  void queryClient.invalidateQueries({ queryKey: savedQueriesKey(viewType) });
}
