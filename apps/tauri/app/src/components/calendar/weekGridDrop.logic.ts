// Pure decision helpers for the week timeline's drop handler. The DOM/geometry
// (rect, scrollTop, clientY) lives in WeekTimelineGrid; everything here is
// node-testable (`.logic.ts` only, no jsdom + React), mirroring the day
// timeline's logic/component split.
import { decodeCalendarTaskDrag } from './calendarViewUtils';
import {
  WEEK_TIMELINE_HOUR_END,
  WEEK_TIMELINE_HOUR_START,
  WEEK_TIMELINE_SNAP_MINUTES,
  weekTimelineMinutesToTimeString,
  weekTimelineMinutesToTop,
  weekTimelineSnapMinutes,
  weekTimelineTopToMinutes,
} from './week-timeline/weekTimelineLayout';

type WeekGridDropOutcome =
  | { kind: 'ignore' } // bad payload, missing handler, or no-op (same day + same time)
  | {
      kind: 'reschedule';
      taskId: string;
      newDate: string;
      oldDate: string | null;
      oldTime: string | null;
      dueTime: string;
      hasPlannedDate: boolean;
    };

/**
 * Map a drop's Y offset (pixels from the top of the timeline body, with
 * scrollTop already folded in) to a snapped wall-clock time on the week grid.
 *
 * Inverts {@link weekTimelineMinutesToTop} via the shared timeline geometry,
 * snaps to the 15-minute grid, then clamps into `[HOUR_START*60,
 * HOUR_END*60 - SNAP]` so a drop at the very bottom lands on the last usable
 * slot rather than midnight of the next day. Returns the snapped `top` (for a
 * drop indicator) alongside the wire "HH:MM" `timeStr`.
 */
export function resolveWeekTimelineDropTime(relativeY: number): { top: number; timeStr: string } {
  const rawMinutes = weekTimelineTopToMinutes(Math.max(0, relativeY));
  const snapped = weekTimelineSnapMinutes(rawMinutes);
  const clamped = Math.max(
    WEEK_TIMELINE_HOUR_START * 60,
    Math.min(snapped, WEEK_TIMELINE_HOUR_END * 60 - WEEK_TIMELINE_SNAP_MINUTES),
  );
  return {
    top: weekTimelineMinutesToTop(clamped),
    timeStr: weekTimelineMinutesToTimeString(clamped),
  };
}

/**
 * Resolve a calendar drop payload against a week-timeline column date + the
 * time inferred from the drop's Y position.
 *
 * - `{ kind: 'ignore' }` when the payload is invalid or the consumer did not
 *   wire `onRescheduleTask`.
 * - `{ kind: 'ignore' }` for a true no-op: the column date matches the task's
 *   source date AND the inferred time equals the task's existing `due_time`.
 *   A same-day drop at a different Y is NOT a no-op — it re-times the task.
 * - `{ kind: 'reschedule', ... }` otherwise, carrying both the column `newDate`
 *   and the inferred `dueTime` so the consumer sets day + time in one update.
 */
export function resolveWeekGridDrop(
  rawPayload: string,
  dateStr: string,
  inferredTime: string,
  hasRescheduleHandler: boolean,
): WeekGridDropOutcome {
  const payload = decodeCalendarTaskDrag(rawPayload);
  if (!payload || !hasRescheduleHandler) return { kind: 'ignore' };
  if (payload.oldDate === dateStr && payload.oldTime === inferredTime) {
    return { kind: 'ignore' };
  }
  return {
    kind: 'reschedule',
    taskId: payload.id,
    newDate: dateStr,
    oldDate: payload.oldDate,
    oldTime: payload.oldTime,
    dueTime: inferredTime,
    hasPlannedDate: payload.hasPlannedDate,
  };
}
