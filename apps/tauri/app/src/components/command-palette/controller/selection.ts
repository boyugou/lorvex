import { useCallback, useEffect, type Dispatch, type RefObject, type SetStateAction } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import { getPaletteOptionId, isListView } from '../model';
import type { KeyedResult } from '../types';

interface UsePaletteSelectionArgs {
  isScopedListQuery: boolean;
  keyedResults: KeyedResult[];
  lists: Array<{ id: string; name: string }>;
  moveTask: Task | null;
  // palette options are now <div role="option">; widen
  // the ref map's element type accordingly.
  optionRefs: RefObject<Map<string, HTMLElement>>;
  query: string;
  selectedIdx: number;
  selectedResultKey: string | null;
  setConfirmArchiveListId: Dispatch<SetStateAction<string | null>>;
  setMoveTask: Dispatch<SetStateAction<Task | null>>;
  setQuery: Dispatch<SetStateAction<string>>;
  setSelectedIdx: Dispatch<SetStateAction<number>>;
  setSelectedResultKey: Dispatch<SetStateAction<string | null>>;
}

export function usePaletteSelection({
  isScopedListQuery,
  keyedResults,
  lists,
  moveTask,
  optionRefs,
  query,
  selectedIdx,
  selectedResultKey,
  setConfirmArchiveListId,
  setMoveTask,
  setQuery,
  setSelectedIdx,
  setSelectedResultKey,
}: UsePaletteSelectionArgs) {
  useEffect(() => {
    setSelectedIdx(0);
    setSelectedResultKey(null);
  }, [query, moveTask, setSelectedIdx, setSelectedResultKey]);

  useEffect(() => {
    const currentKey = keyedResults[selectedIdx]?.key ?? null;
    if (currentKey !== selectedResultKey) {
      setSelectedResultKey(currentKey);
    }
  }, [keyedResults, selectedIdx, selectedResultKey, setSelectedResultKey]);

  useEffect(() => {
    if (keyedResults.length === 0) {
      setSelectedIdx(0);
      if (selectedResultKey !== null) setSelectedResultKey(null);
      return;
    }
    if (selectedResultKey) {
      const preservedIdx = keyedResults.findIndex((entry) => entry.key === selectedResultKey);
      if (preservedIdx >= 0) {
        if (preservedIdx !== selectedIdx) setSelectedIdx(preservedIdx);
        return;
      }
    }
    setSelectedIdx((prev) => Math.min(Math.max(prev, 0), keyedResults.length - 1));
  }, [keyedResults, selectedIdx, selectedResultKey, setSelectedIdx, setSelectedResultKey]);

  useEffect(() => {
    setConfirmArchiveListId(null);
  }, [query, moveTask, setConfirmArchiveListId]);

  const visualSelectedIdx = keyedResults.length === 0
    ? 0
    : Math.min(Math.max(selectedIdx, 0), keyedResults.length - 1);
  const selectedResult = keyedResults[visualSelectedIdx]?.item ?? null;
  const selectedTask = selectedResult?.kind === 'task' ? selectedResult.task : null;
  const selectedNavResult = selectedResult?.kind === 'nav' ? selectedResult : null;
  const selectedScopedListView = selectedNavResult && isListView(selectedNavResult.view)
    ? selectedNavResult.view
    : null;
  const selectedScopedList = isScopedListQuery && selectedScopedListView
    ? lists.find((list) => list.id === selectedScopedListView.listId) ?? null
    : null;
  const movingTaskTitle = moveTask?.title ?? '';
  const selectedEntry = keyedResults[visualSelectedIdx] ?? null;
  const activeOptionId = selectedEntry ? getPaletteOptionId(selectedEntry.key) : null;

  useEffect(() => {
    if (!activeOptionId) return;
    const option = optionRefs.current.get(activeOptionId);
    option?.scrollIntoView({ block: 'nearest' });
  }, [activeOptionId, optionRefs]);

  const clearMoveTask = useCallback(() => {
    setMoveTask(null);
    setQuery('');
    setSelectedIdx(0);
  }, [setMoveTask, setQuery, setSelectedIdx]);

  return {
    activeOptionId,
    clearMoveTask,
    movingTaskTitle,
    selectedScopedList,
    selectedTask,
    visualSelectedIdx,
  };
}
