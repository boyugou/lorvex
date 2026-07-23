import { useRef, useMemo } from 'react';
import { useQueries, useQuery, keepPreviousData } from '@tanstack/react-query';
import { getTask, getTaskAttribution, getTasksBlockedBy } from '@/lib/ipc/tasks/queries';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { STALE_DEFAULT, STALE_LONG } from '@/lib/query/timing';
import { parseJsonIds } from '../support';

export function useTaskDetailQueries(taskId: string): {
  attribution: Awaited<ReturnType<typeof getTaskAttribution>> | null;
  blocksIds: string[];
  dependsOnIds: string[];
  depTaskMap: Record<string, { title: string; status: string }>;
  error: unknown;
  isLoading: boolean;
  refetchTask: () => Promise<unknown>;
  task: Awaited<ReturnType<typeof getTask>> | null;
} {
  const {
    data: taskData,
    isLoading,
    error,
    refetch: refetchTask,
  } = useQuery({
    queryKey: QUERY_KEYS.task(taskId),
    queryFn: ({ signal }) => getTask(taskId, signal),
    placeholderData: keepPreviousData,
  });
  const task = taskData ?? null;

  const { data: attributionData } = useQuery({
    queryKey: QUERY_KEYS.taskAttribution(taskId),
    queryFn: ({ signal }) => getTaskAttribution(taskId, signal),
  });
  const attribution = attributionData ?? null;

  const dependsOnIds = useMemo(() => parseJsonIds(task?.depends_on ?? null), [task?.depends_on]);

  // Reverse-edge lookup: tasks that this task blocks (derived from their depends_on).
  const { data: blockedTasks } = useQuery({
    queryKey: QUERY_KEYS.tasksBlockedBy(taskId),
    queryFn: ({ signal }) => getTasksBlockedBy(taskId, signal),
    staleTime: STALE_DEFAULT,
  });
  const blocksIds = useMemo(() => (blockedTasks ?? []).map((t) => t.id), [blockedTasks]);

  const allDepIds = useMemo(() => [...new Set([...dependsOnIds, ...blocksIds])], [blocksIds, dependsOnIds]);

  const depQueries = useQueries({
    queries: allDepIds.map((id) => ({
      queryKey: QUERY_KEYS.task(id),
      queryFn: ({ signal }: { signal?: AbortSignal }) => getTask(id, signal),
      staleTime: STALE_LONG,
      gcTime: 30_000,
    })),
  });
  // Stabilize depTaskMap identity: only produce a new object when the
  // actual title/status values change, not on every useQueries reference.
  const prevDepMapRef = useRef<Record<string, { title: string; status: string }>>({});
  const depTaskMap = useMemo(() => {
    const map: Record<string, { title: string; status: string }> = {};
    for (let index = 0; index < allDepIds.length; index += 1) {
      const depTask = depQueries[index]?.data;
      if (depTask) {
        map[allDepIds[index]!] = { title: depTask.title, status: depTask.status };
      }
    }
    // Shallow-compare against previous: return stable reference if unchanged
    const prev = prevDepMapRef.current;
    const keys = Object.keys(map);
    const prevKeys = Object.keys(prev);
    if (
      keys.length === prevKeys.length &&
      keys.every((k) => prev[k]?.title === map[k]!.title && prev[k]?.status === map[k]!.status)
    ) {
      return prev;
    }
    prevDepMapRef.current = map;
    return map;
  }, [allDepIds, depQueries]);

  return {
    attribution,
    blocksIds,
    dependsOnIds,
    depTaskMap,
    error,
    isLoading,
    refetchTask,
    task,
  };
}
