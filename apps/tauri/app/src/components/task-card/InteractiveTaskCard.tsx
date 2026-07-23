import { memo, useCallback, type MouseEvent as ReactMouseEvent } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import TaskCard from './TaskCard';
import { SelectableTaskCard } from '../ui/SelectableTaskCard';
import { SwipeableTaskCard } from './SwipeableTaskCard';

const NOOP = () => {};

interface InteractiveTaskCardProps {
  task: Task;
  selectionMode: boolean;
  selected?: boolean;
  bulkBusy?: boolean;
  onToggleSelected?: ((id: string) => void) | undefined;
  onSelect?: ((id: string) => void) | undefined;
  /**
   * Optional modifier-aware click handler. When provided and the click
   * carries a meta/ctrl/shift modifier — or when `hasSelection` is
   * truthy — the card routes the click here instead of to `onSelect`,
   * enabling native-style multi-select without requiring the explicit
   * selection-mode toggle. Plain clicks with no modifier and no active
   * selection still fall through to `onSelect` (navigate to detail).
   */
  onClickWithModifiers?: ((id: string, event: ReactMouseEvent<HTMLButtonElement>) => void) | undefined;
  /** True when the parent holds a non-empty multi-selection. */
  hasSelection?: boolean;
  focused?: boolean;
  completed?: boolean | undefined;
  /** Hide list name badge (forwarded to TaskCard). */
  hideListInfo?: boolean;
  /** Show the colored left border from the task's list. Default `true`. */
  showListColor?: boolean;
}

/**
 * Single composition owner for selection + swipe + plain card.
 *
 * - **Selection mode:** delegates to `SelectableTaskCard` (no swipe).
 * - **Normal mode:** wraps `TaskCard` in `SwipeableTaskCard`.
 */
export const InteractiveTaskCard = memo(function InteractiveTaskCard({
  task,
  selectionMode,
  selected = false,
  bulkBusy = false,
  onToggleSelected,
  onSelect,
  onClickWithModifiers,
  hasSelection = false,
  focused = false,
  completed,
  hideListInfo = false,
  showListColor,
}: InteractiveTaskCardProps) {
  const handleClick = useCallback(
    (event?: ReactMouseEvent<HTMLButtonElement>) => {
      // Native-style multi-select: a modifier, or an existing selection,
      // means the click manipulates selection instead of navigating.
      if (event && onClickWithModifiers) {
        const hasModifier = event.shiftKey || event.metaKey || event.ctrlKey;
        if (hasModifier || hasSelection) {
          event.preventDefault();
          onClickWithModifiers(task.id, event);
          return;
        }
      }
      onSelect?.(task.id);
    },
    [onSelect, onClickWithModifiers, hasSelection, task.id],
  );

  if (selectionMode) {
    return (
      <SelectableTaskCard
        task={task}
        selected={selected}
        bulkBusy={bulkBusy}
        completed={completed}
        onToggleSelected={onToggleSelected ?? NOOP}
      />
    );
  }

  return (
    <SwipeableTaskCard task={task}>
      <TaskCard
        task={task}
        completed={completed}
        focused={focused}
        selected={selected}
        hideListInfo={hideListInfo}
        {...(showListColor !== undefined && { showListColor })}
        onClick={handleClick}
      />
    </SwipeableTaskCard>
  );
});
