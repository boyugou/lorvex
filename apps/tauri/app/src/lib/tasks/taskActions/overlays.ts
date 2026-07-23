import { useCallback, useRef, useState } from 'react';

import {
  createBrowserTaskListActionHost,
  dispatchTaskListElementEvent,
} from '../useTaskListActions.runtime';
import { getActiveTask, type TaskListActionDeps } from './shared';

// CONTRACT: `taskListActionHost` must remain stateless. Vite HMR does
// NOT reset module-level `const` values across reloads, so any
// in-host state added here would be silently shared across mount
// cycles. To add stateful behavior, move construction inside the
// effect/hook that consumes it.
const taskListActionHost = createBrowserTaskListActionHost();

interface PickerState {
  taskId: string | null;
  open: (id: string) => void;
  close: () => void;
}

function usePickerState(): PickerState {
  const [taskId, setTaskId] = useState<string | null>(null);
  const controlsRef = useRef<{ open: (id: string) => void; close: () => void } | null>(null);
  if (controlsRef.current === null) {
    controlsRef.current = {
      open: (id: string) => setTaskId(id),
      close: () => setTaskId(null),
    };
  }
  return { taskId, open: controlsRef.current.open, close: controlsRef.current.close };
}

export function useTaskOverlayActions({
  tasksRef,
}: Pick<TaskListActionDeps, 'tasksRef'>) {
  const movePicker = usePickerState();
  const recurrencePicker = usePickerState();
  const dueDatePicker = usePickerState();
  const durationPicker = usePickerState();

  const onEdit = useCallback((taskId: string) => {
    dispatchTaskListElementEvent({
      eventName: 'lorvex:start-edit-title',
      host: taskListActionHost,
      taskId,
    });
  }, []);

  const onMoveToList = useCallback((taskId: string) => {
    const task = getActiveTask(tasksRef.current, taskId);
    if (!task) return;
    movePicker.open(taskId);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [movePicker.open, tasksRef]);

  const onSetRecurrence = useCallback((taskId: string) => {
    const task = getActiveTask(tasksRef.current, taskId);
    if (!task) return;
    recurrencePicker.open(taskId);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [recurrencePicker.open, tasksRef]);

  const onSetDueDate = useCallback((taskId: string) => {
    const task = getActiveTask(tasksRef.current, taskId);
    if (!task) return;
    dueDatePicker.open(taskId);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dueDatePicker.open, tasksRef]);

  const onSetDuration = useCallback((taskId: string) => {
    const task = getActiveTask(tasksRef.current, taskId);
    if (!task) return;
    durationPicker.open(taskId);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [durationPicker.open, tasksRef]);

  const onOpenContextMenu = useCallback((taskId: string) => {
    dispatchTaskListElementEvent({
      eventName: 'lorvex:open-context-menu',
      host: taskListActionHost,
      taskId,
    });
  }, []);

  return {
    closeDueDatePickerAction: dueDatePicker.close,
    closeDurationPickerAction: durationPicker.close,
    closeMovePickerAction: movePicker.close,
    closeRecurrencePickerAction: recurrencePicker.close,
    dueDatePickerTaskId: dueDatePicker.taskId,
    durationPickerTaskId: durationPicker.taskId,
    movePickerTaskId: movePicker.taskId,
    onEdit,
    onMoveToList,
    onOpenContextMenu,
    onSetDueDate,
    onSetDuration,
    onSetRecurrence,
    recurrencePickerTaskId: recurrencePicker.taskId,
  };
}
