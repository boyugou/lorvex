import type { QueryClient } from '@tanstack/react-query';

import { QUERY_KEYS } from './queryKeyFactory';
import { QK } from './queryKeyHeads';

export type PreferenceQueryKey = readonly [typeof QK.preference, string];
type PreferenceQueryRootKey = readonly [typeof QK.preference];
type PreferenceRawCacheValue = string | null;

export function preferenceQueryKey(key: string): PreferenceQueryKey {
  return QUERY_KEYS.preference(key);
}

export function preferenceQueryRootKey(): PreferenceQueryRootKey {
  return QUERY_KEYS.preferenceRoot();
}

export function setPreferenceQueryData(
  queryClient: QueryClient,
  key: string,
  value: PreferenceRawCacheValue,
): void {
  queryClient.setQueryData(preferenceQueryKey(key), value);
}

export function getPreferenceQueryData(
  queryClient: QueryClient,
  key: string,
): PreferenceRawCacheValue | undefined {
  return queryClient.getQueryData<PreferenceRawCacheValue>(preferenceQueryKey(key));
}

export function setPreferenceQueryDefaults(
  queryClient: QueryClient,
  options: Parameters<QueryClient['setQueryDefaults']>[1],
): void {
  queryClient.setQueryDefaults(preferenceQueryRootKey(), options);
}
