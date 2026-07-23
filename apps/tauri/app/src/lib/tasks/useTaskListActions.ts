import { useMemo, useRef } from 'react';
import { useQueryClient } from '@tanstack/react-query';

import { useConfiguredDayContext } from '../dayContext';
import { useI18n } from '../i18n';
import type { Task } from '@/lib/ipc/tasks/models';
import { useTaskLifecycleActions } from './taskActions/lifecycle';
import { useTaskMetadataActions } from './taskActions/metadata';
import { useTaskOverlayActions } from './taskActions/overlays';
import { useTaskSchedulingActions } from './taskActions/scheduling';
import type { TaskListKeyboardActions } from './useTaskListKeyboard';

export interface TaskListActionsResult extends TaskListKeyboardActions {
  /** When non-null, the list picker overlay should be shown for this task. */
  movePickerTaskId: string | null;
  /** Close the move picker overlay. */
  closeMovePickerAction: () => void;
  /** When non-null, the recurrence picker overlay should be shown for this task. */
  recurrencePickerTaskId: string | null;
  /** Close the recurrence picker overlay. */
  closeRecurrencePickerAction: () => void;
  /** When non-null, the due date picker overlay should be shown for this task. */
  dueDatePickerTaskId: string | null;
  /** Close the due date picker overlay. */
  closeDueDatePickerAction: () => void;
  /** When non-null, the duration picker overlay should be shown for this task. */
  durationPickerTaskId: string | null;
  /** Close the duration picker overlay. */
  closeDurationPickerAction: () => void;
}

/**
 * Provides keyboard action callbacks (complete, defer, move, etc.) for task list views.
 * Pass the returned `actions` object to `useTaskListKeyboard({ actions })`.
 * Also returns overlay state for ListPickerOverlay and RecurrencePickerOverlay.
 */
export function useTaskListActions(
  tasks: Task[],
): TaskListActionsResult {
  const { t, format } = useI18n();
  const qc = useQueryClient();
  const dayContext = useConfiguredDayContext();

  const tasksRef = useRef(tasks);
  tasksRef.current = tasks;
  const dayContextRef = useRef(dayContext);
  dayContextRef.current = dayContext;

  const lifecycle = useTaskLifecycleActions({ tasksRef, qc, t, format });
  const scheduling = useTaskSchedulingActions({ tasksRef, dayContextRef, qc, t });
  const metadata = useTaskMetadataActions({ tasksRef, qc, t });
  const overlays = useTaskOverlayActions({ tasksRef });

  return useMemo(
    () => ({
      onCancelTask: lifecycle.onCancelTask,
      onComplete: lifecycle.onComplete,
      onDuplicate: lifecycle.onDuplicate,
      onEdit: overlays.onEdit,
      onMoveToList: overlays.onMoveToList,
      onOpenContextMenu: overlays.onOpenContextMenu,
      onPromoteToActive: lifecycle.onPromoteToActive,
      onSetDueDate: overlays.onSetDueDate,
      onSetDueToday: scheduling.onSetDueToday,
      onSetDueTomorrow: scheduling.onSetDueTomorrow,
      onSetDuration: overlays.onSetDuration,
      onSetPriority: metadata.onSetPriority,
      onSetRecurrence: overlays.onSetRecurrence,
      onDefer: scheduling.onDefer,
      onDeferNextWeek: scheduling.onDeferNextWeek,
      onToggleRecurrence: metadata.onToggleRecurrence,
      movePickerTaskId: overlays.movePickerTaskId,
      closeMovePickerAction: overlays.closeMovePickerAction,
      recurrencePickerTaskId: overlays.recurrencePickerTaskId,
      closeRecurrencePickerAction: overlays.closeRecurrencePickerAction,
      dueDatePickerTaskId: overlays.dueDatePickerTaskId,
      closeDueDatePickerAction: overlays.closeDueDatePickerAction,
      durationPickerTaskId: overlays.durationPickerTaskId,
      closeDurationPickerAction: overlays.closeDurationPickerAction,
    }),
    [
      lifecycle.onCancelTask,
      lifecycle.onComplete,
      lifecycle.onDuplicate,
      lifecycle.onPromoteToActive,
      metadata.onSetPriority,
      metadata.onToggleRecurrence,
      overlays.closeDueDatePickerAction,
      overlays.closeDurationPickerAction,
      overlays.closeMovePickerAction,
      overlays.closeRecurrencePickerAction,
      overlays.dueDatePickerTaskId,
      overlays.durationPickerTaskId,
      overlays.movePickerTaskId,
      overlays.onEdit,
      overlays.onMoveToList,
      overlays.onOpenContextMenu,
      overlays.onSetDueDate,
      overlays.onSetDuration,
      overlays.onSetRecurrence,
      overlays.recurrencePickerTaskId,
      scheduling.onDefer,
      scheduling.onDeferNextWeek,
      scheduling.onSetDueToday,
      scheduling.onSetDueTomorrow,
    ],
  );
}
