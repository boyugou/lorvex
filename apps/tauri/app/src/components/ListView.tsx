import { useCallback, useMemo, type MouseEvent as ReactMouseEvent } from 'react';
import { useConfiguredDayContext } from '../lib/dayContext';
import { useBulkActions } from '../lib/tasks/useBulkActions';
import { useRuntimeProfile } from '../lib/useRuntimeProfile';
import { useTaskListActions } from '../lib/tasks/useTaskListActions';
import { useTaskListKeyboard } from '../lib/tasks/useTaskListKeyboard';
import { useTaskSelection } from '../lib/tasks/useTaskSelection';
import { useI18n } from '../lib/i18n';
import { ListViewContent, ListViewLoadError, LoadingState } from './list-view/ListViewContent';
import type { ListViewProps } from './list-view/support';
import { useListViewController } from './list-view/useListViewController';
import { KeyboardHintBar } from './ui/KeyboardHintBar';
import { PickerOverlays } from './ui/PickerOverlays';

export default function ListView({ listId, initialRename, onSelectTask, onListDeleted }: ListViewProps) {
  const dayContext = useConfiguredDayContext();
  const runtimeProfile = useRuntimeProfile();
  const usesMobileLayout = runtimeProfile.runtimeClass === 'mobile';
  const { t, format } = useI18n();
  const {
    adding,
    allTags,
    clearTagFilter,
    completedTasks,
    isFilterActive,
    data,
    deleting,
    deletionFinalized,
    draft,
    error,
    filterPriority,
    handleAdd,
    handleDeleteList,
    handleRename,
    inputRef,
    isLoading,
    openTasks,
    refetch,
    renameSaving,
    renaming,
    search,
    selectedTags,
    setDraft,
    setFilterPriority,
    setRenaming,
    setSearch,
    setSortKey,
    sortDirection,
    sortKey,
    toggleSortDirection,
    toggleTag,
    totalOpenCount,
  } = useListViewController({
    listId,
    initialRename,
    onListDeleted,
  });

  const openTaskIds = useMemo(() => openTasks.map((t) => t.id), [openTasks]);
  const openTaskIdSet = useMemo(() => new Set(openTaskIds), [openTaskIds]);

  // Selection + bulk actions
  const {
    selectionMode,
    selectedIds,
    selectAll,
    toggleTaskSelected,
    setSelectionModeEnabled,
    setSelectedIds,
    clearSelection,
    handleClickWithModifiers,
    handleKeyboardExtend,
  } = useTaskSelection(openTaskIdSet, null, {
    // localized strings for the silent-collapse warning
    // toast. Keeping them inline here means the hook itself remains
    // i18n-string-free.
    onSelectionCollapsedMessage: (count) =>
      format('allTasks.selectionCollapsed', { count: String(count) }),
    onSelectionCollapsedUndoLabel: () => t('allTasks.selectionCollapsedRestore'),
  });
  const bulk = useBulkActions({
    tasks: openTasks,
    selectedIds,
    setSelectedIds,
    deferDateYmd: dayContext.tomorrowYmd,
  });

  const onExtendSelection = useCallback(
    (direction: 'up' | 'down', focusedId: string | null) =>
      handleKeyboardExtend(direction, openTaskIds, focusedId),
    [handleKeyboardExtend, openTaskIds],
  );
  const onClickWithModifiers = useCallback(
    (id: string, event: ReactMouseEvent<HTMLButtonElement>) =>
      handleClickWithModifiers(id, event, openTaskIds, null),
    [handleClickWithModifiers, openTaskIds],
  );

  const baseActions = useTaskListActions(openTasks);
  const keyboardActions = {
    ...baseActions,
    onToggleSelected: toggleTaskSelected,
    setSelectionModeEnabled,
    selectionModeActive: selectionMode,
    onExtendSelection,
    onSelectAll: selectAll,
    onClearSelection: clearSelection,
    hasSelection: selectedIds.size > 0,
  };
  const keyboard = useTaskListKeyboard({
    taskIds: openTaskIds,
    onSelect: onSelectTask,
    actions: keyboardActions,
    disabled: isLoading || !!error || renaming,
  });

  if (isLoading) {
    return <LoadingState />;
  }

  if (error) {
    return (
      <ListViewLoadError
        onRetryLoad={() => { void refetch(); }}
        onBack={onListDeleted}
      />
    );
  }

  if (!data) return null;
  if (deletionFinalized) return null;

  return (
    <div className="h-full flex flex-col overflow-hidden clarity-first-surface">
      <ListViewContent
        data={data}
        inputRef={inputRef}
        draft={draft}
        adding={adding}
        deleting={deleting}
        renaming={renaming}
        renameSaving={renameSaving}
        usesMobileLayout={usesMobileLayout}
        openTasks={openTasks}
        completedTasks={completedTasks}
        search={search}
        onSearchChange={setSearch}
        onDraftChange={setDraft}
        onAdd={handleAdd}
        onDeleteList={handleDeleteList}
        onRename={handleRename}
        onStartRename={() => setRenaming(true)}
        onCancelRename={() => setRenaming(false)}
        onSelectTask={onSelectTask}
        focusedTaskId={keyboard.focusedId}
        sortKey={sortKey}
        sortDirection={sortDirection}
        onSortKeyChange={setSortKey}
        onToggleSortDirection={toggleSortDirection}
        filterPriority={filterPriority}
        onFilterPriorityChange={setFilterPriority}
        allTags={allTags}
        selectedTags={selectedTags}
        onToggleTag={toggleTag}
        onClearTagFilter={clearTagFilter}
        isFilterActive={isFilterActive}
        totalOpenCount={totalOpenCount}
        selectionMode={selectionMode}
        selectedIds={selectedIds}
        onToggleSelected={toggleTaskSelected}
        onSelectAll={selectAll}
        onClearSelection={clearSelection}
        onSetSelectionMode={setSelectionModeEnabled}
        onClickWithModifiers={onClickWithModifiers}
        bulk={bulk}
      />

      <KeyboardHintBar visible={keyboard.showKeyboardHints} />

      <PickerOverlays
        tasks={openTasks}
        movePickerTaskId={baseActions.movePickerTaskId}
        closeMovePickerAction={baseActions.closeMovePickerAction}
        recurrencePickerTaskId={baseActions.recurrencePickerTaskId}
        closeRecurrencePickerAction={baseActions.closeRecurrencePickerAction}
        dueDatePickerTaskId={baseActions.dueDatePickerTaskId}
        closeDueDatePickerAction={baseActions.closeDueDatePickerAction}
        durationPickerTaskId={baseActions.durationPickerTaskId}
        closeDurationPickerAction={baseActions.closeDurationPickerAction}
      />
    </div>
  );
}
