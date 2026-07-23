import assert from 'node:assert/strict';
import test from 'node:test';

import { QueryClient } from '@tanstack/react-query';

import type { SavedQuery } from '../../../app/src/lib/ipc/savedQueries';
import {
  createSavedQueriesListQueryOptions,
  invalidateSavedQueries,
  savedQueriesKey,
} from '../../../app/src/lib/hooks/useSavedQueries.logic';
import { STALE_DEFAULT } from '../../../app/src/lib/query/timing';

function savedQuery(overrides: Partial<SavedQuery> = {}): SavedQuery {
  return {
    id: 'query-1',
    view_type: 'AllTasks',
    name: 'Focus today',
    filter_json: '{"tags":["focus"]}',
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    ...overrides,
  };
}

test('saved queries key scopes cache entries by view type', () => {
  assert.deepEqual(savedQueriesKey('AllTasks'), ['saved-queries', 'AllTasks']);
  assert.deepEqual(savedQueriesKey('Kanban'), ['saved-queries', 'Kanban']);
});

test('saved queries list query options forward the view type, abort signal, and stale window', async () => {
  const calls: Array<{ viewType: string; signal: AbortSignal }> = [];
  const expected = [savedQuery()];
  const options = createSavedQueriesListQueryOptions('Upcoming', async (viewType, signal) => {
    calls.push({ viewType, signal: signal! });
    return expected;
  });
  const abortController = new AbortController();

  assert.deepEqual(options.queryKey, ['saved-queries', 'Upcoming']);
  assert.equal(options.staleTime, STALE_DEFAULT);
  assert.deepEqual(
    await options.queryFn({ signal: abortController.signal }),
    expected,
  );
  assert.equal(calls.length, 1);
  assert.equal(calls[0]?.viewType, 'Upcoming');
  assert.equal(calls[0]?.signal, abortController.signal);
});

test('invalidateSavedQueries invalidates only the matching view cache slot', async () => {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false, gcTime: Infinity } },
  });

  queryClient.setQueryData(savedQueriesKey('AllTasks'), [savedQuery()]);
  queryClient.setQueryData(savedQueriesKey('Kanban'), [savedQuery({ id: 'query-2', view_type: 'Kanban' })]);

  assert.equal(queryClient.getQueryState(savedQueriesKey('AllTasks'))?.isInvalidated, false);
  assert.equal(queryClient.getQueryState(savedQueriesKey('Kanban'))?.isInvalidated, false);

  invalidateSavedQueries(queryClient, 'AllTasks');

  await Promise.resolve();
  assert.equal(queryClient.getQueryState(savedQueriesKey('AllTasks'))?.isInvalidated, true);
  assert.equal(queryClient.getQueryState(savedQueriesKey('Kanban'))?.isInvalidated, false);
});
