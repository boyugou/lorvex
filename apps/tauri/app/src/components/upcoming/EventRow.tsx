import { memo } from 'react';
import { eventDotColor } from '@/lib/colorUtils';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import { eventTypeIcon } from '../calendar/eventTypeIcon';
import type { TranslationKey } from '@/lib/i18n';

export const EventRow = memo(function EventRow({
  event,
  t,
  isPast = false,
}: {
  event: UnifiedCalendarEvent;
  t: (k: TranslationKey) => string;
  isPast?: boolean;
}) {
  return (
    <div className={`flex items-center gap-3 px-4 py-2.5 bg-surface-2 rounded-r-card transition-opacity ${isPast ? 'opacity-40' : ''}`}>
      <div
        className="shrink-0 w-1 self-stretch rounded-full"
        style={{ backgroundColor: eventDotColor(event.color ?? null) }}
      />
      <div className="flex-1 min-w-0">
        <p className={`text-sm truncate ${isPast ? 'text-text-muted line-through' : 'text-text-primary'}`}>
          {eventTypeIcon(event.event_type) || (event.recurrence ? '↻ ' : '')}
          {event.title}
        </p>
        <p className="text-xs text-text-muted font-mono">
          {event.all_day
            ? t('calendar.eventAllDay')
            : [event.start_time, event.end_time].filter(Boolean).join(' – ') || ''}
        </p>
        {event.location && <p className="text-xs text-text-muted truncate">{event.location}</p>}
      </div>
    </div>
  );
})
