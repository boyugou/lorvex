import type { QueryClient } from '@tanstack/react-query';
import { QUERY_KEYS } from '@/lib/query/queryKeys';

export function shouldKeepCachedListEntry(item: unknown, deletedListId: string): boolean {
  if (typeof item !== 'object' || item === null || Array.isArray(item)) return true;
  const descriptor = Object.getOwnPropertyDescriptor(item, 'id');
  const id = descriptor && 'value' in descriptor ? descriptor.value : undefined;
  return id !== deletedListId;
}

/**
 * drop a deleted list from the cache: filter the lists
 * collection query and remove the per-list cache entry. Both the
 * sidebar context-menu delete and the list-view header delete
 * (and its NotFound recovery branch) must run this same eviction
 * before invalidating downstream surfaces, so it lives here as a
 * shared helper rather than three near-identical inline blocks.
 *
 * The caller is still responsible for the cross-surface
 * invalidations (today, task collections) since those vary by
 * call site.
 */
export function evictDeletedListFromCache(qc: QueryClient, listId: string): void {
  qc.setQueryData(QUERY_KEYS.lists(), (previous: unknown) => {
    if (!Array.isArray(previous)) return previous;
    return previous.filter((item) => shouldKeepCachedListEntry(item, listId));
  });
  qc.removeQueries({ queryKey: QUERY_KEYS.list(listId) });
}
