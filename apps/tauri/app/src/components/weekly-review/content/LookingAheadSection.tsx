import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { Task } from '@/lib/ipc/tasks/models';
import type { TranslationKey } from '@/lib/i18n';
import { formatNumber } from '@/locales';
import { formatCalendarDate } from '@/lib/dates/dateLocale';
import TaskCard from '@/components/task-card/TaskCard';
import { SwipeableTaskCard } from '@/components/task-card/SwipeableTaskCard';

interface LookingAheadSectionProps {
  upcomingTasks: Task[];
  events: UnifiedCalendarEvent[];
  onSelectTask: (taskId: string) => void;
  t: (key: TranslationKey) => string;
  locale: string;
}

export default function LookingAheadSection({
  upcomingTasks,
  events,
  onSelectTask,
  t,
  locale,
}: LookingAheadSectionProps) {
  const hasUpcoming = upcomingTasks.length > 0;
  const hasEvents = events.length > 0;

  if (!hasUpcoming && !hasEvents) {
    return (
      <div className="bg-surface-2 border border-card rounded-r-card px-5 py-8 text-center">
        <p className="text-text-muted text-sm">{t('review.nothingAhead')}</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Upcoming tasks */}
      {hasUpcoming && (
        <div>
          <h3 className="text-xs font-semibold text-text-muted uppercase tracking-wider mb-2 ms-1">
            {t('review.nextWeekTasks')}
          </h3>
          <div className="space-y-1">
            {upcomingTasks.slice(0, 10).map((task) => (
              <SwipeableTaskCard key={task.id} task={task}>
                <TaskCard task={task} onClick={() => onSelectTask(task.id)} />
              </SwipeableTaskCard>
            ))}
            {upcomingTasks.length > 10 && (
              <p className="text-text-muted text-xs pt-1 ms-1">
                + {formatNumber(locale, upcomingTasks.length - 10)} {t('review.more')}
              </p>
            )}
          </div>
        </div>
      )}

      {/* Calendar events */}
      {hasEvents && (
        <div>
          <h3 className="text-xs font-semibold text-text-muted uppercase tracking-wider mb-2 ms-1">
            {t('review.nextWeekEvents')}
          </h3>
          <div className="space-y-1.5">
            {events.slice(0, 8).map((event) => {
              // `formatCalendarDate` anchors at UTC midnight and
              // forces `timeZone: 'UTC'` so the day label stays on
              // the intended calendar day regardless of host OS tz.
              const dayLabel = formatCalendarDate(event.start_date, locale, {
                weekday: 'short', month: 'short', day: 'numeric',
              });
              const timeLabel = event.all_day || !event.start_time
                ? ''
                : event.start_time;

              return (
                <div
                  key={event.id}
                  className="flex items-center gap-3 px-3 py-2.5 bg-surface-2 border border-card rounded-r-control"
                >
                  <div className="w-1 h-8 rounded-full bg-accent/50 shrink-0" />
                  <div className="flex-1 min-w-0">
                    <div className="text-sm text-text-primary truncate">{event.title}</div>
                    <div className="text-xs text-text-muted">
                      {dayLabel}{timeLabel ? ` \u00B7 ${timeLabel}` : ''}
                    </div>
                  </div>
                </div>
              );
            })}
            {events.length > 8 && (
              <p className="text-text-muted text-xs pt-1 ms-1">
                + {formatNumber(locale, events.length - 8)} {t('review.more')}
              </p>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
