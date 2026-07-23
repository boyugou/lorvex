/**
 * Optimistic entity patch helper.
 *
 * High-frequency UX mutations (status flip, priority pill, planned-date
 * drag, habit completion tap, …) routinely produce a visible flash:
 * the cache holds the pre-mutation entity, the IPC round-trips, and
 * only after invalidation+refetch does the UI catch up. This is most
 * painful on views where the same entity appears in multiple list
 * queries simultaneously.
 *
 * Rather than thread bespoke optimistic updates through every call
 * site, this helper sweeps the TanStack Query cache for any entry
 * whose data is `E` or `E[]` and patches the matching entity in place.
 *
 * # Per-entity configuration
 *
 * The helper is generic over the entity type `E`. A call site supplies
 * an `OptimisticEntityConfig<E>` describing:
 *
 * - `queryHeads` — the closed set of `QK.*` heads whose cache entries
 *   may carry `E` or `E[]`. Restricting the sweep to a fixed head list
 *   prevents accidental matches on unrelated cache entries that happen
 *   to contain objects with a colliding `id`.
 * - `looksLikeEntity` — runtime guard. Any object that passes the
 *   guard AND has the matching `id` is treated as the entity.
 * - `singleEntityCacheRemoval` — opt-in. When `true`, the
 *   `removeFromCacheIf` predicate is applied to single-entity cache
 *   entries (`['<head>', id]`) as well as list-shape entries. Defaults
 *   to `false`: for entities like Task whose detail view IS a single
 *   cache entry, removing it would erase the canonical detail surface;
 *   for ephemeral entities the opt-in lets the predicate sweep
 *   everything cleanly.
 *
 * # Rollback semantics — per-field, never whole-array (,)
 *
 * Earlier revisions snapshotted the full prior cache value (the entire
 * `E[]` or `E` object) and `setQueryData`'d it back wholesale on
 * rollback. That silently clobbered any concurrent in-flight optimistic
 * mutation that landed between snapshot and rollback — drag B's
 * optimistic patch on a different entity could be reverted because
 * drag A's snapshot still held the pre-B array.
 *
 * The helper now records, for every query entry it touches, the
 * **previous values of the specific fields** the patch overwrote on
 * the source entity. Rollback re-applies that field-level snapshot
 * only to the source entity — every other entity in the array, and
 * every other field on the same entity, stays at whatever value the
 * cache holds at rollback time.
 *
 * # Why a hand-written sweep instead of `defineEntityHooks` config
 *
 * Tasks live in many list-shaped queries with no single canonical
 * "list" key (`todayPoolTasks`, `upcomingTasks(todayYmd, days)`,
 * `calendarTasks(from, to)`, weekly-review variants, …) plus the
 * single `task(id)` cache. The factory's `optimistic` projection is
 * scoped to a single query key, so it can't cover a fan-out write
 * cleanly. Sweeping by id keeps the same patch correct everywhere
 * the cache holds the entity, with no per-call-site key wiring.
 */

import type { QueryClient, QueryKey } from '@tanstack/react-query';

import type { Task } from '@/lib/ipc/tasks/models';

import { QUERY_KEYS } from './queryKeyFactory';
import { QK } from './queryKeyHeads';

/** Minimum surface every patchable entity exposes — id-based addressing. */
export interface IdentifiableEntity {
  id: string;
}

/** A patch produced by an optimistic projection. */
export type EntityPatch<E> = Partial<E>;

/**
 * Per-(queryKey, entityId) snapshot of the original field values the
 * patch overwrote, captured at apply time and consumed by rollback to
 * re-apply field-level undo without disturbing concurrent in-flight
 * mutations.
 */
export interface OptimisticEntitySnapshot<E> {
  entityId: string;
  /** Names of fields the patch overwrote (drives rollback re-apply). */
  patchedFields: readonly (keyof E)[];
  /** Per-queryKey snapshot of the previous entity field values. */
  entries: Array<{
    key: QueryKey;
    /** Subset of the source entity — only the fields the patch overwrote. */
    previousFields: Partial<E>;
    /** Whether the cache entry was a single entity (vs. an array). */
    singleEntity: boolean;
    /**
     * If the entry was a list and the entity was removed by the
     * `removeFromCacheIf` predicate, the index it lived at and the
     * complete prior entity value so rollback can re-insert it.
     * `null` when no removal happened.
     */
    removed?: { index: number; previousEntity: E } | null;
  }>;
}

/**
 * Optional behavior knobs for `applyOptimisticEntityPatch`.
 *
 * `removeFromCacheIf` handles the
 * "patch moves entity out of cached window" case: views that group by
 * a derived key (e.g. `taskEffectiveActionDate`, habit completion
 * bucket) cannot re-bucket an entity whose new derived value falls
 * outside their window, so the entity lingers in its old slot with
 * stale-looking data until the refetch lands. When the predicate
 * returns `true` for the patched entity, the helper removes it from
 * every list-shape cache entry. Single-entity cache entries are
 * removed only when the call-site config opts in via
 * `singleEntityCacheRemoval`.
 */
