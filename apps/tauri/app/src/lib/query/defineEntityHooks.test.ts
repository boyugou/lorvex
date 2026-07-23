import { QueryClient } from '@tanstack/react-query';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { resetClientErrorLogDedupeForTests, setAppendErrorLogForTests } from '../errors/errorLogging';

import {
  buildEntityQueryConfig,
  defineEntityHooks,
  handleMutationError,
  handleMutationSuccess,
  type EntityQueryDef,
} from './defineEntityHooks';
import { QUERY_KEYS } from './queryKeyFactory';
import { QK } from './queryKeyHeads';

// ---------------------------------------------------------------------------
// Mock toast — replaced via dynamic import boundary by stubbing the
// underlying module. The factory imports `../toast`, so we vi.mock it.
// ---------------------------------------------------------------------------

vi.mock('../notifications/toast', () => ({
  toast: {
    success: vi.fn(),
    errorWithDetail: vi.fn(),
    error: vi.fn(),
    info: vi.fn(),
  },
}));

import { toast } from '../notifications/toast';

beforeEach(() => {
  vi.clearAllMocks();
  resetClientErrorLogDedupeForTests();
  // Make `reportClientError` a no-op against the IPC channel — the
  // factory should still call into it, just don't blow up the
  // suppressed-output path.
  setAppendErrorLogForTests(async () => undefined);
});

afterEach(() => {
  setAppendErrorLogForTests(null);
});

describe('defineEntityHooks — buildEntityQueryConfig', () => {
  it('produces a query config bound to the canonical query key', () => {
    const fetch = vi.fn(async (_id: string, _signal?: AbortSignal) => ({ id: '1' }));
    const def: EntityQueryDef<readonly [string], { id: string }> = {
      key: (id) => QUERY_KEYS.task(id),
      fetch,
    };

    const config = buildEntityQueryConfig(def, ['task-1'] as const);
    expect(config.queryKey).toEqual([QK.task, 'task-1']);
  });

  it('forwards the AbortSignal through to the IPC fetcher', async () => {
    const fetch = vi.fn(async (_id: string, _signal?: AbortSignal) => ({ id: '1' }));
    const def: EntityQueryDef<readonly [string], { id: string }> = {
      key: (id) => QUERY_KEYS.task(id),
      fetch,
    };

    const config = buildEntityQueryConfig(def, ['task-1'] as const);
    const controller = new AbortController();
    const queryFn = config.queryFn as (ctx: { signal: AbortSignal }) => Promise<unknown>;
    await queryFn({ signal: controller.signal });
    expect(fetch).toHaveBeenCalledWith('task-1', controller.signal);
  });

  it('applies default staleTime when set, and overrides win', () => {
    const def: EntityQueryDef<readonly [], string[]> = {
      key: () => QUERY_KEYS.lists(),
      fetch: async () => [],
      staleTime: 30_000,
    };
    expect(buildEntityQueryConfig(def, [] as const).staleTime).toBe(30_000);
    expect(
      buildEntityQueryConfig(def, [] as const, { staleTime: 5_000 }).staleTime,
    ).toBe(5_000);
  });
});

describe('defineEntityHooks — handleMutationSuccess', () => {
  it('invalidates the entity by default and emits the success toast', () => {
    const queryClient = new QueryClient();
    const spy = vi.spyOn(queryClient, 'invalidateQueries');

    handleMutationSuccess(queryClient, {
      entity: 'memory',
      invalidateEntity: undefined,
      successMessage: 'Saved',
    });

    expect(spy).toHaveBeenCalled();
    expect(toast.success).toHaveBeenCalledWith('Saved');
  });

  it('skips invalidation when invalidateEntity === false', () => {
    const queryClient = new QueryClient();
    const spy = vi.spyOn(queryClient, 'invalidateQueries');

    handleMutationSuccess(queryClient, {
      entity: 'task',
      invalidateEntity: false,
      successMessage: undefined,
    });

    expect(spy).not.toHaveBeenCalled();
    expect(toast.success).not.toHaveBeenCalled();
  });

  it('honours an explicit invalidateEntity override', () => {
    const queryClient = new QueryClient();
    const spy = vi.spyOn(queryClient, 'invalidateQueries');

    handleMutationSuccess(queryClient, {
      entity: 'memory',
      invalidateEntity: 'memory_revision',
      successMessage: undefined,
    });

    // Two heads from QUERY_ENTITY_INVALIDATION_MAP.memory_revision: aiMemory + memoryHistory.
    expect(spy).toHaveBeenCalled();
  });
});

describe('defineEntityHooks — handleMutationError', () => {
  it('forwards to toast.errorWithDetail when an errorMessage is supplied', () => {
    const err = new Error('boom');
    handleMutationError(err, 'create_task', 'Could not save');
    expect(toast.errorWithDetail).toHaveBeenCalledWith(err, 'Could not save');
  });

  it('omits the toast when no errorMessage is supplied', () => {
    handleMutationError(new Error('silent'), 'create_task', undefined);
    expect(toast.errorWithDetail).not.toHaveBeenCalled();
  });
});

describe('defineEntityHooks — bundle shape', () => {
  it('exposes one query hook + key per query def, and one mutation hook per mutation def', () => {
    const bundle = defineEntityHooks({
      entity: 'memory',
      queries: {
        all: {
          key: () => QUERY_KEYS.aiMemory(),
          fetch: async () => [] as unknown[],
        },
      },
      mutations: {
        remove: {
          run: async (_input: { key: string }) => {},
          errorContext: 'memory_test',
        },
      },
    });

    expect(bundle.entity).toBe('memory');
    expect(typeof bundle.queries.all.useQuery).toBe('function');
    expect(bundle.queries.all.key()).toEqual([QK.aiMemory]);
    expect(typeof bundle.mutations.remove.useMutation).toBe('function');
  });
});
