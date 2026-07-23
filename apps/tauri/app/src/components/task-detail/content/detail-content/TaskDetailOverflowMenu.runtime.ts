type TaskDetailOverflowFocusable = Pick<HTMLElement, 'focus'>;

export type TaskDetailOverflowKeyAction =
  | { type: 'none' }
  | { type: 'close' }
  | { type: 'focus'; index: number };

export function resolveTaskDetailOverflowKeyAction({
  key,
  currentIndex,
  itemCount,
}: {
  key: string;
  currentIndex: number;
  itemCount: number;
}): TaskDetailOverflowKeyAction {
  if (key === 'Escape') return { type: 'close' };
  if (itemCount <= 0) return { type: 'none' };
  if (key === 'ArrowDown') {
    return { type: 'focus', index: currentIndex === -1 ? 0 : currentIndex + 1 };
  }
  if (key === 'ArrowUp') {
    return { type: 'focus', index: currentIndex === -1 ? itemCount - 1 : currentIndex - 1 };
  }
  if (key === 'Home') return { type: 'focus', index: 0 };
  if (key === 'End') return { type: 'focus', index: itemCount - 1 };
  return { type: 'none' };
}

export function focusTaskDetailOverflowMenuItem({
  items,
  panel,
  index,
}: {
  items: TaskDetailOverflowFocusable[];
  panel: TaskDetailOverflowFocusable | null;
  index: number;
}): number | null {
  if (items.length === 0) {
    panel?.focus();
    return null;
  }
  const nextIndex = (index + items.length) % items.length;
  items[nextIndex]?.focus();
  return nextIndex;
}
