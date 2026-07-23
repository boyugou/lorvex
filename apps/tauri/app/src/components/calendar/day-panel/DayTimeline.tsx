import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { eventColorStyles, eventDotColor } from '@/lib/colorUtils';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { Task } from '@/lib/ipc/tasks/models';
import { parseTimeToMinutes } from '@/lib/timeUtils';
import { isTerminalStatus } from '@lorvex/shared/types';
import type { PositionedEvent, PositionedTask } from '@/lib/timeline/types';
import { eventTypeIcon } from '../eventTypeIcon';
import type { TranslationKey } from '@/lib/i18n';
import { isEventPast } from '@/lib/time/useCurrentTime';
import {
  DAY_TIMELINE_HOUR_END,
  DAY_TIMELINE_ROW_HEIGHT,
  DAY_TIMELINE_HOUR_START,
  DAY_TIMELINE_SNAP_MINUTES,
  DAY_TIMELINE_TASK_KEYSHORTCUTS,
  dayTimelineLaneStyle,
  dayTimelineMinutesToTop,
  dayTimelineResizedMinutes,
  parseDayTimelineDragPayload,
  resolveDayTimelineInitialScrollTop,
  resolveDayTimelineKeyboardReschedule,
  serializeDayTimelineDragPayload,
} from './DayTimeline.logic';
import {
  timelineDurationToHeight,
  timelineMinutesToTimeString,
  timelineSnapMinutes,
  timelineTopToMinutes,
} from '../timelineLayout';
import {
  computeWeekTimelineSlots,
  type WeekTimelineSlotItem,
} from '../week-timeline/weekTimelineLayout';

const HOUR_START = DAY_TIMELINE_HOUR_START;
const HOUR_END = DAY_TIMELINE_HOUR_END;
const HOUR_COUNT = DAY_TIMELINE_HOUR_END - DAY_TIMELINE_HOUR_START;
const ROW_HEIGHT = DAY_TIMELINE_ROW_HEIGHT; // px per hour
const MIN_BLOCK_HEIGHT = 24; // px minimum for a block
const SNAP_MINUTES = DAY_TIMELINE_SNAP_MINUTES; // snap to 15-minute intervals
// Assumed durations when an item lacks an explicit span. Shared by the
// block height and the overlap packer so a chip's drawn extent and its
// lane assignment always agree.
const DEFAULT_EVENT_DURATION_MINUTES = 60;
const DEFAULT_TASK_DURATION_MINUTES = 30;
const DRAG_MIME = 'application/x-day-timeline-task';

function minutesToTop(minutes: number): number {
  return dayTimelineMinutesToTop(minutes);
}

function durationToHeight(estimatedMinutes: number): number {
  return timelineDurationToHeight(estimatedMinutes, MIN_BLOCK_HEIGHT);
}

function topToMinutes(top: number): number {
  return timelineTopToMinutes(top);
}

function snapMinutes(minutes: number): number {
  return timelineSnapMinutes(minutes);
}

function minutesToTimeStr(minutes: number): string {
  return timelineMinutesToTimeString(minutes);
}

interface DayTimelineProps {
  tasks: Task[];
  events: UnifiedCalendarEvent[];
  t: (key: TranslationKey) => string;
  onSelectTask: (id: string) => void;
  onCompleteTask?: (task: Task) => void;
  onRescheduleTask?: ((taskId: string, newTime: string, oldTime: string | null) => void) | undefined;
  onResizeTask?: ((taskId: string, newMinutes: number, oldMinutes: number | null) => void) | undefined;
  nowHHMM?: string | null;
}

