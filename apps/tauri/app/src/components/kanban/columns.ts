import type { TaskStatus } from '@lorvex/shared/types';

export type ColumnKey = 'open' | 'someday' | 'completed';

export const COLUMN_ORDER: ColumnKey[] = ['open', 'someday', 'completed'];

export const STATUS_TO_COLUMN: Partial<Record<TaskStatus, ColumnKey>> = {
  open: 'open',
  someday: 'someday',
  completed: 'completed',
  cancelled: 'completed',
};

/**
 * column → canonical task status mapping. The inverse of
 * `STATUS_TO_COLUMN` (which folds `cancelled` into the `completed`
 * column for display); on a drop the backend writes `completed` /
 * `someday` / `open` so the optimistic patch needs the canonical
 * status the column resolves to. Co-located here so consumers (kanban
 * column actions, drag handlers, tests) share one source of truth.
 */
export const COLUMN_TO_STATUS: Record<ColumnKey, TaskStatus> = {
  open: 'open',
  someday: 'someday',
  completed: 'completed',
};

export const COLUMN_STYLE: Record<ColumnKey, string> = {
  open: 'border-accent/30 bg-accent/5',
  someday: 'border-surface-3 bg-surface-2/60',
  completed: 'border-success/30 bg-[var(--success-tint-xs)]',
};

export const COLUMN_LABEL_KEYS: Record<ColumnKey, 'kanban.column.open' | 'kanban.column.someday' | 'kanban.column.completed'> = {
  open: 'kanban.column.open',
  someday: 'kanban.column.someday',
  completed: 'kanban.column.completed',
};

export const COLUMN_MOVE_LABEL_KEYS: Record<
  ColumnKey,
  'kanban.mobile.moveToOpen' | 'kanban.mobile.moveToSomeday' | 'kanban.mobile.moveToCompleted'
> = {
  open: 'kanban.mobile.moveToOpen',
  someday: 'kanban.mobile.moveToSomeday',
  completed: 'kanban.mobile.moveToCompleted',
};

export const DRAG_MIME = 'application/x-kanban-task';