export interface ApplyOptimisticEntityPatchOptions<E> {
  removeFromCacheIf?: (entity: E, queryKey: QueryKey) => boolean;
}

/**
 * Per-entity-type configuration. A single instance is built per entity
 * surface (Task, Habit, …) and reused across every call site.
 */
export interface OptimisticEntityConfig<E extends IdentifiableEntity> {
  /** Closed set of `QK.*` heads whose data shape is `E | E[]`. */
  queryHeads: ReadonlySet<string>;
  /** Runtime guard for the entity. */
  looksLikeEntity: (value: unknown) => value is E;
  /**
   * When `true`, `removeFromCacheIf` is applied to single-entity
   * cache entries as well. Defaults to `false`. See class doc.
   */
  singleEntityCacheRemoval?: boolean;
}

/**
 * Capture the prior values of `patch`'s keys from `entity`, returning
 * a `Partial<E>` containing exactly those keys. Skips keys absent
 * from `entity`'s own properties so rollback never writes an
 * explicit `undefined` onto a field that the source object did not
 * carry — `Object.assign({}, entity, { foo: undefined })` would
 * otherwise zero a field that a concurrent patch had set.
 */
function captureFields<E>(entity: E, patch: EntityPatch<E>): Partial<E> {
  const previous: Partial<E> = {};
  const source = entity as unknown as Record<string, unknown>;
  for (const key of Object.keys(patch) as (keyof E)[]) {
    const stringKey = key as string;
    // Only capture keys actually present on the source. Missing keys
    // would otherwise be recorded as `undefined`, which on rollback
    // becomes an explicit `field: undefined` overwrite — silently
    // erasing a value a concurrent patch had set.
    if (!(stringKey in source)) continue;
    (previous as Record<string, unknown>)[stringKey] = source[stringKey];
  }
  return previous;
}

function queryHeadKey(head: string): QueryKey {
  return QUERY_KEYS.head(head as Parameters<typeof QUERY_KEYS.head>[0]);
}

/**
 * Apply `patch` to every cache entry under the configured heads where
 * an entity with id `entityId` is found. Cancels in-flight queries for
 * those heads first so a stale refetch can't overwrite the optimistic
 * value.
 */
export async function applyOptimisticEntityPatch<E extends IdentifiableEntity>(
  qc: QueryClient,
  config: OptimisticEntityConfig<E>,
  entityId: string,
  patch: EntityPatch<E>,
  options: ApplyOptimisticEntityPatchOptions<E> = {},
): Promise<OptimisticEntitySnapshot<E>> {
  await Promise.all(
    Array.from(config.queryHeads).map((head) =>
      qc.cancelQueries({ queryKey: queryHeadKey(head) }),
    ),
  );

  const patchedFields = Object.keys(patch) as (keyof E)[];
  const snapshot: OptimisticEntitySnapshot<E> = {
    entityId,
    patchedFields,
    entries: [],
  };
  const cache = qc.getQueryCache();
  for (const query of cache.getAll()) {
    const key = query.queryKey;
    if (!Array.isArray(key) || key.length === 0) continue;
    const head = key[0];
    if (typeof head !== 'string' || !config.queryHeads.has(head)) continue;
    const data = query.state.data;
    if (data === undefined || data === null) continue;

    if (Array.isArray(data)) {
      let touched = false;
      let previousFields: Partial<E> | null = null;
      let removed: { index: number; previousEntity: E } | null = null;
      const next: unknown[] = [];
      for (let i = 0; i < data.length; i++) {
        const item = data[i];
        if (config.looksLikeEntity(item) && item.id === entityId) {
          if (!touched) {
            previousFields = captureFields(item, patch);
            touched = true;
          }
          const patched = { ...item, ...patch } as E;
          if (
            options.removeFromCacheIf &&
            options.removeFromCacheIf(patched, key) &&
            removed === null
          ) {
            removed = { index: i, previousEntity: item };
            continue;
          }
          next.push(patched);
        } else {
          next.push(item);
        }
      }
      if (touched && previousFields) {
        snapshot.entries.push({
          key,
          previousFields,
          singleEntity: false,
          removed,
        });
        qc.setQueryData(key, next);
      }
    } else if (config.looksLikeEntity(data) && data.id === entityId) {
      const previousFields = captureFields(data, patch);
      const patched = { ...data, ...patch } as E;
      // by default the single-entity cache entry stays put
      // (it's the canonical detail surface). Call sites whose
      // single-entity cache should also drop the entity when the
      // predicate matches opt in via `singleEntityCacheRemoval`.
      if (
        config.singleEntityCacheRemoval &&
        options.removeFromCacheIf &&
        options.removeFromCacheIf(patched, key)
      ) {
        snapshot.entries.push({
          key,
          previousFields,
          singleEntity: true,
          removed: { index: 0, previousEntity: data },
        });
        // `setQueryData(key, undefined)` is a no-op in TanStack Query
        // (the cache treats `undefined` as "leave alone"). Use
        // `removeQueries` to actually drop the entry, then rely on the
        // rollback path to re-seed it via `setQueryData` if needed.
        const exactQueryKey = [...key];
        qc.removeQueries({ queryKey: exactQueryKey, exact: true });
      } else {
        snapshot.entries.push({
          key,
          previousFields,
          singleEntity: true,
        });
        qc.setQueryData(key, patched);
      }
    }
  }
  return snapshot;
}

