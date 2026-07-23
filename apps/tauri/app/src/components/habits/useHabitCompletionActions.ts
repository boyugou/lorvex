import { useRef, useState } from 'react';

import { useMutation, useQueryClient } from '@tanstack/react-query';
import { adjustHabitCompletion } from '@/lib/ipc/habits';
import type { HabitSummary, HabitWithStats } from '@/lib/ipc/habits';
import { reportClientError } from '@/lib/errors/errorLogging';
import {
  applyOptimisticEntityPatch,
  rollbackOptimisticEntityPatch,
  type OptimisticEntityConfig,
  type OptimisticEntitySnapshot,
} from '@/lib/query/optimisticEntity';
import { invalidateHabitQueries } from '@/lib/query/queryKeys';
import { QK } from '@/lib/query/queryKeyHeads';
import { toast } from '@/lib/notifications/toast';

function buildToggledTodayCount(completionsToday: number, targetCount: number): number {
  const wasDone = completionsToday >= targetCount;
  return wasDone ? 0 : targetCount;
}

function looksLikeHabitSummary(value: unknown): value is HabitSummary {
  return (
    !!value &&
    typeof value === 'object' &&
    'id' in (value as Record<string, unknown>) &&
    'completions_today' in (value as Record<string, unknown>) &&
    'target_count' in (value as Record<string, unknown>)
  );
}

function looksLikeHabitWithStats(value: unknown): value is HabitWithStats {
  // Distinguishes from HabitSummary by a stats-only field. The cache
  // separates the two by query head, so this guard is belt-and-braces
  // protection against a future test fixture using the wrong type.
  return (
    !!value &&
    typeof value === 'object' &&
    'id' in (value as Record<string, unknown>) &&
    'completions_today' in (value as Record<string, unknown>) &&
    'recent_completion_dates' in (value as Record<string, unknown>)
  );
}

const HABIT_SUMMARY_CONFIG: OptimisticEntityConfig<HabitSummary> = {
  queryHeads: new Set<string>([QK.todaysHabits]),
  looksLikeEntity: looksLikeHabitSummary,
};

const HABIT_WITH_STATS_CONFIG: OptimisticEntityConfig<HabitWithStats> = {
  queryHeads: new Set<string>([QK.habitsWithStats]),
  looksLikeEntity: looksLikeHabitWithStats,
};

// ---------------------------------------------------------------------------
// Shared mutation skeleton
// ---------------------------------------------------------------------------

interface UseHabitCompletionCollectionActionsArgs<E extends { id: string; completions_today: number; target_count: number }> {
  errorMessage: string;
  config: OptimisticEntityConfig<E>;
  /**
   * Compute the `completions_today` patch for a single habit given a
   * delta (`0` = toggle to-done, `>0` / `<0` = relative bump).
   */
  buildPatch: (habit: E, delta: number) => Partial<E>;
  /**
   * Apply server-confirmed fields onto the patched habit. Called from
   * `onSuccess` to align the optimistic state with the authoritative
   * server response without disturbing fields the response doesn't
   * carry.
   */
  serverPatch: (habit: E, server: HabitSummary) => Partial<E>;
}

function useHabitCompletionCollectionActions<
  E extends { id: string; completions_today: number; target_count: number },
