import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { CalendarEvent, UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { Task } from '@/lib/ipc/tasks/models';
import type { TranslationKey } from '@/lib/i18n';
import { useListJkNavigation } from '@/lib/useListJkNavigation';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { formatCalendarDate } from '@/lib/dates/dateLocale';
import {
  formatCalendarDayPanelSummary,
  formatOpenTaskCountLabel,
} from '@/lib/dates/i18nCountPhrases';
import { isEventPast, useCurrentTime } from '@/lib/time/useCurrentTime';
import { Tooltip } from '@/components/ui/Tooltip';
import { EventForm } from '../event-form';
import { DayEventRow } from './DayEventRow';
import { useDayPanelTaskActions } from './useDayPanelTaskActions';
import { DayTask } from './DayTask';
import { DayTimeline } from './DayTimeline';
import { TASK_STATUS } from '@lorvex/shared/types';

export function DayPanel({
  date,
  tasks,
  events,
  locale,
  t,
  onSelectTask,
  onInvalidate,
  autoShowAddEvent = false,
  onAutoShowAddEventConsumed,
  isMobile = false,
  onClose,
}: {
  date: string;
  tasks: Task[];
  events: UnifiedCalendarEvent[];
  locale: string;
  t: (key: TranslationKey) => string;
  onSelectTask: (id: string) => void;
  onInvalidate: () => void;
  autoShowAddEvent?: boolean;
  onAutoShowAddEventConsumed?: () => void;
  isMobile?: boolean;
  /** Desktop-only: collapse the panel. The mobile layout ships its
   * own chevron in the parent, so the mobile path leaves this
   * undefined and the close button below is suppressed. */
  onClose?: () => void;
}) {
  const dayContext = useConfiguredDayContext();
  const nowHHMM = useCurrentTime(dayContext.timezone);
  const isToday = date === dayContext.todayYmd;
  const formattedDate = formatCalendarDate(date, locale, {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  });

  // Partition + sort once per `tasks` change. Was running on every render
  // when only an unrelated `viewMode` / form-state tick fired.
  const open = useMemo(() => tasks
    .filter((task) => task.status === TASK_STATUS.open)
    .sort((left, right) => {
      if (left.due_time && right.due_time) return left.due_time.localeCompare(right.due_time);
      if (left.due_time) return -1;
      if (right.due_time) return 1;
      return 0;
    }), [tasks]);
  const done = useMemo(
    () => tasks.filter((task) => task.status === TASK_STATUS.completed),
    [tasks],
  );

  const sortedEvents = useMemo(() => [...events].sort((left, right) => {
    if (left.all_day && !right.all_day) return -1;
    if (!left.all_day && right.all_day) return 1;
    if (left.start_time && right.start_time) return left.start_time.localeCompare(right.start_time);
    return 0;
  }), [events]);

  const {
    addingTask,
    handleAddTask,
    handleComplete,
    handleReopen,
    handleRescheduleTask,
    handleResizeTask,
  } = useDayPanelTaskActions({
    date,
    onInvalidate,
    t,
  });

  const [viewMode, setViewMode] = useState<'list' | 'timeline'>('list');
  const [showAddEvent, setShowAddEvent] = useState(false);
  const [editingEvent, setEditingEvent] = useState<CalendarEvent | null>(null);
  const eventFormSessionRef = useRef(0);

  // Reset editing state when the selected date changes so stale forms
  // from a previous day don't persist in the panel.
  const prevDateRef = useRef(date);
  useEffect(() => {
    if (prevDateRef.current !== date) {
      prevDateRef.current = date;
      eventFormSessionRef.current += 1;
      setShowAddEvent(false);
      setEditingEvent(null);
    }
  }, [date]);
  const openCreateEventForm = useCallback(() => {
    eventFormSessionRef.current += 1;
    setEditingEvent(null);
    setShowAddEvent(true);
  }, []);
  const openEditEventForm = useCallback((nextEvent: UnifiedCalendarEvent) => {
    if (!nextEvent.editable) return; // Provider events (native calendar, ICS) are read-only
    eventFormSessionRef.current += 1;
    setEditingEvent(nextEvent as CalendarEvent);
    setShowAddEvent(false);
  }, []);
  const closeEventForm = useCallback(() => {
    eventFormSessionRef.current += 1;
    setShowAddEvent(false);
    setEditingEvent(null);
  }, []);
  // Auto-open the event creation form when triggered by the header "New Event" button
  useEffect(() => {
    if (autoShowAddEvent) {
      openCreateEventForm();
      onAutoShowAddEventConsumed?.();
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps -- trigger only on prop change, not on stable callbacks
  }, [autoShowAddEvent]);

  // Close edit form if the event being edited is no longer in the list
  // (e.g. deleted from the row-level delete button while the form was open).
  useEffect(() => {
    if (!editingEvent) return;
    const stillExists = events.some((e) => e.id === editingEvent.id);
    if (!stillExists) {
      closeEventForm();
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps -- only re-check when events list changes
  }, [events]);

  const activeEventFormSession = (showAddEvent || editingEvent) ? eventFormSessionRef.current : null;
  const hasItems = events.length > 0 || tasks.length > 0;

  // j/k roving focus across the day panel's combined feed
  // (event pills + task rows), interleaved in time order. Skips
  // non-editable provider events (no interactive surface) and the
  // collapsed "done" tasks rail intentionally; the panel's primary
  // navigation concern is open work + editable events for the day.
  const focusableRows = useMemo(() => {
    type FocusableRow =
      | { kind: 'event'; sortKey: string; id: string }
      | { kind: 'task'; sortKey: string; id: string };
    const rows: FocusableRow[] = [];
    for (const event of sortedEvents) {
      // All-day events sort to the top with an empty time key; tasks
      // without a due_time sort to the bottom via `~` (lexicographically
      // greater than any `HH:MM` string).
      const editable = 'editable' in event ? (event as { editable?: boolean }).editable !== false : true;
      if (!editable) continue;
      const sortKey = event.all_day ? '' : (event.start_time ?? '~');
      rows.push({ kind: 'event', sortKey, id: event.id });
    }
    for (const task of open) {
      rows.push({ kind: 'task', sortKey: task.due_time ?? '~', id: task.id });
    }
    rows.sort((a, b) => a.sortKey.localeCompare(b.sortKey));
    return rows;
  }, [sortedEvents, open]);
  const focusableRowIndexById = useMemo(() => {
    const map = new Map<string, number>();
    focusableRows.forEach((row, idx) => { map.set(`${row.kind}:${row.id}`, idx); });
    return map;
  }, [focusableRows]);
  const { register: registerFocusableRow } = useListJkNavigation(focusableRows.length);

  const taskInputRef = useRef<HTMLInputElement>(null);

  return (
    <div className={isMobile
      ? 'w-full flex flex-col overflow-hidden max-h-[50vh]'
      : 'w-80 shrink-0 border-s border-card flex flex-col overflow-hidden'
    }>
      <div className="px-5 pt-6 pb-4 border-b border-surface-3 shrink-0">
        <div className="flex items-center justify-between gap-2">
          <p className="text-text-primary text-sm font-medium truncate">{formattedDate}</p>
          <div className="flex items-center gap-1.5 shrink-0">
            <div className="flex gap-0.5 bg-surface-2 rounded-r-control p-0.5">
              <Tooltip label={t('upcoming.listView')}>
                <button
                  type="button"
                  onClick={() => setViewMode('list')}
                  className={`px-1.5 py-0.5 text-xs rounded-r-control transition-colors focus-ring-soft ${
                    viewMode === 'list' ? 'bg-surface-3 text-text-primary' : 'text-text-muted hover:text-text-secondary'
                  }`}
                  aria-pressed={viewMode === 'list'}
                >
                  {t('upcoming.listView')}
                </button>
              </Tooltip>
              <Tooltip label={t('upcoming.timelineView')}>
                <button
                  type="button"
                  onClick={() => setViewMode('timeline')}
                  className={`px-1.5 py-0.5 text-xs rounded-r-control transition-colors focus-ring-soft ${
                    viewMode === 'timeline' ? 'bg-surface-3 text-text-primary' : 'text-text-muted hover:text-text-secondary'
                  }`}
                  aria-pressed={viewMode === 'timeline'}
                >
                  {t('upcoming.timelineView')}
                </button>
              </Tooltip>
            </div>
            {onClose && (
              <Tooltip label={t('common.close')}>
                <button
                  type="button"
                  onClick={onClose}
                  aria-label={t('common.close')}
                  className="w-6 h-6 flex items-center justify-center rounded-r-control text-text-muted hover:text-text-primary hover:bg-surface-2 transition-colors focus-ring-soft"
                >
                  ×
                </button>
              </Tooltip>
            )}
          </div>
        </div>
        <p className="text-text-muted text-xs mt-0.5">
          {!hasItems
            ? t('calendar.noTasks')
            : formatCalendarDayPanelSummary(locale, events.length, open.length, t)}
        </p>
      </div>

      {viewMode === 'timeline' ? (
        <div className="flex-1 overflow-hidden px-4 py-3">
          <DayTimeline
            tasks={tasks}
            events={events}
            t={t}
            onSelectTask={onSelectTask}
            onCompleteTask={handleComplete}
            onRescheduleTask={handleRescheduleTask}
            onResizeTask={handleResizeTask}
            nowHHMM={isToday ? nowHHMM : null}
          />
        </div>
      ) : (
        <div className="flex-1 overflow-y-auto overscroll-contain px-4 py-3 space-y-1">
          {sortedEvents.length > 0 ? (
            <>
              <p className="text-text-muted text-xs font-medium pb-1">{t('calendar.events')}</p>
              {sortedEvents.map((event) => {
                const editable = 'editable' in event ? (event as { editable?: boolean }).editable !== false : true;
                const focusIdx = editable ? focusableRowIndexById.get(`event:${event.id}`) : undefined;
                return (
                  <DayEventRow
                    key={event.id}
                    event={event}
                    t={t}
                    onEdit={openEditEventForm}
                    onInvalidate={onInvalidate}
                    isPast={isToday && isEventPast(event, nowHHMM)}
                    editable={editable}
                    editButtonRef={focusIdx != null ? registerFocusableRow(focusIdx) : undefined}
                  />
                );
              })}
            </>
          ) : null}

          {open.length > 0 ? (
            <>
              <p className={`text-text-muted text-xs font-medium pb-1 ${sortedEvents.length > 0 ? 'pt-3' : ''}`}>
                {formatOpenTaskCountLabel(locale, open.length, t)}
              </p>
              {open.map((task) => {
                const focusIdx = focusableRowIndexById.get(`task:${task.id}`);
                return (
                  <DayTask
                    key={task.id}
                    task={task}
                    onOpen={onSelectTask}
                    onComplete={handleComplete}
                    completeLabelPrefix={t('task.status.completed')}
                    openButtonRef={focusIdx != null ? registerFocusableRow(focusIdx) : undefined}
                  />
                );
              })}
            </>
          ) : null}

          {done.length > 0 ? (
            <>
              <p className="text-text-muted text-xs font-medium pt-3 pb-1">{t('calendar.completed')}</p>
              {done.map((task) => (
                <DayTask
                  key={task.id}
                  task={task}
                  onOpen={onSelectTask}
                  onComplete={handleComplete}
                  onReopen={handleReopen}
                  done
                  completeLabelPrefix={t('task.status.completed')}
                />
              ))}
            </>
          ) : null}

          {!hasItems && !showAddEvent ? (
            <div className="flex flex-col items-center justify-center py-12 text-center">
              <p className="text-text-muted text-xs">{t('calendar.noTasks')}</p>
            </div>
          ) : null}

          {(showAddEvent || editingEvent) && activeEventFormSession != null ? (
            <EventForm
              key={editingEvent ? `edit-${editingEvent.id}` : `create-${date}`}
              date={date}
              event={editingEvent}
              t={t}
              onDone={() => {
                onInvalidate();
                if (eventFormSessionRef.current !== activeEventFormSession) return;
                closeEventForm();
              }}
              onCancel={() => {
                if (eventFormSessionRef.current !== activeEventFormSession) return;
                closeEventForm();
              }}
            />
          ) : null}
        </div>
      )}

      {viewMode === 'list' && !showAddEvent && !editingEvent ? (
        <div className="px-4 py-3 border-t border-surface-3 shrink-0 space-y-2">
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const input = taskInputRef.current;
              if (!input) return;
              void handleAddTask(input.value).then((created) => {
                if (created) {
                  input.value = '';
                }
              });
            }}
          >
            <input
              ref={taskInputRef}
              type="text"
              disabled={addingTask}
              placeholder={t('calendar.addTaskPlaceholder')}
              aria-label={t('calendar.addTaskPlaceholder')}
              className="w-full text-xs bg-surface-2 text-text-primary px-2.5 py-1.5 rounded-r-control border border-surface-3 outline-hidden focus-ring-soft placeholder:text-text-muted disabled:opacity-50"
              onKeyDown={(e) => {
                if (e.key === 'Escape') {
                  e.currentTarget.blur();
                }
              }}
            />
          </form>
          <button
            type="button"
            onClick={openCreateEventForm}
            className="w-full text-xs text-text-muted hover:text-text-primary py-1.5 rounded-r-control border border-dashed border-surface-3 hover:border-text-muted/30 transition-colors focus-ring-soft"
          >
            + {t('calendar.addEvent')}
          </button>
        </div>
      ) : null}
    </div>
  );
}
