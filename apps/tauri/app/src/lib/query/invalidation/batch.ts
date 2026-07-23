import type { QueryClient } from '@tanstack/react-query';

import { QUERY_KEYS } from '../queryKeyFactory';
import { QUERY_KEY_HEAD_SET, type QueryKeyHead } from '../queryKeyHeads';

// ---------------------------------------------------------------------------
// Batched invalidation
// ---------------------------------------------------------------------------
// Each `invalidateQueries({ queryKey: [head] })` call walks the full query
// cache.  When we need to invalidate N key-heads, doing N walks is wasteful.
// `invalidateByKeyHeadSet` collapses them into a single cache traversal using
// a predicate that matches against a pre-built Set.
// For very small sets (<=2) the overhead of a predicate function outweighs the
// savings, so we fall back to per-key calls.
// ---------------------------------------------------------------------------

export function invalidateKeyHeads(queryClient: QueryClient, keyHeads: readonly QueryKeyHead[]): void {
  if (keyHeads.length <= 2) {
    for (const keyHead of keyHeads) {
      void queryClient.invalidateQueries({ queryKey: QUERY_KEYS.head(keyHead) });
    }
    return;
  }
  invalidateByKeyHeadSet(queryClient, new Set(keyHeads));
}

export function invalidateByKeyHeadSet(queryClient: QueryClient, keyHeadSet: Set<QueryKeyHead>): void {
  void queryClient.invalidateQueries({
    predicate: (query) => {
      const head = query.queryKey[0];
      return (
        typeof head === 'string'
        && QUERY_KEY_HEAD_SET.has(head)
        && keyHeadSet.has(head as QueryKeyHead)
      );
    },
  });
}

export function queryHeadList(...heads: readonly QueryKeyHead[]): readonly QueryKeyHead[] {
  return Object.freeze([...new Set(heads)]);
}