>({
  errorMessage,
  config,
  buildPatch,
  serverPatch,
}: UseHabitCompletionCollectionActionsArgs<E>) {
  const queryClient = useQueryClient();
  // Track which habits currently have an in-flight adjustment so we
  // can gate per-habit double-taps without dropping cross-habit taps.
  // The shared `mutation.isPending` would silently no-op tapping habit
  // B while habit A is still in flight.
  const [pendingHabits, setPendingHabits] = useState<ReadonlySet<string>>(() => new Set());
  const pendingHabitsRef = useRef<Set<string>>(new Set());

  const markPending = (habitId: string) => {
    pendingHabitsRef.current = new Set(pendingHabitsRef.current).add(habitId);
    setPendingHabits(pendingHabitsRef.current);
  };
  const clearPending = (habitId: string) => {
    if (!pendingHabitsRef.current.has(habitId)) return;
    const next = new Set(pendingHabitsRef.current);
    next.delete(habitId);
    pendingHabitsRef.current = next;
    setPendingHabits(next);
  };

  const mutation = useMutation({
    mutationFn: ({ habitId, delta }: { habitId: string; delta: number }) =>
      adjustHabitCompletion(habitId, delta),
    onMutate: async ({ habitId, delta }) => {
      // Read the current habit out of any cache entry under the
      // configured heads so we can compute the patch from the live
      // value rather than relying on `current` from `setQueryData`.
      // The generic helper applies the same patch object across every
      // matching cache entry — so the caller computes the patch from
      // ONE entity instance and the helper handles the fan-out.
      let sourceHabit: E | null = null;
      const cache = queryClient.getQueryCache();
      for (const query of cache.getAll()) {
        const key = query.queryKey;
        if (!Array.isArray(key) || key.length === 0) continue;
        const head = key[0];
        if (typeof head !== 'string' || !config.queryHeads.has(head)) continue;
        const data = query.state.data;
        if (Array.isArray(data)) {
          for (const item of data) {
            if (config.looksLikeEntity(item) && item.id === habitId) {
              sourceHabit = item;
              break;
            }
          }
        } else if (config.looksLikeEntity(data) && data.id === habitId) {
          sourceHabit = data;
        }
        if (sourceHabit) break;
      }
      if (!sourceHabit) return { snapshot: null as OptimisticEntitySnapshot<E> | null };
      const patch = buildPatch(sourceHabit, delta);
      const snapshot = await applyOptimisticEntityPatch(queryClient, config, habitId, patch);
      return { snapshot };
    },
    onError: (error, variables, context) => {
      if (context?.snapshot) {
        rollbackOptimisticEntityPatch(queryClient, config, context.snapshot);
      }
      clearPending(variables.habitId);
      reportClientError('toggle_habit_completion', 'Failed to toggle habit', error);
      toast.errorWithDetail(error, errorMessage);
    },
    onSuccess: (updated, variables) => {
      // Apply the authoritative server response on top of the
      // optimistic state. We don't roll back the optimistic snapshot
      // because the server response IS the new ground truth — the
      // subsequent `invalidateHabitQueries` will refetch the stats
      // fields the response doesn't carry.
      void applyOptimisticEntityPatch(
        queryClient,
        config,
        updated.id,
        // We don't have a direct `E`; pull the current cached habit
        // out and feed it through `serverPatch` to compute the patch
        // shape. If the habit is gone (refetch already ran), the
        // sweep is a no-op.
        ((): Partial<E> => {
          const cache = queryClient.getQueryCache();
          for (const query of cache.getAll()) {
            const key = query.queryKey;
            if (!Array.isArray(key) || key.length === 0) continue;
            const head = key[0];
            if (typeof head !== 'string' || !config.queryHeads.has(head)) continue;
            const data = query.state.data;
            const candidates = Array.isArray(data) ? data : [data];
            for (const item of candidates) {
              if (config.looksLikeEntity(item) && item.id === updated.id) {
                return serverPatch(item, updated);
              }
            }
          }
          return {};
        })(),
      );
      clearPending(variables.habitId);
      invalidateHabitQueries(queryClient);
    },
    // No `onSettled` invalidation: the success path already writes the
    // authoritative server result and invalidates, and the error path
    // rolls the optimistic update back per-field. A settle-time
    // invalidation would schedule a refetch that overwrites the
    // freshly-applied server data, producing a one-frame flicker on a
    // fast tap-double-tap.
  });

  return {
    adjustHabit: (habitId: string, delta: number) => {
      // Per-habit gating: still drop a same-habit double-tap (the
      // optimistic state already reflects the pending change), but
      // allow taps on a different habit while another is in flight.
      if (pendingHabitsRef.current.has(habitId)) return;
      markPending(habitId);
      mutation.mutate({ habitId, delta });
    },
    isPendingForHabit: (habitId: string) => pendingHabits.has(habitId),
  };
}

export function useHabitStatsCompletionActions(errorMessage: string) {
  return useHabitCompletionCollectionActions<HabitWithStats>({
    errorMessage,
    config: HABIT_WITH_STATS_CONFIG,
    buildPatch: (habit, delta) => {
      const next =
        delta === 0
          ? buildToggledTodayCount(habit.completions_today, habit.target_count)
          : Math.max(0, Math.min(habit.target_count, habit.completions_today + delta));
      // Only patch the field we can derive locally without ambiguity.
      // `total_completions` / `completions_last_30` are sums of
      // `value` across history; clamping `completions_today` makes
      // the delta we apply to those aggregates wrong (over-tap clamps
      // locally but the server's authoritative aggregate would not
      // move). The post-success invalidation refetches authoritative
      // stats. `recent_completion_dates` is also recomputed there.
      return { completions_today: next };
    },
    serverPatch: (_habit, server) => ({
      // Trust server fields we have authoritative values for and let
      // `invalidateHabitQueries` (in onSuccess) refetch the stats
      // fields we cannot derive from the IPC return (:
      // total_completions / completions_last_30 drift;:
      // recent_completion_dates would otherwise be erased for
      // accumulative habits since the local recompute used
      // target_count gating that misrepresents accumulative cadences).
      completions_today: server.completions_today,
      current_streak: server.current_streak,
    }),
  });
}

export function useTodayHabitCompletionActions(errorMessage: string) {
  return useHabitCompletionCollectionActions<HabitSummary>({
    errorMessage,
    config: HABIT_SUMMARY_CONFIG,
    buildPatch: (habit, delta) => {
      const next =
        delta === 0
          ? buildToggledTodayCount(habit.completions_today, habit.target_count)
          : Math.max(0, Math.min(habit.target_count, habit.completions_today + delta));
      return { completions_today: next };
    },
    serverPatch: (_habit, server) => ({
      // For the today summary the IPC `HabitSummary` IS the canonical
      // shape — every field on `server` is authoritative.
      ...server,
    }),
  });
}
