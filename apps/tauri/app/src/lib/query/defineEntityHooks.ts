/**
 * defineEntityHooks — typed bundle factory for entity read/write hooks.
 *
 * # Why this exists
 *
 * Across the app, the same `useQuery` / `useMutation` boilerplate is
 * repeated per entity:
 *
 *   const q = useQuery({
 *     queryKey: QUERY_KEYS.X(args),
 *     queryFn: ({ signal }) => ipcCall(args, signal),
 *     staleTime: STALE_DEFAULT,
 *   });
 *
 *   const m = useMutation({
 *     mutationFn: (input) => ipcWrite(input),
 *     onSuccess: () => {
 *       // toast.success(...);
 *       invalidateQueriesForEntity(qc, 'X');
 *     },
 *     onError: (e) => {
 *       reportClientError('create_x', 'failed', e);
 *       // toast.errorWithDetail(e, '...');
 *     },
 *   });
 *
 * `defineEntityHooks` collapses this into a single declarative bundle
 * that wires:
 *   - typed query keys via `QUERY_KEYS`
 *   - auto invalidation on mutation success via
 *     `invalidateQueriesForEntity(QUERY_ENTITY_INVALIDATION_MAP)`
 *   - error → toast + `reportClientError` surfacing
 *   - optional `onSuccess` / `onError` per call-site
 *
 * # Usage
 *
 *   import { defineEntityHooks } from '@/lib/query/defineEntityHooks';
 *   import { QUERY_KEYS } from '@/lib/query/queryKeys';
 *   import * as memoryIpc from '@/lib/ipc/memory';
 *
 *   export const memoryHooks = defineEntityHooks({
 *     entity: 'memory',
 *     queries: {
 *       all: {
 *         key: () => QUERY_KEYS.aiMemory(),
 *         fetch: (signal) => memoryIpc.getAiMemory(signal),
 *       },
 *     },
 *     mutations: {
 *       create: {
 *         run: (input: { key: string; content: string }) =>
 *           memoryIpc.createMemoryEntry(input.key, input.content),
 *         errorContext: 'create_memory_entry',
 *       },
 *     },
 *   });
 *
 *   // In a component:
 *   const { data } = memoryHooks.queries.all.useQuery();
 *   const create = memoryHooks.mutations.create.useMutation({
 *     successMessage: t('memory.entryCreated'), // any literal i18n key
 *     errorMessage: t('common.error'),
 *   });
 *
 * # Migration playbook
 *
 *   1. Identify the target entity. The entity name MUST match a key in
 *      `QUERY_ENTITY_INVALIDATION_MAP` (`task`, `list`, `habit`, `memory`,
 *      `calendar_event`, …) so auto-invalidation is wired correctly.
 *   2. Enumerate the read queries the components use. Build a `queries`
 *      map; each entry pairs a `QUERY_KEYS.*` factory with the matching
 *      IPC fetcher. Use the existing `staleTime` constant from
 *      `query/timing` if needed (override per call-site).
 *   3. Enumerate the IPC writes. Build a `mutations` map; each entry
 *      pairs the `ipc` function with an `errorContext` slug used by
 *      `reportClientError`. Components pass `successMessage` /
 *      `errorMessage` (already i18n'd) at call-time.
 *   4. Replace inline `useQuery` / `useMutation` blocks at the call
 *      sites. The factory handles the toast + invalidation; per-site
 *      `onSuccess` callbacks still run after invalidation.
 *   5. Verify: `npm run -w app typecheck && npm run -w app test:unit`.
 *
 * # When NOT to use this
 *
 *   - Cursor-paginated lists with placeholder/keepPreviousData semantics
 *     and complex effect dependencies — those are easier to keep inline.
 *   - Mutations with optimistic `onMutate` snapshot/rollback that depend
 *     on multiple cache reads. The factory exposes a passthrough
 *     `onMutate` for simple cases, but fully-fledged optimistic cache
 *     surgery is still clearer inline.
 *   - One-off queries used by a single component, where the indirection
 *     adds noise without dedup benefit.
 */

import {
  useMutation,
  useQuery,
  useQueryClient,
  type QueryClient,
  type UseMutationOptions,
  type UseMutationResult,
  type UseQueryOptions,
  type UseQueryResult,
} from '@tanstack/react-query';

import { reportClientError } from '../errors/errorLogging';
import { toast } from '../notifications/toast';
import { invalidateQueriesForEntity } from './invalidation';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/**
 * Entity names recognised by the invalidation map. Mirrors the keys of
 * `QUERY_ENTITY_INVALIDATION_MAP` (`app/src/lib/query/invalidation/entityMap.ts`).
 * Curated as a literal union here because the runtime map is typed as
 * `Record<string, ...>` and can't drive a narrow `keyof` lookup.
 *
 * The `queryKeys.test.ts` registry test guarantees every entity used in
 * the map is wired; if you add a new entity to the map, also add it
 * here so `defineEntityHooks` can target it.
 */
