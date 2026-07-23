/**
 * Reschedule callback for the week timeline. A drop carries the target column
 * `newDate`, the source `oldDate` + `oldTime` (for a complete undo), the time
 * inferred from the drop's Y offset (`dueTime`, wire "HH:MM"), and
 * `hasPlannedDate` (route the date to `planned_date` vs `due_date`). The
 * consumer sets day + time in one update.
 */
export type WeekGridTaskReschedule =
  | ((
      taskId: string,
      newDate: string,
      oldDate: string | null,
      oldTime: string | null,
      dueTime: string,
      hasPlannedDate?: boolean,
    ) => void)
  | undefined;
