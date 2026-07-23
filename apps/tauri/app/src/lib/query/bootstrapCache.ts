import type { QueryClient } from '@tanstack/react-query';

import type { TodayBootstrap } from '@/lib/ipc/bootstrap';
import {
  PREF_DASHBOARD_LAYOUT,
  PREF_SIDEBAR_HIDE_EMPTY_LISTS,
  PREF_SIDEBAR_VISIBLE_MODULES,
  PREF_TIMEZONE,
} from '../preferences/keys';

import { setPreferenceQueryData, setPreferenceQueryDefaults } from './preferenceCache';
import { QUERY_KEYS } from './queryKeyFactory';
import { QK, type QueryKeyHead } from './queryKeyHeads';
import { TODAY_SURFACE_REFETCH_MS } from './timing';

export const BOOTSTRAP_SEEDED_QUERY_HEADS = Object.freeze([
  QK.overview,
  QK.lists,
  QK.currentFocus,
  QK.setupStatus,
] as const satisfies readonly QueryKeyHead[]);

export const BOOTSTRAP_SEEDED_PREFERENCE_KEYS = Object.freeze([
  PREF_TIMEZONE,
  PREF_SIDEBAR_VISIBLE_MODULES,
  PREF_SIDEBAR_HIDE_EMPTY_LISTS,
  PREF_DASHBOARD_LAYOUT,
] as const);

export function seedTodayBootstrapQueryData(
  queryClient: QueryClient,
  bootstrap: TodayBootstrap,
  staleTime: number = TODAY_SURFACE_REFETCH_MS,
): void {
  const seedHead = (head: QueryKeyHead, data: unknown) => {
    queryClient.setQueryDefaults(QUERY_KEYS.head(head), { staleTime });
    queryClient.setQueryData(QUERY_KEYS.head(head), data);
  };

  seedHead(QK.overview, bootstrap.overview);
  seedHead(QK.lists, bootstrap.lists);
  seedHead(QK.currentFocus, bootstrap.current_focus);
  seedHead(QK.setupStatus, bootstrap.setup_status);

  setPreferenceQueryDefaults(queryClient, { staleTime });
  for (const key of BOOTSTRAP_SEEDED_PREFERENCE_KEYS) {
    setPreferenceQueryData(queryClient, key, bootstrap.preferences[key] ?? null);
  }
}