export type EntityName =
  | 'task'
  | 'list'
  | 'calendar_event'
  | 'calendar_subscription'
  | 'task_calendar_event_link'
  | 'task_tag'
  | 'task_dependency'
  | 'task_checklist_item'
  | 'habit'
  | 'habit_completion'
  | 'tag'
  | 'daily_review'
  | 'current_focus'
  | 'focus_schedule'
  | 'preference'
  | 'memory'
  | 'memory_revision'
  | 'task_reminder'
  | 'habit_reminder_policy'
  | 'ai_changelog'
  | 'changelog'
  | 'ai_memory'
  | 'data_import'
  | 'planning';

/** A query definition: key factory + IPC fetcher.
 *
 *  The `fetch` signature is `[...TArgs, signal?: AbortSignal]` — the
 *  call-site args (matching `key`) followed by an *optional* trailing
 *  AbortSignal. Optional trailing tuple slots accommodate the IPC
 *  wrappers in `lib/ipc/*` that declare the signal as `signal?:
 *  AbortSignal`. The factory always passes the signal explicitly at
 *  call time. Narrow typing here means call-site type errors (wrong
 *  arg arity / shape) are caught instead of being swallowed by `any[]`.
 */
export interface EntityQueryDef<TArgs extends readonly unknown[], TData> {
  /** Builds the canonical query key. Must come from `QUERY_KEYS.*`. */
  key: (...args: TArgs) => readonly unknown[];
  /** IPC fetcher. Receives the call-site args plus an AbortSignal. */
  fetch: (...args: [...TArgs, signal?: AbortSignal]) => Promise<TData>;
  /** Default `staleTime` if the call-site doesn't override. */
  staleTime?: number;
}

/** A mutation definition: IPC writer + reporting context. */
export interface EntityMutationDef<TInput, TOutput> {
  /** IPC writer. */
  run: (input: TInput) => Promise<TOutput>;
  /**
   * Slug used by `reportClientError` (e.g. `'create_task'`). Should be
   * stable; logs in the unseen-error panel group on this string.
   */
  errorContext: string;
}

// `any` constraints below are required for variance: a concrete
// `EntityMutationDef<{ key: string }, void>` is NOT assignable to a
// constraint of `EntityMutationDef<unknown, unknown>` (function param
// contravariance). `any` makes the constraint bivariant, while the
// per-entry generic inference (`infer TInput, infer TOutput`) still
// narrows to the precise types in the returned bundle.

/** Bundle config for `defineEntityHooks`. */
export interface EntityHooksConfig<
  TQueries extends Record<string, EntityQueryDef<any, any>>,
  TMutations extends Record<string, EntityMutationDef<any, any>>,
> {
  entity: EntityName;
  queries?: TQueries;
  mutations?: TMutations;
}

/** Per-call-site options on `useMutation`. */
interface UseEntityMutationOptions<TInput, TOutput, TContext = unknown>
  extends Omit<
    UseMutationOptions<TOutput, Error, TInput, TContext>,
    'mutationFn' | 'onSuccess' | 'onError'
  > {
  /** Toast message on success. Omitted → no toast. */
  successMessage?: string;
  /** Toast message on error (fallback if the error has no detail). */
  errorMessage?: string;
  /** Optional post-invalidation callback. Receives the IPC return value. */
  onSuccess?: (data: TOutput, input: TInput, ctx: TContext | undefined) => void;
  /** Optional error callback. Runs AFTER `reportClientError` + toast. */
  onError?: (error: Error, input: TInput, ctx: TContext | undefined) => void;
  /** Override the default entity invalidation. Pass `false` to skip. */
  invalidateEntity?: EntityName | false;
}

// Per-call-site options on `useQuery` (everything TanStack accepts,
// minus the parts the factory owns).
export type UseEntityQueryOptions<TData> = Omit<
  UseQueryOptions<TData, Error, TData, readonly unknown[]>,
  'queryKey' | 'queryFn'
>;

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

/** Helper hook-bundle types — inferred via factory return type. */
interface EntityQueryHook<TArgs extends readonly unknown[], TData> {
  useQuery: (
    args: TArgs,
    options?: UseEntityQueryOptions<TData>,
  ) => UseQueryResult<TData, Error>;
  /** Imperative variant: build the canonical key without subscribing. */
  key: (...args: TArgs) => readonly unknown[];
}

interface EntityMutationHook<TInput, TOutput> {
  useMutation: (
    options?: UseEntityMutationOptions<TInput, TOutput>,
  ) => UseMutationResult<TOutput, Error, TInput, unknown>;
}

type QueryHooksOf<TQueries> = {
  [K in keyof TQueries]: TQueries[K] extends EntityQueryDef<infer TArgs, infer TData>
    ? EntityQueryHook<TArgs, TData>
    : never;
};

