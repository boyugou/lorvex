import { memo, useEffect, useMemo } from 'react';
import { useVirtualizer } from '@tanstack/react-virtual';

import { InteractiveTaskCard } from '../task-card/InteractiveTaskCard';

import { useListView } from './ListViewContext';
import {
  LIST_VIEW_OVERSCAN,
  LIST_VIEW_ROW_ESTIMATE_PX,
  shouldVirtualizeListView,
} from './virtualization';

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

/**
 * Renders the list view's active (non-completed) task rail. For short
 * lists we keep the plain `.map(...)` render — below the threshold the
 * virtualizer's measurement overhead outweighs the win. For long
 * lists we window through `@tanstack/react-virtual`.
 */
export function OpenTaskList(): React.JSX.Element {
  const {
    openTasks,
    selectionMode,
    selectedIds,
    bulk,
    focusedTaskId,
    onToggleSelected,
    onSelectTask,
    onClickWithModifiers,
    scrollContainerRef,
  } = useListView();
  const bulkBusy = bulk.bulkAction !== null;
  const hasSelection = selectedIds.size > 0;

  const virtualize =
    shouldVirtualizeListView(openTasks.length) && scrollContainerRef != null;

  if (!virtualize) {
    return (
      <div className="space-y-1.5">
        {openTasks.map((task) => (
          <OpenTaskRow
            key={task.id}
            task={task}
            selectionMode={selectionMode}
            selected={selectedIds.has(task.id)}
            focused={focusedTaskId === task.id}
            bulkBusy={bulkBusy}
            hasSelection={hasSelection}
            onToggleSelected={onToggleSelected}
            onSelectTask={onSelectTask}
            onClickWithModifiers={onClickWithModifiers}
          />
        ))}
      </div>
    );
  }

  return (
    <VirtualizedOpenTaskList
      tasks={openTasks}
      selectionMode={selectionMode}
      selectedIds={selectedIds}
      focusedTaskId={focusedTaskId ?? null}
      bulkBusy={bulkBusy}
      hasSelection={hasSelection}
      onToggleSelected={onToggleSelected}
      onSelectTask={onSelectTask}
      onClickWithModifiers={onClickWithModifiers}
      scrollContainerRef={scrollContainerRef}
    />
  );
}

// ---------------------------------------------------------------------------
// Virtualized variant
// ---------------------------------------------------------------------------

type ListViewContextValue = ReturnType<typeof useListView>;

interface VirtualizedProps {
  tasks: ListViewContextValue['openTasks'];
  selectionMode: ListViewContextValue['selectionMode'];
  selectedIds: ListViewContextValue['selectedIds'];
  focusedTaskId: string | null;
  bulkBusy: boolean;
  hasSelection: boolean;
  onToggleSelected: ListViewContextValue['onToggleSelected'];
  onSelectTask: ListViewContextValue['onSelectTask'];
  onClickWithModifiers: ListViewContextValue['onClickWithModifiers'];
  scrollContainerRef: NonNullable<ListViewContextValue['scrollContainerRef']>;
}

function VirtualizedOpenTaskList({
  tasks,
  selectionMode,
  selectedIds,
  focusedTaskId,
  bulkBusy,
  hasSelection,
  onToggleSelected,
  onSelectTask,
  onClickWithModifiers,
  scrollContainerRef,
}: VirtualizedProps): React.JSX.Element {
  const virtualizer = useVirtualizer({
    count: tasks.length,
    getScrollElement: () => scrollContainerRef.current,
    estimateSize: () => LIST_VIEW_ROW_ESTIMATE_PX,
    overscan: LIST_VIEW_OVERSCAN,
    // Stable per-task key so row measurements survive reordering.
    getItemKey: (index) => tasks[index]?.id ?? index,
  });

  // Keyboard-driven focus changes (j/k, arrows) must scroll the
  // focused row into view even when it's outside the current window.
  // The generic `useTaskListKeyboard` hook uses DOM scrollIntoView on
  // a `[data-task-id]` host — which doesn't exist for virtual rows
  // that haven't rendered yet. Mirror the fix AllTasksView applies:
  // map the focused id back to an index and let the virtualizer
  // scroll the container.
  const taskIndexById = useMemo(() => {
    const map = new Map<string, number>();
    tasks.forEach((task, idx) => map.set(task.id, idx));
    return map;
  }, [tasks]);

  useEffect(() => {
    if (!focusedTaskId) return;
    const idx = taskIndexById.get(focusedTaskId);
    if (idx == null) return;
    virtualizer.scrollToIndex(idx, { align: 'auto' });
  }, [focusedTaskId, taskIndexById, virtualizer]);

  return (
    <div
      className="relative w-full"
      style={{ height: `${virtualizer.getTotalSize()}px` }}
    >
      {virtualizer.getVirtualItems().map((vItem) => {
        const task = tasks[vItem.index];
        if (!task) return null;
        return (
          <div
            key={vItem.key}
            data-index={vItem.index}
            ref={virtualizer.measureElement}
            style={{
              position: 'absolute',
              top: 0,
              left: 0,
              width: '100%',
              transform: `translateY(${vItem.start}px)`,
            }}
          >
            <div className="py-0.5">
              <OpenTaskRow
                task={task}
                selectionMode={selectionMode}
                selected={selectedIds.has(task.id)}
                focused={focusedTaskId === task.id}
                bulkBusy={bulkBusy}
                hasSelection={hasSelection}
                onToggleSelected={onToggleSelected}
                onSelectTask={onSelectTask}
                onClickWithModifiers={onClickWithModifiers}
              />
            </div>
          </div>
        );
      })}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Shared row renderer — keeps the two code paths in sync
// ---------------------------------------------------------------------------

interface OpenTaskRowProps {
  task: ListViewContextValue['openTasks'][number];
  selectionMode: boolean;
  selected: boolean;
  focused: boolean;
  bulkBusy: boolean;
  hasSelection: boolean;
  onToggleSelected: ListViewContextValue['onToggleSelected'];
  onSelectTask: ListViewContextValue['onSelectTask'];
  onClickWithModifiers: ListViewContextValue['onClickWithModifiers'];
}

const OpenTaskRow = memo(function OpenTaskRow({
  task,
  selectionMode,
  selected,
  focused,
  bulkBusy,
  hasSelection,
  onToggleSelected,
  onSelectTask,
  onClickWithModifiers,
}: OpenTaskRowProps): React.JSX.Element {
  if (selectionMode) {
    return (
      <InteractiveTaskCard
        task={task}
        selectionMode
        selected={selected}
        bulkBusy={bulkBusy}
        onToggleSelected={onToggleSelected}
      />
    );
  }
  return (
    <InteractiveTaskCard
      task={task}
      selectionMode={false}
      selected={selected}
      focused={focused}
      hideListInfo
      hasSelection={hasSelection}
      onSelect={onSelectTask}
      onClickWithModifiers={onClickWithModifiers}
    />
  );
});
