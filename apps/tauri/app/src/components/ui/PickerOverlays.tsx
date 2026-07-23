import type { Task } from '@/lib/ipc/tasks/models';
import { ListPickerOverlay } from './ListPickerOverlay';
import { DueDatePickerOverlay } from './DueDatePickerOverlay';
import { DurationPickerOverlay } from './DurationPickerOverlay';
import { RecurrencePickerOverlay } from './RecurrencePickerOverlay';

interface PickerOverlaysProps {
  tasks: Task[];
  movePickerTaskId: string | null;
  closeMovePickerAction: () => void;
  recurrencePickerTaskId: string | null;
  closeRecurrencePickerAction: () => void;
  dueDatePickerTaskId: string | null;
  closeDueDatePickerAction: () => void;
  durationPickerTaskId: string | null;
  closeDurationPickerAction: () => void;
}

export function PickerOverlays({
  tasks,
  movePickerTaskId,
  closeMovePickerAction,
  recurrencePickerTaskId,
  closeRecurrencePickerAction,
  dueDatePickerTaskId,
  closeDueDatePickerAction,
  durationPickerTaskId,
  closeDurationPickerAction,
}: PickerOverlaysProps): React.JSX.Element {
  return (
    <>
      {movePickerTaskId && (
        <ListPickerOverlay taskId={movePickerTaskId} tasks={tasks} onClose={closeMovePickerAction} />
      )}
      {recurrencePickerTaskId && (
        <RecurrencePickerOverlay taskId={recurrencePickerTaskId} tasks={tasks} onClose={closeRecurrencePickerAction} />
      )}
      {dueDatePickerTaskId && (
        <DueDatePickerOverlay taskId={dueDatePickerTaskId} tasks={tasks} onClose={closeDueDatePickerAction} />
      )}
      {durationPickerTaskId && (
        <DurationPickerOverlay taskId={durationPickerTaskId} tasks={tasks} onClose={closeDurationPickerAction} />
      )}
    </>
  );
}
