/**
 * Shared positioning types for vertical day-grid timelines.
 *
 * Both the day-panel `DayTimeline` and the upcoming `WeekTimeline` lay
 * out tasks/events on a fixed-pixel-per-hour grid: each domain object
 * gets a `top` (y-offset in px from the start hour) and a `height` (px
 * span for its duration). The hour scale itself is per-component (the
 * day panel uses a denser scale than the week overview), but the
 * positioned-record shape is identical.
 */

import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { Task } from '@/lib/ipc/tasks/models';

export interface PositionedTask {
  task: Task;
  top: number;
  height: number;
}

export interface PositionedEvent {
  event: UnifiedCalendarEvent;
  top: number;
  height: number;
}
