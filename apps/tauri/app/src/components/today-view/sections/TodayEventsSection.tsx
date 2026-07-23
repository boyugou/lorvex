import { useMemo } from 'react';

import { eventDotColor } from '@/lib/colorUtils';
import { useConfiguredDayContext } from '@/lib/dayContext';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import { eventTypeIcon } from '@/components/calendar/eventTypeIcon';
import { useI18n } from '@/lib/i18n';
import { formatNumber } from '@/locales';
import { isEventPast, useCurrentTime } from '@/lib/time/useCurrentTime';
import { SectionHeader } from '../primitives';

/** Compute whether an event is currently happening or starting soon. */
function eventTimeStatus(
  event: UnifiedCalendarEvent,
  nowHHMM: string,
): { isNow: boolean; minutesUntil: number } {
  if (event.all_day || !event.start_time) return { isNow: false, minutesUntil: -1 };
  const _np = nowHHMM.split(':').map(Number);
  const nh = _np[0] ?? 0, nm = _np[1] ?? 0;
  const nowMin = nh * 60 + nm;
  const _sp = event.start_time.split(':').map(Number);
  const sh = _sp[0] ?? 0, sm = _sp[1] ?? 0;
  const startMin = sh * 60 + sm;
  const syntheticEndH = Math.min(sh + 1, 23);
  const endStr = event.end_time ?? `${String(syntheticEndH).padStart(2, '0')}:${String(syntheticEndH === sh ? 59 : sm).padStart(2, '0')}`;
  const _etp = endStr.split(':').map(Number);
  const eh = _etp[0] ?? 0, em = _etp[1] ?? 0;
  const endMin = eh * 60 + em;
  if (nowMin >= startMin && nowMin < endMin) return { isNow: true, minutesUntil: 0 };
  if (nowMin < startMin && startMin - nowMin <= 30) return { isNow: false, minutesUntil: startMin - nowMin };
  return { isNow: false, minutesUntil: -1 };
}

export function TodayEventsSection({ events }: { events: UnifiedCalendarEvent[] }) {
  const { locale, t, format } = useI18n();
  const dayContext = useConfiguredDayContext();
  const nowHHMM = useCurrentTime(dayContext.timezone);
  const sorted = useMemo(() => {
    return [...events].sort((left, right) => {
      if (left.all_day && !right.all_day) return -1;
      if (!left.all_day && right.all_day) return 1;
      if (left.start_time && right.start_time) {
        const timeCompare = left.start_time.localeCompare(right.start_time);
        if (timeCompare !== 0) return timeCompare;
      } else if (left.start_time) {
        return -1;
      } else if (right.start_time) {
        return 1;
      }
      if (left.end_time && right.end_time) {
        const endCompare = left.end_time.localeCompare(right.end_time);
        if (endCompare !== 0) return endCompare;
      } else if (left.end_time) {
        return -1;
      } else if (right.end_time) {
        return 1;
      }
      const titleCompare = left.title.localeCompare(right.title);
      if (titleCompare !== 0) return titleCompare;
      return left.id.localeCompare(right.id);
    });
  }, [events]);

  return (
    <section>
      <SectionHeader title={t('calendar.events')} count={events.length} />
      <div className="space-y-1">
        {sorted.map((event) => {
          const past = isEventPast(event, nowHHMM);
          const { isNow, minutesUntil } = eventTimeStatus(event, nowHHMM);
          return (
            <div
              key={event.id}
              className={`flex items-center gap-3 px-4 py-2 rounded-r-control transition-opacity ${
                isNow ? 'bg-accent/10 ring-1 ring-accent/20' : past ? 'bg-surface-2 opacity-55' : 'bg-surface-2'
              }`}
            >
              <div
                className={`shrink-0 w-1 self-stretch rounded-full ${isNow ? 'motion-safe:animate-pulse' : ''}`}
                style={{ backgroundColor: eventDotColor(event.color ?? null) }}
              />
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <p className={`text-sm truncate ${
                    isNow ? 'text-text-primary font-medium' : past ? 'text-text-muted line-through' : 'text-text-primary'
                  }`}>{eventTypeIcon(event.event_type) || (event.recurrence ? '↻ ' : '')}{event.title}</p>
                  {isNow && (
                    <span className="shrink-0 text-xs font-semibold text-accent uppercase tracking-wide">
                      {t('popover.eventNow')}
                    </span>
                  )}
                  {!isNow && !past && minutesUntil > 0 && (
                    <span className="shrink-0 text-xs font-medium text-warning tabular-nums">
                      {format('popover.eventSoon', { '0': formatNumber(locale, minutesUntil) })}
                    </span>
                  )}
                </div>
                <p className="text-xs text-text-muted font-mono">
                  {event.all_day
                    ? t('calendar.eventAllDay')
                    : [event.start_time, event.end_time].filter(Boolean).join(' – ') || ''}
                </p>
                {event.location && <p className="text-xs text-text-muted truncate">{event.location}</p>}
              </div>
            </div>
          );
        })}
      </div>
    </section>
  );
}
