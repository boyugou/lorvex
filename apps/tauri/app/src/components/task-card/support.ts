import type {
  AriaRole,
  KeyboardEvent as ReactKeyboardEvent,
  MouseEvent as ReactMouseEvent,
} from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import type { Priority } from '@lorvex/shared/types';
import type { TranslationKey } from '@/lib/i18n';

export interface TaskCardProps {
  task: Task;
  rank?: number | undefined;
  completed?: boolean | undefined;
  disableComplete?: boolean;
  focused?: boolean;
  /** Whether the card is part of the current multi-selection (normal-mode visual highlight). */
  selected?: boolean;
  /** Hide list name badge (e.g. when already viewing the parent list). */
  hideListInfo?: boolean;
  /** Show the colored left border from the task's list. Default `true`. Set `false` in Today view for a calmer layout. */
  showListColor?: boolean;
  /**
   * Primary-activation click.  The optional event argument lets callers
   * inspect modifier keys (shift/meta/ctrl) to branch into multi-select
   * semantics without losing the "click to open task detail" default
   * behaviour. Handlers that don't care may keep the zero-arg signature.
   */
  onClick?: (event?: ReactMouseEvent<HTMLButtonElement>) => void;
  onKeyDown?: (event: ReactKeyboardEvent<HTMLButtonElement>) => void;
  taskButtonRole?: AriaRole;
  taskButtonAriaChecked?: boolean;
  taskButtonAriaLabel?: string;
  taskButtonAriaDescription?: string;
  taskButtonAriaRoleDescription?: string;
  taskButtonAriaKeyShortcuts?: string;
  taskButtonDisabled?: boolean;
  hideQuickActions?: boolean;
}

export interface TaskCardDisplayLabels {
  complete: string;
  reopen: string;
  completed: string;
  recurrence: string;
  minuteSuffix: string;
  dependsOn: string;
  overdue: string;
  dueToday: string;
  aiNotes: string;
  priorityLabels: Record<number, string>;
}

type TaskCardActionEvent =
  | ReactMouseEvent<HTMLButtonElement>
  | ReactKeyboardEvent<HTMLButtonElement>;

export type TaskCardActionHandler = (event: TaskCardActionEvent) => void;

export interface ChecklistProgress {
  total: number;
  done: number;
}

export const PRIORITY_ICONS: Record<number, string> = { 1: '⚑', 2: '◆', 3: '▲' };

/** Static i18n-safe priority label keys. Use instead of dynamic template literals. */
export const PRIORITY_LABEL_KEYS: Record<number, 'task.priorityP1' | 'task.priorityP2' | 'task.priorityP3'> = {
  1: 'task.priorityP1',
  2: 'task.priorityP2',
  3: 'task.priorityP3',
};

/**
 * Canonical priority palette. Co-located with PRIORITY_ICONS /
 * PRIORITY_LABEL_KEYS so a single edit site updates every priority
 * surface. Lifted from `quick-capture/toolbar/PriorityDropdown.tsx`
 * where it was duplicated.
 */
export const PRIORITY_COLORS: Record<Priority, string> = {
  1: 'text-danger',
  2: 'text-warning',
  3: 'text-accent',
};

interface PriorityNumericOption {
  value: Priority;
  labelKey: TranslationKey;
}

/**
 * Canonical priority options keyed by numeric `Priority`. Use for
 * editor menus (TaskUnifiedMetaCard, priorityMenuItems) where the
 * downstream call wants the numeric value.
 */
export const PRIORITY_NUMERIC_OPTIONS: readonly PriorityNumericOption[] = [
  { value: 1, labelKey: 'task.priorityP1' },
  { value: 2, labelKey: 'task.priorityP2' },
  { value: 3, labelKey: 'task.priorityP3' },
] as const;

interface PriorityStringOption {
  value: '1' | '2' | '3';
  labelKey: TranslationKey;
}

/**
 * Same set as PRIORITY_NUMERIC_OPTIONS but with `value` stringified —
 * the FilterDropdown contract requires string values so the underlying
 * `<select>`/menu can carry an "all" sentinel as `''`.
 */
// written as a tuple literal with `as const` so the value
// type narrows to `'1' | '2' | '3'`. The previous `.map(... as ...)`
// form lost the literal narrowing because `Array.prototype.map`
// returns the element type as the widened union the callback declares,
// not the per-row narrow tuple.
export const PRIORITY_OPTIONS = [
  { value: '1', labelKey: 'task.priorityP1' },
  { value: '2', labelKey: 'task.priorityP2' },
  { value: '3', labelKey: 'task.priorityP3' },
] as const satisfies readonly PriorityStringOption[];
export const TASK_COMPLETE_ANIMATION_DELAY_MS = 260;

export function parseChecklistProgress(task: Task): ChecklistProgress | null {
  const checklistItems = task.checklist_items ?? null;
  if (checklistItems && checklistItems.length > 0) {
    let done = 0;
    for (const item of checklistItems) {
      if (item.completed_at) {
        done += 1;
      }
    }
    return { total: checklistItems.length, done };
  }
  return null;
}