/**
 * Re-apply the captured field values onto the source entity in every
 * cache entry the original patch touched. Concurrent in-flight
 * mutations on other entities (or on disjoint fields of the same
 * entity) are not disturbed because rollback only writes the
 * snapshot's keys and only on the matching entity id.
 */
export function rollbackOptimisticEntityPatch<E extends IdentifiableEntity>(
  qc: QueryClient,
  config: OptimisticEntityConfig<E>,
  snapshot: OptimisticEntitySnapshot<E>,
): void {
  const { entityId } = snapshot;

  for (const entry of snapshot.entries) {
    if (entry.singleEntity) {
      qc.setQueryData(entry.key, (current: unknown) => {
        // Single-entity-removal rollback: if apply set the
        // entry to `undefined`, restore the prior entity value.
        if (entry.removed && current === undefined) {
          return entry.removed.previousEntity;
        }
        if (!config.looksLikeEntity(current) || current.id !== entityId) {
          return current;
        }
        return { ...current, ...entry.previousFields };
      });
    } else {
      qc.setQueryData(entry.key, (current: unknown) => {
        if (!Array.isArray(current)) return current;
        if (entry.removed) {
          const alreadyPresent = current.some(
            (item) => config.looksLikeEntity(item) && item.id === entityId,
          );
          if (alreadyPresent) {
            return current.map((item) => {
              if (config.looksLikeEntity(item) && item.id === entityId) {
                return { ...item, ...entry.previousFields };
              }
              return item;
            });
          }
          const insertAt = Math.min(entry.removed.index, current.length);
          const next = current.slice();
          next.splice(insertAt, 0, entry.removed.previousEntity);
          return next;
        }
        let mutated = false;
        const next = current.map((item) => {
          if (config.looksLikeEntity(item) && item.id === entityId) {
            mutated = true;
            return { ...item, ...entry.previousFields };
          }
          return item;
        });
        return mutated ? next : current;
      });
    }
  }
}

// ---------------------------------------------------------------------------
// Task-typed wrappers
// ---------------------------------------------------------------------------
//
// Tasks are the original consumer of this helper. The wrappers below
// preserve the original `Task`-typed call signatures so existing call
// sites need only swap the import path / type names — no per-call
// generic arg threading.

/** Heads whose data shape is `Task | Task[]`. */
const TASK_QUERY_HEADS = new Set<string>([
  QK.task,
  QK.allTasks,
  QK.todayPoolTasks,
  QK.todayOverdueTasks,
  QK.somedayTasks,
  QK.recurringTasks,
  QK.upcomingTasks,
  QK.upcomingWeekTasks,
  QK.calendarTasks,
  QK.weeklyReview,
  QK.weeklyReviewUpcoming,
  QK.search,
  QK.tasksBlockedBy,
]);

function looksLikeTask(value: unknown): value is Task {
  return (
    !!value &&
    typeof value === 'object' &&
    'id' in (value as Record<string, unknown>) &&
    'status' in (value as Record<string, unknown>) &&
    'list_id' in (value as Record<string, unknown>)
  );
}

const TASK_OPTIMISTIC_CONFIG: OptimisticEntityConfig<Task> = {
  queryHeads: TASK_QUERY_HEADS,
  looksLikeEntity: looksLikeTask,
  // Tasks' single-entity cache (`['task', id]`) is the canonical
  // detail surface — keep the patched value there even when the
  // list-removal predicate fires. Opt-out by omission.
  singleEntityCacheRemoval: false,
};

export type TaskPatch = EntityPatch<Task>;
export type OptimisticTaskSnapshot = OptimisticEntitySnapshot<Task>;
export type ApplyOptimisticTaskPatchOptions = ApplyOptimisticEntityPatchOptions<Task>;

export function applyOptimisticTaskPatch(
  qc: QueryClient,
  taskId: string,
  patch: TaskPatch,
  options: ApplyOptimisticTaskPatchOptions = {},
): Promise<OptimisticTaskSnapshot> {
  return applyOptimisticEntityPatch(qc, TASK_OPTIMISTIC_CONFIG, taskId, patch, options);
}

export function rollbackOptimisticTaskPatch(
  qc: QueryClient,
  snapshot: OptimisticTaskSnapshot,
): void {
  rollbackOptimisticEntityPatch(qc, TASK_OPTIMISTIC_CONFIG, snapshot);
}
