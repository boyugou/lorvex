import { useCallback, useMemo, useRef, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { getAllTasks } from '@/lib/ipc/tasks/queries';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import {
  buildRelationGraphSnapshot,
  type RelationGraphSnapshot,
} from './relationCyclePrecheck';

interface UseTaskDetailRelationComposerArgs {
  taskId: string | null;
  blocksIds: string[];
  dependsOnIds: string[];
  onAddBlocks: (taskId: string) => Promise<void>;
  onAddDependsOn: (taskId: string) => Promise<void>;
}

/**
 * Owns the relation-composer state (which picker is open + which ids
 * to exclude) plus the dependency-graph snapshot used for client-side
 * cycle precheck.
 *
 * The snapshot is captured once when the picker opens — using
 * `queryClient.getQueryData` for the cached `allTasks` payload when
 * possible and falling back to a fresh fetch otherwise. Subsequent
 * keystroke filtering reuses the same snapshot via
 * `relationCyclePrecheck.wouldCreateCycle`, so per-row checks stay
 * O(V+E) instead of re-walking the full task list per render.
 */
export function useTaskDetailRelationComposer({
  taskId,
  blocksIds,
  dependsOnIds,
  onAddBlocks,
  onAddDependsOn,
}: UseTaskDetailRelationComposerArgs) {
  const queryClient = useQueryClient();
  const [addingType, setAddingType] = useState<'depends_on' | 'blocks' | null>(null);
  const [graphSnapshot, setGraphSnapshot] = useState<RelationGraphSnapshot | null>(null);
  // Bumps each time the picker reopens so a late-arriving fetch from
  // a stale picker session can't overwrite the new session's snapshot.
  const snapshotSessionRef = useRef(0);

  const captureSnapshot = useCallback(() => {
    if (!taskId) return;
    const session = ++snapshotSessionRef.current;
    // Try the cache first to avoid an IPC round-trip when the
    // assistant or another view already loaded the full task set.
    const cached =
      queryClient.getQueryData(QUERY_KEYS.allTasks(true, true)) ??
      queryClient.getQueryData(QUERY_KEYS.allTasks(true, false)) ??
      queryClient.getQueryData(QUERY_KEYS.allTasks(false, true)) ??
      queryClient.getQueryData(QUERY_KEYS.allTasks(false, false));
    if (Array.isArray(cached)) {
      setGraphSnapshot(buildRelationGraphSnapshot(cached, taskId));
      return;
    }
    void getAllTasks(true, true)
      .then((tasks) => {
        if (snapshotSessionRef.current !== session) return;
        setGraphSnapshot(buildRelationGraphSnapshot(tasks, taskId));
      })
      .catch(() => {
        // Fall back to "no precheck" silently — the server-side
        // dependency validator still rejects cycle-forming edges, so
        // the user just loses the inline hint, not the safety net.
      });
  }, [queryClient, taskId]);

  const startAddingDependsOn = useCallback(() => {
    setAddingType((current) => {
      const next = current === 'depends_on' ? null : 'depends_on';
      if (next) captureSnapshot();
      return next;
    });
  }, [captureSnapshot]);

  const startAddingBlocks = useCallback(() => {
    setAddingType((current) => {
      const next = current === 'blocks' ? null : 'blocks';
      if (next) captureSnapshot();
      return next;
    });
  }, [captureSnapshot]);

  const cancelAdding = useCallback(() => {
    setAddingType(null);
    setGraphSnapshot(null);
    // Invalidate any in-flight fetch from this picker session.
    snapshotSessionRef.current += 1;
  }, []);

  const excludeIds = useMemo(
    () => [taskId ?? '', ...(addingType === 'depends_on' ? dependsOnIds : blocksIds)],
    [addingType, blocksIds, dependsOnIds, taskId],
  );

  const handleSelectTask = useCallback((selectedTaskId: string) => {
    if (addingType === 'depends_on') {
      void onAddDependsOn(selectedTaskId);
    } else if (addingType === 'blocks') {
      void onAddBlocks(selectedTaskId);
    }
    setAddingType(null);
    setGraphSnapshot(null);
    snapshotSessionRef.current += 1;
  }, [addingType, onAddBlocks, onAddDependsOn]);

  return {
    addingType,
    cancelAdding,
    excludeIds,
    graphSnapshot,
    handleSelectTask,
    startAddingBlocks,
    startAddingDependsOn,
  };
}
