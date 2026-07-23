import { useEffect, useState, type DragEvent, type KeyboardEvent } from 'react';
import { useQueryClient } from '@tanstack/react-query';

import { reorderCurrentFocusOpenTasks } from '@/lib/ipc/tasks/mutations/focus';
import type { TranslationKey } from '@/lib/i18n';
import { applyCompactDragImage } from '@/lib/dragImage';
import { defineEntityHooks } from '@/lib/query/defineEntityHooks';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { useMounted } from '@/lib/useMounted';
import { moveTaskId } from './taskOrdering';

/**
 * Focus-pool reorder routed through `defineEntityHooks` with
 * `entity: 'current_focus'`, which expands to every today-surface
 * head (overview, currentFocus, focusSchedule, todayEvents,
 * todayPoolTasks, todayOverdueTasks, todayBootstrap) per
 * `QUERY_ENTITY_INVALIDATION_MAP['current_focus']`.
 *
 * Bespoke surface: the `onSuccess` callback seeds the
 * `QK.currentFocus` cache with the IPC return so the optimistic order
 * survives across the bootstrap refetch ( race-4 fix below),
 * and `onError` rolls the local component state back to the
 * server-truth `planOpenTaskIds`. The factory owns invalidation +
 * `reportClientError`; the local-state rollback is intrinsic to the
 * drag UX and can't move into the factory.
 */
const focusReorderHooks = defineEntityHooks({
  entity: 'current_focus',
  mutations: {
    reorder: {
      run: (openTaskIds: string[]) => reorderCurrentFocusOpenTasks(openTaskIds),
      errorContext: 'today.reorderFocus',
    },
  },
});

interface UseFocusReorderActionsArgs {
  planOpenTaskIds: string[];
  t: (key: TranslationKey) => string;
}

export function useFocusReorderActions({
  planOpenTaskIds,
  t,
}: UseFocusReorderActionsArgs) {
  const queryClient = useQueryClient();
  const mountedRef = useMounted();
  const [openOrder, setOpenOrder] = useState<string[]>([]);
  const [draggingId, setDraggingId] = useState<string | null>(null);
  const [dragOverId, setDragOverId] = useState<string | null>(null);

  const persistReorder = focusReorderHooks.mutations.reorder.useMutation({
    errorMessage: t('common.error'),
    onSuccess: (updatedPlan) => {
      // Seed the currentFocus cache so the freshly persisted order
      // survives the bootstrap refetch the entity invalidation
      // triggers. `setQueryData` doesn't itself invalidate, so the
      // entity invalidation (which already ran by the time this
      // override fires) drives the canonical reseed via
      // `useMainWindowQueries` — but having the seed in place first
      // means the in-flight refetch can't surface a one-frame stale
      // order to the renderer.
      queryClient.setQueryData(QUERY_KEYS.currentFocus(), updatedPlan);
    },
    onError: () => {
      if (mountedRef.current) {
        setOpenOrder(planOpenTaskIds);
      }
    },
  });

  // race 4: only sync from props when no reorder mutation is
  // pending. Otherwise an unrelated peer data-changed event can refetch
  // overview between the optimistic `setOpenOrder` in `commitReorder` and
  // the mutation landing, wiping the user's drag position with pre-mutate
  // server state. Waiting for `isPending` to clear means by the time we
  // re-sync, the mutation's own entity-keyed invalidation has run and
  // the incoming `planOpenTaskIds` already reflects the reorder.
  useEffect(() => {
    if (persistReorder.isPending) return;
    setOpenOrder(planOpenTaskIds);
  }, [planOpenTaskIds, persistReorder.isPending]);

  const commitReorder = (nextOrder: string[]) => {
    if (nextOrder.join('|') === openOrder.join('|')) return;
    setOpenOrder(nextOrder);
    persistReorder.mutate(nextOrder);
  };

  const moveTaskByStep = (taskId: string, step: -1 | 1) => {
    if (persistReorder.isPending) return;
    const fromIndex = openOrder.indexOf(taskId);
    if (fromIndex < 0) return;
    const toIndex = fromIndex + step;
    if (toIndex < 0 || toIndex >= openOrder.length) return;
    const nextOrder = [...openOrder];
    const [moved] = nextOrder.splice(fromIndex, 1);
    nextOrder.splice(toIndex, 0, moved!);
    commitReorder(nextOrder);
  };

  const handleDropOn = (targetId: string) => {
    const sourceId = draggingId;
    setDragOverId(null);
    setDraggingId(null);
    if (!sourceId || sourceId === targetId || persistReorder.isPending) return;
    const nextOrder = moveTaskId(openOrder, sourceId, targetId);
    commitReorder(nextOrder);
  };

  const handleDragStart = (
    taskId: string,
    event: DragEvent<HTMLDivElement>,
    title?: string,
  ) => {
    setDraggingId(taskId);
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('text/plain', taskId);
    // Compact drag-image — see lib/dragImage.ts for rationale. Falls
    // back to a generic label when the caller can't thread the task
    // title through (e.g. drag-source state without the full Task).
    applyCompactDragImage(event, { title: title ?? taskId, icon: '✦' });
  };

  const handleDragEnd = () => {
    setDraggingId(null);
    setDragOverId(null);
  };

  const handleDragOver = (taskId: string, event: DragEvent<HTMLDivElement>) => {
    if (!draggingId || persistReorder.isPending) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = 'move';
    if (dragOverId !== taskId) {
      setDragOverId(taskId);
    }
  };

  const handleDragLeave = (taskId: string) => {
    if (dragOverId === taskId) {
      setDragOverId(null);
    }
  };

  const handleTaskReorderKeyDown = (taskId: string, event: KeyboardEvent<HTMLButtonElement>) => {
    if (persistReorder.isPending) return;
    if (!event.altKey || event.metaKey || event.ctrlKey) return;
    if (event.key === 'ArrowUp') {
      event.preventDefault();
      moveTaskByStep(taskId, -1);
    } else if (event.key === 'ArrowDown') {
      event.preventDefault();
      moveTaskByStep(taskId, 1);
    }
  };

  return {
    dragOverId,
    draggingId,
    focusTaskIds: openOrder,
    isReorderPending: persistReorder.isPending,
    handleDragEnd,
    handleDragLeave,
    handleDragOver,
    handleDragStart,
    handleDropOn,
    handleTaskReorderKeyDown,
    moveTaskByStep,
  };
}
