import { useEffect } from 'react';
import { keepPreviousData, useQuery, useQueryClient } from '@tanstack/react-query';
import { getTodayBootstrap } from '@/lib/ipc/bootstrap';
import type { TodayBootstrap } from '@/lib/ipc/bootstrap';
import type { Overview } from '@/lib/ipc/tasks/models';
import { seedTodayBootstrapQueryData } from '@/lib/query/bootstrapCache';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { TODAY_SURFACE_REFETCH_MS } from '@/lib/query/timing';

import type { ListsData } from './types';

interface MainWindowQueryState {
  isOverviewError: boolean;
  lists: ListsData;
  overview: Overview | null;
  refetchOverview: () => void;
}

export function useMainWindowQueries(): MainWindowQueryState {
  const queryClient = useQueryClient();

  const {
    data: bootstrap,
    isError: isOverviewError,
    refetch: refetchBootstrap,
  } = useQuery<TodayBootstrap>({
    queryKey: QUERY_KEYS.todayBootstrap(),
    queryFn: ({ signal }) => getTodayBootstrap(signal),
    refetchInterval: TODAY_SURFACE_REFETCH_MS,
    placeholderData: keepPreviousData,
  });

  // Seed the per-field query caches from the bootstrap. Descendant
  // hooks (`useQuery({ queryKey: QUERY_KEYS.overview() })`, per-preference
  // queries, the setup-status query, current-focus) read the seeded
  // data synchronously on mount instead of firing their own IPC.
  //
  // TanStack Query v5 detail: `setQueryData` populates the cache
  // but does NOT automatically mark the entry non-stale. With the
  // default `staleTime: 0`, a descendant `useQuery` would read the
  // seeded cache AND immediately fire a background refetch —
  // defeating the point of the bootstrap. We therefore also attach
  // `setQueryDefaults` to each seeded key head, bumping its staleTime
  // to the same window used for the bootstrap refetch. Views that
  // want fresher data can still call `queryClient.invalidateQueries`
  // or pass an explicit `staleTime` override on their own useQuery.
  useEffect(() => {
    if (!bootstrap) return;

    seedTodayBootstrapQueryData(queryClient, bootstrap);
  }, [bootstrap, queryClient]);

  const lists = bootstrap?.lists ?? [];

  return {
    isOverviewError,
    lists,
    overview: bootstrap?.overview ?? null,
    refetchOverview: () => { void refetchBootstrap(); },
  };
}
