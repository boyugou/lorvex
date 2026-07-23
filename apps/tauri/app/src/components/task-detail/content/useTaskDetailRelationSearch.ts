import { useEffect, useMemo, useRef, useState } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import { searchTasks } from '@/lib/ipc/tasks/queries';
import {
  clearTaskDetailRelationSearchTimer,
  createBrowserTaskDetailRelationSearchTimerHost,
  createTaskDetailRelationSearchTimerState,
  scheduleTaskDetailRelationSearch,
  type TaskDetailRelationSearchTimerState,
} from './useTaskDetailRelationSearch.runtime';

interface UseTaskDetailRelationSearchArgs {
  excludeIds: string[];
}

const taskDetailRelationSearchTimerHost = createBrowserTaskDetailRelationSearchTimerHost();

export function useTaskDetailRelationSearch({
  excludeIds,
}: UseTaskDetailRelationSearchArgs) {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Task[]>([]);
  const [loading, setLoading] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const debounceRef = useRef<TaskDetailRelationSearchTimerState>(createTaskDetailRelationSearchTimerState());

  // Stabilize excludeIds to prevent unnecessary search re-triggers when the
  // caller passes a new array reference with the same contents each render.
  const excludeKey = JSON.stringify(excludeIds);
  // Stabilize over the JSON-key so a fresh array reference with the
  // same contents doesn't re-trigger the search effect; we
  // deliberately don't list `excludeIds` since `excludeKey` is the
  // identity-stable representation.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const stableExcludeIds = useMemo(() => excludeIds, [excludeKey]);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  useEffect(() => {
    if (query.length < 2) {
      setResults([]);
      setLoading(false);
      return;
    }
    let cancelled = false;
    scheduleTaskDetailRelationSearch({
      state: debounceRef.current,
      timerHost: taskDetailRelationSearchTimerHost,
      runSearch: () => {
        void (async () => {
          setLoading(true);
          try {
            const found = await searchTasks(query, false);
            if (!cancelled) {
              setResults(found.filter((task) => !stableExcludeIds.includes(task.id)).slice(0, 8));
            }
          } catch {
            if (!cancelled) setResults([]);
          } finally {
            if (!cancelled) setLoading(false);
          }
        })();
      },
    });
    return () => {
      cancelled = true;
      clearTaskDetailRelationSearchTimer(
        // We deliberately read `.current` at cleanup time so we clear
        // whichever debounce timer is currently armed.
        // eslint-disable-next-line react-hooks/exhaustive-deps
        debounceRef.current,
        taskDetailRelationSearchTimerHost.clearTimeout,
      );
    };
  }, [stableExcludeIds, query]);

  return {
    inputRef,
    loading,
    query,
    results,
    setQuery,
  };
}
