import { eventDotColor } from '@/lib/colorUtils';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { useI18n } from '@/lib/i18n';
import { formatNumber } from '@/locales';
import { Pill } from '@/components/ui/Pill';
import { eventTypeIcon } from '../calendar/eventTypeIcon';

export interface EnrichedEvent {
  event: UnifiedCalendarEvent;
  isPast: boolean;
  isNow: boolean;
  minutesUntil: number;
}

interface PopoverEventItemProps {
  enriched: EnrichedEvent;
  locale: string;
  t: ReturnType<typeof useI18n>['t'];
  format: ReturnType<typeof useI18n>['format'];
}

export function PopoverEventItem({ enriched, locale, t, format }: PopoverEventItemProps) {
  const { event, isPast, isNow, minutesUntil } = enriched;

  return (
    <li
      className={`flex items-center gap-2 rounded-r-card px-1.5 py-[5px] transition-colors ${
        isNow ? 'bg-[var(--accent-tint-xxs)]' : isPast ? 'opacity-35' : ''
      }`}
    >
      <span
        className={`shrink-0 w-1.5 h-1.5 rounded-full ${isNow ? 'motion-safe:animate-pulse' : ''}`}
        style={{ backgroundColor: eventDotColor(event.color ?? null) }}
      />
      <span className="shrink-0 text-2xs text-text-muted/70 tabular-nums w-10 font-medium">
        {event.all_day ? t('upcoming.allDay') : (event.start_time?.slice(0, 5) ?? '')}
      </span>
      <span
        title={event.title}
        className={`text-xs leading-snug truncate flex-1 min-w-0 ${
          isNow ? 'text-text-primary font-medium' : isPast ? 'line-through text-text-muted' : 'text-text-secondary'
        }`}
      >
        {eventTypeIcon(event.event_type) || (event.recurrence ? '↻ ' : '')}{event.title}
      </span>
      {isNow && (
        <Pill tone="accent" size="sm" tabular className="shrink-0 uppercase tracking-wide">
          {t('popover.eventNow')}
        </Pill>
      )}
      {!isNow && !isPast && minutesUntil > 0 && (
        <Pill tone="warning" size="sm" tabular className="shrink-0">
          {format('popover.eventSoon', { '0': formatNumber(locale, minutesUntil) })}
        </Pill>
      )}
    </li>
  );
}
