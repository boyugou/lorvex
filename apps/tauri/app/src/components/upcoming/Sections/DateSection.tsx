import { useMemo, type MouseEvent as ReactMouseEvent } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import type { TranslationKey } from '@/lib/i18n';
import type { DayContext } from '@/lib/dayContext';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import { invalidateTaskMutationQueries } from '../../../lib/query/queryKeys';
import { isEventPast } from '../../../lib/time/useCurrentTime';
import { formatDueDate } from '../../../lib/format';
import { formatNumber } from '../../../locales';
import { useQueryClient } from '@tanstack/react-query';
import { formatDurationCompact } from '../../today-view/primitives';
import { CollapsibleSection } from '../../ui/CollapsibleSection';
import { Tooltip } from '../../ui/Tooltip';
import { ChevronDownIcon, WarningIcon } from '../../ui/icons';
import { EventRow } from '../EventRow';
import { InlineAddTask } from '../InlineAddTask';
import { UpcomingTaskRow } from '../UpcomingTaskRow';
import { sortEvents } from '../dateUtils';
import { DRAG_MIME } from '../useUpcomingController';

/**
 * Single date column in the Upcoming list view. Renders the header
 * row (formatted date + item count + estimated-minutes pill with
 * overload warning), a collapsible body holding events + tasks +
 * inline-add, and the HTML5 drop target for reschedule drag-drop.
 *
 * The orchestrator hands this component pre-sliced day arrays, so the
 * sum here is over a single day; per-section `useMemo` keeps the sum
 * stable across unrelated parent state ticks.
 */
export function DateSection({
  date,
  dayTasks,
  dayEvents,
  collapsed,
  isDragOver,
  onToggleCollapse,
  setDragOverDate,
  handleRescheduleTask,
  onSelectTask,
  onClickWithModifiers,
  onDragEnd,
  selectionMode,
  selectedIds,
  bulkBusy,
  focusedId,
  hasSelection,
  onToggleSelected,
  dayContext,
  nowHHMM,
  locale,
  t,
}: {
  date: string;
  dayTasks: Task[];
  dayEvents: UnifiedCalendarEvent[];
  collapsed: boolean;
  isDragOver: boolean;
  onToggleCollapse: () => void;
  setDragOverDate: (date: string | null) => void;
  handleRescheduleTask: (taskId: string, newDate: string) => Promise<void> | void;
  onSelectTask?: ((taskId: string) => void) | undefined;
  onClickWithModifiers: (id: string, event: ReactMouseEvent<HTMLButtonElement>) => void;
  onDragEnd: () => void;
  selectionMode: boolean;
  selectedIds: Set<string>;
  bulkBusy: boolean;
  focusedId: string | null;
  hasSelection: boolean;
  onToggleSelected: (taskId: string) => void;
  dayContext: DayContext;
  nowHHMM: string;
  locale: string;
  t: (key: TranslationKey) => string;
}) {
  const qc = useQueryClient();
  // Pre-memoize per-day total — keeps the sum stable across renders
  // that don't change this day's task array reference (e.g.
  // `dragOverDate` ticks elsewhere on the page).
  const totalMinutes = useMemo(
    () => dayTasks.reduce((sum, tk) => sum + (tk.estimated_minutes ?? 0), 0),
    [dayTasks],
  );
  const isOverloaded = totalMinutes > 480;
  const itemCount = dayTasks.length + dayEvents.length;

  return (
    // Drop zone for HTML5 drag-and-drop on a date column.
    // No user-action contract beyond receiving a drop;
    // keyboard reschedule is wired through the task card.
    // eslint-disable-next-line jsx-a11y/no-static-element-interactions
    <section
      onDragOver={(event) => {
        if (!event.dataTransfer.types.includes(DRAG_MIME)) return;
        event.preventDefault();
        event.dataTransfer.dropEffect = 'move';
        if (!isDragOver) setDragOverDate(date);
      }}
      onDragLeave={(event) => {
        if (!event.currentTarget.contains(event.relatedTarget as Node)) {
          setDragOverDate(null);
        }
      }}
      onDrop={(event) => {
        event.preventDefault();
        setDragOverDate(null);
        const taskId = event.dataTransfer.getData(DRAG_MIME);
        if (taskId) void handleRescheduleTask(taskId, date);
      }}
      // Aligned to the canonical drag-over treatment shared with
      // Eisenhower / Kanban (`ring-2 ring-accent/50 bg-accent/5`).
      // Keep the ring permanently in the box-shadow
      // chain (rendered transparent when not dragging) and
      // animate it via a 150ms transition on box-shadow +
      // background-color so the visual fades softly in both
      // directions during multi-day reschedule drags.
      className={`rounded-r-card transition-[box-shadow,background-color] duration-150 ease-out ring-2 ring-transparent ${isDragOver ? 'ring-accent/50 bg-accent/5' : ''}`}
    >
      <h2 className="mb-3">
        <button
          type="button"
          // Subtle hover affordance — see overdue header above for the rationale.
          className="flex items-baseline gap-2 select-none focus-ring-soft rounded-r-control text-start hover:opacity-80 transition-opacity"
          onClick={onToggleCollapse}
          aria-expanded={!collapsed}
        >
          {/* Chevron is decorative; state lives in `aria-expanded`
              on the parent button. */}
          <ChevronDownIcon aria-hidden="true" className={`w-3 h-3 text-text-muted transition-transform duration-150 ${collapsed ? '-rotate-90' : ''}`} />
          <span className="text-text-secondary text-xs font-medium">
            {formatDueDate(date, {
              dayContext,
              locale,
              todayLabel: t('upcoming.today'),
              tomorrowLabel: t('upcoming.tomorrow'),
              yesterdayLabel: t('upcoming.yesterday'),
            })}
          </span>
          <span className="chip-tight text-text-muted/70 text-2xs bg-surface-3/40 tabular-nums">{formatNumber(locale, itemCount)}</span>
          {totalMinutes > 0 && (
            isOverloaded ? (
              <Tooltip label={t('upcoming.overloadedHint')}>
                <span className="text-xs text-danger">
                  · {formatDurationCompact(totalMinutes, t('common.hourShort'), t('common.min'), (value) => formatNumber(locale, value))} {t('common.estimated')}
                  <> <WarningIcon className="w-3 h-3 inline-block align-text-bottom" /></>
                </span>
              </Tooltip>
            ) : (
              <span className="text-xs text-text-muted">
                · {formatDurationCompact(totalMinutes, t('common.hourShort'), t('common.min'), (value) => formatNumber(locale, value))} {t('common.estimated')}
              </span>
            )
          )}
        </button>
      </h2>
      <CollapsibleSection collapsed={collapsed}>
          <div className="space-y-1.5">
            {sortEvents(dayEvents).map((event) => (
              <EventRow key={event.id} event={event} t={t} isPast={date === dayContext.todayYmd && isEventPast(event, nowHHMM)} />
            ))}
            {dayTasks.map((task) => (
              <UpcomingTaskRow
                key={task.id}
                task={task}
                selectionMode={selectionMode}
                selected={selectedIds.has(task.id)}
                bulkBusy={bulkBusy}
                focused={focusedId === task.id}
                hasSelection={hasSelection}
                onToggleSelected={onToggleSelected}
                onSelect={onSelectTask}
                onClickWithModifiers={onClickWithModifiers}
                onDragEnd={onDragEnd}
              />
            ))}
            <InlineAddTask
              date={date}
              t={t}
              onCreated={() => invalidateTaskMutationQueries(qc)}
            />
          </div>
      </CollapsibleSection>
    </section>
  );
}