type MutationHooksOf<TMutations> = {
  [K in keyof TMutations]: TMutations[K] extends EntityMutationDef<infer TInput, infer TOutput>
    ? EntityMutationHook<TInput, TOutput>
    : never;
};

export interface EntityHooksBundle<
  TQueries extends Record<string, EntityQueryDef<any, any>>,
  TMutations extends Record<string, EntityMutationDef<any, any>>,
> {
  entity: EntityName;
  queries: QueryHooksOf<TQueries>;
  mutations: MutationHooksOf<TMutations>;
}

export function defineEntityHooks<
  TQueries extends Record<string, EntityQueryDef<any, any>>,
  TMutations extends Record<string, EntityMutationDef<any, any>>,
>(
  config: EntityHooksConfig<TQueries, TMutations>,
): EntityHooksBundle<TQueries, TMutations> {
  const queryHooks: Record<string, EntityQueryHook<readonly unknown[], unknown>> = {};
  const mutationHooks: Record<string, EntityMutationHook<unknown, unknown>> = {};

  if (config.queries) {
    for (const [name, def] of Object.entries(config.queries)) {
      queryHooks[name] = buildQueryHook(def as EntityQueryDef<readonly unknown[], unknown>);
    }
  }
  if (config.mutations) {
    for (const [name, def] of Object.entries(config.mutations)) {
      mutationHooks[name] = buildMutationHook(
        config.entity,
        def as EntityMutationDef<unknown, unknown>,
      );
    }
  }

  return {
    entity: config.entity,
    queries: queryHooks as QueryHooksOf<TQueries>,
    mutations: mutationHooks as MutationHooksOf<TMutations>,
  };
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

function buildQueryHook<TArgs extends readonly unknown[], TData>(
  def: EntityQueryDef<TArgs, TData>,
): EntityQueryHook<TArgs, TData> {
  return {
    key: def.key,
    useQuery(args: TArgs, options?: UseEntityQueryOptions<TData>) {
      return useQuery<TData, Error, TData, readonly unknown[]>(
        buildEntityQueryConfig(def, args, options),
      );
    },
  };
}

/**
 * Pure config builder used by `useQuery`. Exported so unit tests can
 * verify the queryKey + queryFn wiring without a React renderer.
 */
export function buildEntityQueryConfig<TArgs extends readonly unknown[], TData>(
  def: EntityQueryDef<TArgs, TData>,
  args: TArgs,
  options?: UseEntityQueryOptions<TData>,
): UseQueryOptions<TData, Error, TData, readonly unknown[]> {
  const queryKey = def.key(...args);
  return {
    queryKey,
    queryFn: ({ signal }) =>
      // Spread the call-site args followed by the signal. The IPC
      // wrapper functions in `lib/ipc/*` always accept `signal` as
      // the trailing argument.
      def.fetch(...args, signal),
    ...(def.staleTime !== undefined ? { staleTime: def.staleTime } : {}),
    ...options,
  };
}

function buildMutationHook<TInput, TOutput>(
  entity: EntityName,
  def: EntityMutationDef<TInput, TOutput>,
): EntityMutationHook<TInput, TOutput> {
  return {
    useMutation(options?: UseEntityMutationOptions<TInput, TOutput>) {
      const queryClient = useQueryClient();
      const {
        successMessage,
        errorMessage,
        onSuccess: onSuccessOverride,
        onError: onErrorOverride,
        invalidateEntity,
        ...rest
      } = options ?? {};
      return useMutation<TOutput, Error, TInput, unknown>({
        mutationFn: (input: TInput) => def.run(input),
        onSuccess: (data, input, ctx) => {
          handleMutationSuccess(queryClient, {
            entity,
            invalidateEntity,
            successMessage,
          });
          onSuccessOverride?.(data, input, ctx);
        },
        onError: (error, input, ctx) => {
          handleMutationError(error, def.errorContext, errorMessage);
          onErrorOverride?.(error, input, ctx);
        },
        ...rest,
      });
    },
  };
}

/**
 * Side-effect runner used on mutation success. Exported so unit tests
 * can drive it without a React renderer.
 */
export function handleMutationSuccess(
  queryClient: QueryClient,
  args: {
    entity: EntityName;
    invalidateEntity: EntityName | false | undefined;
    successMessage: string | undefined;
  },
): void {
  const target =
    args.invalidateEntity === false
      ? null
      : (args.invalidateEntity ?? args.entity);
  if (target) invalidateQueriesForEntity(queryClient, target);
  if (args.successMessage) toast.success(args.successMessage);
}

/**
 * Side-effect runner used on mutation error. Exported for unit tests.
 */
export function handleMutationError(
  error: Error,
  errorContext: string,
  errorMessage: string | undefined,
): void {
  reportClientError(errorContext, error.message ?? 'Mutation failed', error);
  if (errorMessage) toast.errorWithDetail(error, errorMessage);
}
