import { useCallback, type Dispatch, type KeyboardEvent as ReactKeyboardEvent, type SetStateAction } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import { reopenTask } from '@/lib/ipc/tasks/mutations/lifecycle';
import { isImeComposingEvent } from '@/lib/ime';
import { isPrimaryModifierPressed } from '@/lib/shortcuts';
import type { View } from '@/lib/types';
import { isListView } from '../model';
import type { KeyedResult, ResultItem } from '../types';
import type { PaletteMutationRunner } from './mutations';
import { TASK_STATUS } from '@lorvex/shared/types';
import { recordPaletteActivation, recordTaskOpen } from './paletteUsage';

/// PageUp/PageDown step size — chosen to approximate a viewport of
/// palette rows on the typical 640px-tall dropdown. Matches the
/// "page through a long list" cadence users get from native scroll
/// containers without skipping so many rows that visual continuity
/// breaks.
const PALETTE_PAGE_STEP = 8;

interface UsePaletteKeyboardArgs {
  shelveListFromPalette: (listId: string, listName: string) => void;
  cancelFromPalette: (task: Task) => void;
  completeFromPalette: (task: Task) => void;
  deferFromPalette: (task: Task) => void;
  deleteListFromPalette: (listId: string) => void;
  isComposing: boolean;
  keyedResults: KeyedResult[];
  lists: Array<{ id: string; name: string }>;
  moveTask: Task | null;
  onClose: () => void;
  onNavigate: (view: View) => void;
  onSelectTask: (taskId: string) => void;
  query: string;
  runPaletteMutation: PaletteMutationRunner;
  selectedIdx: number;
  setMoveTask: Dispatch<SetStateAction<Task | null>>;
  setQuery: Dispatch<SetStateAction<string>>;
  setSelectedIdx: Dispatch<SetStateAction<number>>;
}

export function usePaletteKeyboard({
  shelveListFromPalette,
  cancelFromPalette,
  completeFromPalette,
  deferFromPalette,
  deleteListFromPalette,
  isComposing,
  keyedResults,
  lists,
  moveTask,
  onClose,
  onNavigate,
  onSelectTask,
  query,
  runPaletteMutation,
  selectedIdx,
  setMoveTask,
  setQuery,
  setSelectedIdx,
}: UsePaletteKeyboardArgs) {
  const activate = useCallback((item: ResultItem) => {
    if (item.kind === 'nav') {
      // record activation BEFORE navigating so a navigation that
      // unmounts this hook can't drop the side effect on the floor.
      recordPaletteActivation({
        kind: 'nav',
        key: `nav:${item.label}`,
        label: item.label,
      });
      onNavigate(item.view);
      onClose();
      return;
    }
    if (item.kind === 'action') {
      recordPaletteActivation({
        kind: 'action',
        key: `action:${item.label}`,
        label: item.label,
      });
      item.action();
      return;
    }
    recordTaskOpen(item.task.id, item.task.title);
    onSelectTask(item.task.id);
    onClose();
  }, [onClose, onNavigate, onSelectTask]);

  const handleKeyDown = useCallback((e: ReactKeyboardEvent<HTMLInputElement>) => {
    if (isComposing || isImeComposingEvent(e.nativeEvent as KeyboardEvent & { keyCode?: number; which?: number })) return;
    const safeSelectedIdx = keyedResults.length === 0
      ? -1
      : Math.min(Math.max(selectedIdx, 0), keyedResults.length - 1);
    const selectedItem = safeSelectedIdx >= 0 ? keyedResults[safeSelectedIdx]?.item : null;
    if (e.key === 'Escape') {
      e.preventDefault();
      e.stopPropagation();
      if (moveTask) {
        setMoveTask(null);
        setQuery('');
        setSelectedIdx(0);
        return;
      }
      onClose();
      return;
    }

    if (e.key === 'Tab' && !e.shiftKey && !moveTask && selectedItem?.kind === 'task') {
      e.preventDefault();
      setMoveTask(selectedItem.task);
      setQuery('');
      setSelectedIdx(0);
      return;
    }

    const selectedNavItem = selectedItem?.kind === 'nav' ? selectedItem : null;
    const selectedNavView = selectedNavItem?.view;
    const scopedListMode = !moveTask && query.trim().startsWith('@');
    if (scopedListMode && e.key === 'Enter' && selectedNavView && isListView(selectedNavView)) {
      const selectedList = lists.find((list) => list.id === selectedNavView.listId);
      if (selectedList) {
        if (isPrimaryModifierPressed(e.nativeEvent as KeyboardEvent)) {
          e.preventDefault();
          shelveListFromPalette(selectedList.id, selectedList.name);
          return;
        }
        if (e.shiftKey) {
          e.preventDefault();
          deleteListFromPalette(selectedList.id);
          return;
        }
      }
    }

    if (e.key === 'Enter' && selectedItem?.kind === 'task') {
      const task = selectedItem.task;
      const canMutate = task.status !== TASK_STATUS.completed && task.status !== TASK_STATUS.cancelled;

      if (isPrimaryModifierPressed(e.nativeEvent as KeyboardEvent)) {
        e.preventDefault();
        if (canMutate) {
          completeFromPalette(task);
        } else {
          runPaletteMutation(() => reopenTask(task.id), 'reopen');
        }
        return;
      }

      if (e.altKey && canMutate) {
        e.preventDefault();
        deferFromPalette(task);
        return;
      }

      if (e.shiftKey && canMutate) {
        e.preventDefault();
        cancelFromPalette(task);
        return;
      }
    }

    if (e.key === 'ArrowDown') {
      e.preventDefault();
      if (keyedResults.length === 0) return;
      setSelectedIdx((index) => Math.min(index + 1, keyedResults.length - 1));
    }
    if (e.key === 'ArrowUp') {
      e.preventDefault();
      setSelectedIdx((index) => Math.max(index - 1, 0));
    }
    if (e.key === 'Home') {
      e.preventDefault();
      setSelectedIdx(0);
    }
    if (e.key === 'End') {
      e.preventDefault();
      if (keyedResults.length === 0) return;
      setSelectedIdx(keyedResults.length - 1);
      return;
    }
    // PageUp/PageDown step by a viewport-sized chunk so long result
    // lists (recents + frequent + nav + actions can span 20+ rows)
    // are navigable without holding ArrowUp/Down. Matches the
    // DatePicker stepper convention.
    if (e.key === 'PageDown') {
      e.preventDefault();
      if (keyedResults.length === 0) return;
      setSelectedIdx((index) => Math.min(index + PALETTE_PAGE_STEP, keyedResults.length - 1));
      return;
    }
    if (e.key === 'PageUp') {
      e.preventDefault();
      setSelectedIdx((index) => Math.max(index - PALETTE_PAGE_STEP, 0));
      return;
    }
    if (e.key === 'Enter' && selectedItem) {
      e.preventDefault();
      e.stopPropagation();
      activate(selectedItem);
    }
  }, [
    activate,
    shelveListFromPalette,
    cancelFromPalette,
    completeFromPalette,
    deferFromPalette,
    deleteListFromPalette,
    isComposing,
    keyedResults,
    lists,
    moveTask,
    onClose,
    query,
    runPaletteMutation,
    selectedIdx,
    setMoveTask,
    setQuery,
    setSelectedIdx,
  ]);

  return {
    activate,
    handleKeyDown,
  };
}