export function DayTimeline({ tasks, events, t, onSelectTask, onCompleteTask, onRescheduleTask, onResizeTask, nowHHMM }: DayTimelineProps) {
  const gridRef = useRef<HTMLDivElement>(null);
  const [dropIndicatorTop, setDropIndicatorTop] = useState<number | null>(null);
  // Active task-duration resize (dragging a chip's bottom edge). The preview
  // minutes drive the chip height live; the start anchor + latest preview live
  // in refs so the pointerup handler reads fresh values regardless of closure.
  const [resizeTaskId, setResizeTaskId] = useState<string | null>(null);
  const [resizePreviewMinutes, setResizePreviewMinutes] = useState<number | null>(null);
  const resizeStartRef = useRef<{ clientY: number; startMinutes: number } | null>(null);
  const resizePreviewRef = useRef<number | null>(null);
  // Cache the grid's bounding rect during a drag to avoid calling
  // `getBoundingClientRect()` on every dragover event (~60/s). The
  // rect gets invalidated on dragleave/drop and on window resize.
  // The read happens in a layout-reading handler either way, but
  // stacking it 60x per second with arithmetic in between is the
  // exact pattern that triggers forced-reflow pauses.
  const dragRectCacheRef = useRef<DOMRect | null>(null);
  const initialScrollItems = useMemo(
    () => [
      ...events
        .filter((event) => !event.all_day && event.start_time)
        .map((event) => ({ startTime: event.start_time })),
      ...tasks
        .filter((task) => !isTerminalStatus(task.status) && task.due_time)
        .map((task) => ({ startTime: task.due_time })),
    ],
    [events, tasks],
  );
  const initialScrollSignature = useMemo(
    () => [
      nowHHMM ?? 'no-now',
      ...initialScrollItems.map((item) => item.startTime ?? ''),
    ].join('|'),
    [initialScrollItems, nowHHMM],
  );
  const lastInitialScrollSignatureRef = useRef<string | null>(null);

  // Auto-scroll to the day's first timed item; when the day has no
  // timed content, fall back to the current-time position.
  useEffect(() => {
    const container = gridRef.current;
    if (!container) return;
    if (lastInitialScrollSignatureRef.current === initialScrollSignature) return;
    lastInitialScrollSignatureRef.current = initialScrollSignature;
    container.scrollTop = resolveDayTimelineInitialScrollTop({
      nowHHMM,
      timedItems: initialScrollItems,
      viewportHeight: container.clientHeight,
    });
  }, [initialScrollItems, initialScrollSignature, nowHHMM]);

  const hours = useMemo(() =>
    Array.from({ length: HOUR_COUNT }, (_, i) => {
      const h = HOUR_START + i;
      return `${String(h).padStart(2, '0')}:00`;
    }),
  []);

  const { timedTasks, untimedTasks } = useMemo(() => {
    const timed: PositionedTask[] = [];
    const untimed: Task[] = [];

    for (const task of tasks) {
      if (isTerminalStatus(task.status)) continue;
      if (task.due_time) {
        const minutes = parseTimeToMinutes(task.due_time);
        if (minutes == null) {
          untimed.push(task);
          continue;
        }
        const duration = task.estimated_minutes ?? DEFAULT_TASK_DURATION_MINUTES;
        timed.push({
          task,
          top: minutesToTop(minutes),
          height: durationToHeight(duration),
        });
      } else {
        untimed.push(task);
      }
    }

    return { timedTasks: timed, untimedTasks: untimed };
  }, [tasks]);

  const positionedEvents = useMemo(() => {
    const result: PositionedEvent[] = [];
    for (const event of events) {
      if (event.all_day || !event.start_time) continue;
      const startMin = parseTimeToMinutes(event.start_time);
      if (startMin == null) continue;
      const endMin = parseTimeToMinutes(event.end_time) ?? startMin + DEFAULT_EVENT_DURATION_MINUTES;
      result.push({
        event,
        top: minutesToTop(startMin),
        height: durationToHeight(endMin - startMin),
      });
    }
    return result;
  }, [events]);

  const allDayEvents = useMemo(() => events.filter((e) => e.all_day), [events]);
  const gridHeight = HOUR_COUNT * ROW_HEIGHT;

  // Pack overlapping timed chips into side-by-side columns. Events and
  // tasks share one lane assignment so a meeting and a same-slot task
  // sit beside each other rather than occluding. Reuses the week view's
  // clustered interval packer keyed by prefixed id (`evt:` / `task:`) so
  // the two id spaces can't collide.
  const laneSlots = useMemo(() => {
    const items: WeekTimelineSlotItem[] = [
      ...positionedEvents.map((pe) => ({
        id: `evt:${pe.event.id}`,
        start: pe.event.start_time,
        end: pe.event.end_time,
        fallbackDurationMinutes: DEFAULT_EVENT_DURATION_MINUTES,
      })),
      ...timedTasks.map((pt) => ({
        id: `task:${pt.task.id}`,
        start: pt.task.due_time,
        end: null,
        fallbackDurationMinutes: pt.task.estimated_minutes ?? DEFAULT_TASK_DURATION_MINUTES,
      })),
    ];
    return computeWeekTimelineSlots(items);
  }, [positionedEvents, timedTasks]);

  // While a task's duration is being resized, its chip height + minutes label
  // preview the in-progress value; otherwise they reflect the stored estimate.
  const resolvedTaskHeight = (pt: PositionedTask): number =>
    resizeTaskId === pt.task.id && resizePreviewMinutes != null
      ? durationToHeight(resizePreviewMinutes)
      : pt.height;
  const resolvedTaskMinutes = (pt: PositionedTask): number | null =>
    resizeTaskId === pt.task.id && resizePreviewMinutes != null
      ? resizePreviewMinutes
      : pt.task.estimated_minutes ?? null;

  // Clear all resize state/refs. Invoked on a committed pointerup AND as the
  // catch-all on lost pointer capture (interrupted drag / pointercancel) so a
  // cancelled resize can't leave a chip frozen at its preview height.
  const resetResize = () => {
    resizeStartRef.current = null;
    resizePreviewRef.current = null;
    setResizeTaskId(null);
    setResizePreviewMinutes(null);
  };

  const computeDropTime = useCallback((clientY: number): { top: number; timeStr: string } | null => {
    if (!gridRef.current) return null;
    // Reuse the cached rect within a drag session. Populated lazily
    // on first dragover; cleared on dragleave/drop.
    let rect = dragRectCacheRef.current;
    if (!rect) {
      rect = gridRef.current.getBoundingClientRect();
      dragRectCacheRef.current = rect;
    }
    const relativeY = clientY - rect.top + gridRef.current.scrollTop;
    const rawMinutes = topToMinutes(Math.max(0, relativeY));
    const snapped = snapMinutes(rawMinutes);
    const clampedMinutes = Math.max(HOUR_START * 60, Math.min(snapped, HOUR_END * 60 - SNAP_MINUTES));
    return {
      top: minutesToTop(clampedMinutes),
      timeStr: minutesToTimeStr(clampedMinutes),
    };
  }, []);

  const handleGridDragOver = useCallback((event: React.DragEvent) => {
    if (!event.dataTransfer.types.includes(DRAG_MIME)) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = 'move';
    const result = computeDropTime(event.clientY);
    if (result) setDropIndicatorTop(result.top);
  }, [computeDropTime]);

  const handleGridDragLeave = useCallback((event: React.DragEvent) => {
    if (event.currentTarget.contains(event.relatedTarget as Node)) return;
    dragRectCacheRef.current = null;
    setDropIndicatorTop(null);
  }, []);

  const handleGridDrop = useCallback((event: React.DragEvent) => {
    event.preventDefault();
    setDropIndicatorTop(null);
    if (!onRescheduleTask) {
      dragRectCacheRef.current = null;
      return;
    }
    const payload = event.dataTransfer.getData(DRAG_MIME);
    if (!payload) {
      dragRectCacheRef.current = null;
      return;
    }
    const parsed = parseDayTimelineDragPayload(payload);
    if (!parsed) {
      dragRectCacheRef.current = null;
      return;
    }
    const { taskId, oldTime } = parsed;
    const result = computeDropTime(event.clientY);
    dragRectCacheRef.current = null;
    if (!result) return;
    // branch the drop explicitly so each outcome is
    // unambiguous. Same-time drop swallows silently (the visual
    // indicator is already cleared); a real time change forwards to
    // the parent reschedule handler. The parent owns busy-state /
    // toast feedback so we don't double-fire here.
    if (result.timeStr === oldTime) return;
    onRescheduleTask(taskId, result.timeStr, oldTime);
  }, [computeDropTime, onRescheduleTask]);

  const makeTaskDragStart = useCallback((taskId: string, oldTime: string | null) =>
    (event: React.DragEvent) => {
      event.dataTransfer.effectAllowed = 'move';
      event.dataTransfer.setData(DRAG_MIME, serializeDayTimelineDragPayload(taskId, oldTime));
    },
  []);

  const makeTaskKeyDown = useCallback((taskId: string, oldTime: string | null) =>
    (event: React.KeyboardEvent) => {
      if (!onRescheduleTask) return;
      const nextTime = resolveDayTimelineKeyboardReschedule({
        key: event.key,
        oldTime,
        shiftKey: event.shiftKey,
        metaKey: event.metaKey,
        ctrlKey: event.ctrlKey,
        altKey: event.altKey,
      });
      if (!nextTime) return;
      event.preventDefault();
      event.stopPropagation();
      onRescheduleTask(taskId, nextTime, oldTime);
    },
  [onRescheduleTask]);

  return (
    <div className="flex flex-col gap-2 h-full">
      {/* All-day events */}
      {allDayEvents.length > 0 && (
        <div className="shrink-0 space-y-1">
          <p className="text-xs font-medium text-text-muted">{t('calendar.eventAllDay')}</p>
          {allDayEvents.map((event) => (
            <div
              key={event.id}
              className="flex items-center gap-2 px-2 py-1 rounded-r-control text-xs"
              style={{ backgroundColor: eventColorStyles(event.color ?? null, 'medium').backgroundColor }}
            >
              <div
                className="w-1.5 h-1.5 rounded-full shrink-0"
                style={{ backgroundColor: eventDotColor(event.color ?? null) }}
              />
              <span className="text-text-primary truncate">{eventTypeIcon(event.event_type)}{event.title}</span>
            </div>
          ))}
        </div>
      )}

      {/* Untimed tasks */}
      {untimedTasks.length > 0 && (
        <div className="shrink-0 space-y-1">
          <p className="text-xs font-medium text-text-muted">{t('upcoming.noTime')}</p>
          {untimedTasks.map((task) => (
            // HTML5 draggable wrapper. Inner buttons handle pointer
            // and keyboard activation for complete/open.
            // eslint-disable-next-line jsx-a11y/no-static-element-interactions
            <div
              key={task.id}
              draggable={!!onRescheduleTask}
              onDragStart={makeTaskDragStart(task.id, null)}
              className={`w-full flex items-center gap-2 px-2 py-1.5 rounded-r-control text-xs text-start bg-surface-2 hover:bg-surface-3 transition-colors ${onRescheduleTask ? 'cursor-grab active:cursor-grabbing' : ''}`}
            >
              {onCompleteTask && (
                <button
                  type="button"
                  onClick={(e) => { e.stopPropagation(); onCompleteTask(task); }}
                  aria-label={`${t('task.complete')}: ${task.title}`}
                  className="shrink-0 w-3.5 h-3.5 rounded-full border border-text-muted/30 hover:border-success/50 transition-colors focus-ring-soft"
                />
              )}
              <button
                type="button"
                onClick={() => onSelectTask(task.id)}
                onKeyDown={makeTaskKeyDown(task.id, null)}
                aria-keyshortcuts={onRescheduleTask ? DAY_TIMELINE_TASK_KEYSHORTCUTS : undefined}
                aria-description={onRescheduleTask ? t('calendar.dayTimelineKeyboardHint') : undefined}
                aria-label={task.title}
                className="flex-1 min-w-0 text-start focus-ring-soft rounded-r-control"
              >
                <span className="text-text-primary truncate block">{task.title}</span>
              </button>
              {task.estimated_minutes && (
                <span className="text-text-muted ms-auto shrink-0">{task.estimated_minutes} {t('common.min')}</span>
              )}
            </div>
          ))}
        </div>
      )}

      {/* Hourly timeline grid — drop zone for HTML5 drag-and-drop.
          No user-action contract beyond receiving a drop. */}
      {/* eslint-disable-next-line jsx-a11y/no-static-element-interactions */}
      <div
        ref={gridRef}
        className="flex-1 overflow-y-auto overscroll-contain"
        onDragOver={handleGridDragOver}
        onDragLeave={handleGridDragLeave}
        onDrop={handleGridDrop}
      >
        <div className="relative" style={{ height: gridHeight }}>
          {/* Hour lines */}
          {hours.map((hour, i) => (
            <div
              key={hour}
              className="absolute start-0 end-0 flex items-start"
              style={{ top: i * ROW_HEIGHT }}
            >
              <span className="text-2xs text-text-muted/80 w-10 shrink-0 -mt-1.5 tabular-nums">
                {hour}
              </span>
              <div className="flex-1 border-t border-card" />
            </div>
          ))}

          {/* Drop indicator /: positioned task and event blocks
              below render absolutely without an explicit z-index. Under
              the default static stacking order, siblings declared
              LATER in the DOM paint on top of earlier ones — and the
              task/event blocks are declared after the indicator, so a
              `--z-base` indicator would still be hidden behind any
              task block that overlapped its top line. The drop
              indicator therefore takes `z-[calc(var(--z-popover)-1)]`
              — the canonical "hover overlay above sticky" tier — so
              it paints above every event/task block but still below
              modals/popovers proper. The current-time indicator stays
              at `--z-sticky`; the drop indicator outranks it
              intentionally because an active drag is the user's
              foreground intent. */}
          {dropIndicatorTop != null && (
            <div
              className="absolute start-10 end-1 h-0.5 bg-accent/60 rounded-full pointer-events-none z-[calc(var(--z-popover)-1)]"
              style={{ top: dropIndicatorTop }}
            >
              <span className="absolute -top-2.5 -start-0.5 text-3xs text-accent font-medium tabular-nums">
                {minutesToTimeStr(topToMinutes(dropIndicatorTop))}
              </span>
            </div>
          )}

          {/* Current time indicator */}
          {nowHHMM && (() => {
            const nowMin = parseTimeToMinutes(nowHHMM);
            if (nowMin == null) return null;
            if (nowMin < HOUR_START * 60 || nowMin > HOUR_END * 60) return null;
            const nowTop = minutesToTop(nowMin);
            return (
              <div
                role="img"
                aria-label={`${t('calendar.currentTime')} ${nowHHMM}`}
                className="absolute start-8 end-0 flex items-center pointer-events-none z-[var(--z-sticky)]"
                style={{ top: nowTop }}
              >
                <div className="w-2 h-2 rounded-full bg-danger shrink-0 -ms-1" />
                <div className="flex-1 h-px bg-[var(--danger-tint-xl)]" />
              </div>
            );
          })()}

          {/* Positioned events */}
          {positionedEvents.map((pe) => {
            const past = nowHHMM ? isEventPast(pe.event, nowHHMM) : false;
            const lane = dayTimelineLaneStyle(laneSlots.get(`evt:${pe.event.id}`));
            return (
            <div
              key={pe.event.id}
              className={`absolute rounded-r-control px-2 py-1 overflow-hidden ${past ? 'opacity-40' : ''}`}
              style={(() => {
                const s = eventColorStyles(pe.event.color ?? null, 'soft');
                return {
                  top: pe.top,
                  height: pe.height,
                  insetInlineStart: lane.insetInlineStart,
                  width: lane.width,
                  backgroundColor: s.backgroundColor,
                  borderInlineStart: s.borderInlineStart,
                };
              })()}
            >
              <p className={`text-2xs truncate leading-tight ${past ? 'text-text-muted line-through' : 'text-text-primary'}`}>{eventTypeIcon(pe.event.event_type)}{pe.event.title}</p>
              {pe.event.start_time && (
                <p className="text-2xs text-text-muted">
                  {pe.event.start_time}{pe.event.end_time ? ` – ${pe.event.end_time}` : ''}
                </p>
              )}
            </div>
            );
          })}

          {/* Positioned tasks: the entire task block is the click
              target. Pre-fix, the outer `<div>` carried the visible
              padding (`px-2 py-1`) but the inner `<button>` only
              filled `w-full` of the inner content area — so the 2px
              vertical / 8px horizontal halo of "task block" pixels
              looked clickable but absorbed clicks silently. We keep
              the wrapper div for drag affordance + visual chrome
              and make the button itself span the wrapper (`absolute
              inset-0`), pulling padding INTO the button so every
              pixel of the visible block opens the task detail. */}
          {timedTasks.map((pt) => (
            // HTML5 draggable wrapper. Inner button (absolute inset-0)
            // is the actionable target for pointer + keyboard open.
            // eslint-disable-next-line jsx-a11y/no-static-element-interactions
            <div
              key={pt.task.id}
              draggable={!!onRescheduleTask}
              onDragStart={makeTaskDragStart(pt.task.id, pt.task.due_time ?? null)}
              className={`absolute rounded-r-control bg-accent/10 border border-accent/20 overflow-hidden text-start hover:bg-accent/15 transition-colors ${onRescheduleTask ? 'cursor-grab active:cursor-grabbing' : ''}`}
              style={(() => {
                const lane = dayTimelineLaneStyle(laneSlots.get(`task:${pt.task.id}`));
                return {
                  top: pt.top,
                  height: resolvedTaskHeight(pt),
                  insetInlineStart: lane.insetInlineStart,
                  width: lane.width,
                };
              })()}
            >
              <button
                type="button"
                onClick={() => onSelectTask(pt.task.id)}
                onKeyDown={makeTaskKeyDown(pt.task.id, pt.task.due_time ?? null)}
                aria-keyshortcuts={onRescheduleTask ? DAY_TIMELINE_TASK_KEYSHORTCUTS : undefined}
                aria-description={onRescheduleTask ? t('calendar.dayTimelineKeyboardHint') : undefined}
                className="absolute inset-0 w-full h-full text-start px-2 py-1 focus-ring-soft rounded-r-control"
              >
                <p className="text-2xs text-text-primary truncate leading-tight">{pt.task.title}</p>
                {pt.task.due_time && (
                  <p className="text-2xs text-text-muted">
                    {pt.task.due_time}
                    {resolvedTaskMinutes(pt) != null ? ` · ${resolvedTaskMinutes(pt)} ${t('common.min')}` : ''}
                  </p>
                )}
              </button>
            </div>
          ))}

          {/* Duration resize handles. Rendered as siblings (not children) of the
              draggable task chips so grabbing a handle never starts an HTML5
              move-drag. Dragging the bottom edge changes the task's
              estimated_minutes; the chip height previews live. */}
          {onResizeTask && timedTasks.map((pt) => {
            const lane = dayTimelineLaneStyle(laneSlots.get(`task:${pt.task.id}`));
            const startMinutes = pt.task.estimated_minutes ?? DEFAULT_TASK_DURATION_MINUTES;
            return (
              <div
                key={`resize-${pt.task.id}`}
                className="absolute h-1.5 cursor-ns-resize touch-none z-[var(--z-sticky)]"
                style={{
                  top: pt.top + resolvedTaskHeight(pt) - 3,
                  insetInlineStart: lane.insetInlineStart,
                  width: lane.width,
                }}
                onPointerDown={(event) => {
                  event.preventDefault();
                  event.stopPropagation();
                  event.currentTarget.setPointerCapture(event.pointerId);
                  resizeStartRef.current = { clientY: event.clientY, startMinutes };
                  resizePreviewRef.current = startMinutes;
                  setResizeTaskId(pt.task.id);
                  setResizePreviewMinutes(startMinutes);
                }}
                onPointerMove={(event) => {
                  // Guard on the ref (set synchronously in pointerdown), not on
                  // `resizeTaskId` (a stale closure value until the next render),
                  // so the preview tracks from the first move. Pointer capture
                  // guarantees only the active handle receives these.
                  const start = resizeStartRef.current;
                  if (!start) return;
                  const next = dayTimelineResizedMinutes({
                    startMinutes: start.startMinutes,
                    deltaY: event.clientY - start.clientY,
                    rowHeight: ROW_HEIGHT,
                    snapMinutes: SNAP_MINUTES,
                    minMinutes: SNAP_MINUTES,
                  });
                  resizePreviewRef.current = next;
                  setResizePreviewMinutes(next);
                }}
                onPointerUp={(event) => {
                  event.currentTarget.releasePointerCapture(event.pointerId);
                  const next = resizePreviewRef.current;
                  resetResize();
                  if (next != null && next !== startMinutes) {
                    onResizeTask(pt.task.id, next, pt.task.estimated_minutes ?? null);
                  }
                }}
                onLostPointerCapture={resetResize}
                aria-hidden
              />
            );
          })}
        </div>
      </div>
    </div>
  );
}
