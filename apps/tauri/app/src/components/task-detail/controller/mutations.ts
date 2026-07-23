import { useMemo, useRef, useState } from 'react';

import { useTaskDetailLifecycleMutations } from './mutations/lifecycle';
import { useTaskDetailMetadataMutations } from './mutations/metadata';
import type {
  TaskDetailMutationState,
  UseTaskDetailMutationDeps,
} from './mutations/types';

export function useTaskDetailMutations(
  deps: UseTaskDetailMutationDeps,
): TaskDetailMutationState {
  const [isCompleting, setIsCompleting] = useState(false);
  const [actionPending, setActionPending] = useState(false);

  const lifecycle = useTaskDetailLifecycleMutations({
    ...deps,
    isCompleting,
    setIsCompleting,
  });
  const metadata = useTaskDetailMetadataMutations(deps);

  // Use ref for actionPending so guard callback identity stays stable
  const actionPendingRef = useRef(actionPending);
  actionPendingRef.current = actionPending;

  /** Wrap a void-returning async function with action-pending serialization. */
  function useGuarded(fn: () => Promise<void>): () => Promise<void> {
    return useMemo(() => async () => {
      if (actionPendingRef.current) return;
      setActionPending(true);
      try { await fn(); } finally { setActionPending(false); }
    }, [fn]);
  }

  const handleDuplicate = useGuarded(lifecycle.handleDuplicate);
  const handlePermanentDelete = useGuarded(lifecycle.handlePermanentDelete);
  const handleReopen = useGuarded(lifecycle.handleReopen);
  const handleResetDeferral = useGuarded(lifecycle.handleResetDeferral);

  // handleDelete accepts an optional cancelSeries param — guard it separately
  // Depend on the stable `.handleDelete` method only (not the whole
  // lifecycle bag, whose object identity churns each render).
  const handleDelete = useMemo(
    () => async (cancelSeries?: boolean) => {
      if (actionPendingRef.current) return;
      setActionPending(true);
      try { await lifecycle.handleDelete(cancelSeries); } finally { setActionPending(false); }
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [lifecycle.handleDelete],
  );

  return useMemo<TaskDetailMutationState>(() => ({
    ...lifecycle,
    handleDelete,
    handleDuplicate,
    handlePermanentDelete,
    handleReopen,
    handleResetDeferral,
    ...metadata,
    actionPending,
    isCompleting,
  }), [
    actionPending,
    handleDelete,
    handleDuplicate,
    handlePermanentDelete,
    handleReopen,
    handleResetDeferral,
    isCompleting,
    lifecycle,
    metadata,
  ]);
}

export type { TaskDetailMutationState } from './mutations/types';
