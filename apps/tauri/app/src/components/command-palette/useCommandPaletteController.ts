import { useI18n } from '@/lib/i18n';
import type { CommandPaletteProps } from './types';
import { usePaletteKeyboard } from './controller/keyboard';
import { usePaletteMutationActions } from './controller/mutations';
import { useCommandPaletteResults } from './controller/results';
import { usePaletteSelection } from './controller/selection';
import { usePaletteState } from './controller/state';

export function useCommandPaletteController({
  onClose,
  onNavigate,
  onSelectTask,
  onQuickCapture,
}: CommandPaletteProps) {
  const { t, format } = useI18n();
  const state = usePaletteState({ t });

  const {
    shelveListFromPalette,
    cancelFromPalette,
    completeFromPalette,
    createListFromPalette,
    deferFromPalette,
    deleteListFromPalette,
    runPaletteMutation,
  } = usePaletteMutationActions({
    confirmArchiveListId: state.confirmArchiveListId,
    onClose,
    query: state.query,
    setConfirmArchiveListId: state.setConfirmArchiveListId,
    t,
    format,
  });

  const { keyedResults, results } = useCommandPaletteResults({
    shelveListFromPalette,
    confirmArchiveListId: state.confirmArchiveListId,
    createListFromPalette,
    deleteListFromPalette,
    lists: state.lists,
    moveTask: state.moveTask,
    navItems: state.navItems,
    onClose,
    onNavigate,
    onQuickCapture,
    onSelectTask,
    query: state.query,
    runPaletteMutation,
    searchResults: state.searchResults,
    // when the user is searching, expose a "Permanent delete"
    // system action targeting the top match. The destructive flow is
    // gated by a confirm() modal, so even a stray Enter on the entry
    // never destroys data without an explicit YES.
    selectedTask: state.searchResults[0] ?? null,
    t,
    format,
  });

  const {
    activeOptionId,
    clearMoveTask,
    movingTaskTitle,
    selectedScopedList,
    selectedTask,
    visualSelectedIdx,
  } = usePaletteSelection({
    isScopedListQuery: state.isScopedListQuery,
    keyedResults,
    lists: state.lists,
    moveTask: state.moveTask,
    optionRefs: state.optionRefs,
    query: state.query,
    selectedIdx: state.selectedIdx,
    selectedResultKey: state.selectedResultKey,
    setConfirmArchiveListId: state.setConfirmArchiveListId,
    setMoveTask: state.setMoveTask,
    setQuery: state.setQuery,
    setSelectedIdx: state.setSelectedIdx,
    setSelectedResultKey: state.setSelectedResultKey,
  });

  const { activate, handleKeyDown } = usePaletteKeyboard({
    shelveListFromPalette,
    cancelFromPalette,
    completeFromPalette,
    deferFromPalette,
    deleteListFromPalette,
    isComposing: state.isComposing,
    keyedResults,
    lists: state.lists,
    moveTask: state.moveTask,
    onClose,
    onNavigate,
    onSelectTask,
    query: state.query,
    runPaletteMutation,
    selectedIdx: state.selectedIdx,
    setMoveTask: state.setMoveTask,
    setQuery: state.setQuery,
    setSelectedIdx: state.setSelectedIdx,
  });

  return {
    activeOptionId,
    activate,
    clearMoveTask,
    handleKeyDown,
    inScopedListMode: state.isScopedListQuery,
    isSearching: state.isSearching,
    keyedResults,
    moveTask: state.moveTask,
    movingTaskTitle,
    optionRefs: state.optionRefs,
    query: state.query,
    results,
    selectedScopedList,
    selectedTask,
    setIsComposing: state.setIsComposing,
    setQuery: state.setQuery,
    visualSelectedIdx,
  };
}
