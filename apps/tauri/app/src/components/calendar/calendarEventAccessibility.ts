import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { TranslationKey, TranslationVars } from '@/lib/i18n';

import { formatTimeRange } from './calendarViewUtils';

interface CalendarEventAccessibleLabelOptions {
  dateLabel?: string;
  format: (key: TranslationKey, vars?: TranslationVars) => string;
  t: (key: TranslationKey) => string;
}

export function formatCalendarEventAccessibleLabel(
  event: UnifiedCalendarEvent,
  { dateLabel, format, t }: CalendarEventAccessibleLabelOptions,
): string {
  const timeRange = formatTimeRange(event, t('calendar.eventAllDay'));
  const time = timeRange || dateLabel || event.start_date;
  const parts = [
    format('calendar.eventPillLabel', {
      title: event.title,
      time,
    }),
  ];
  const location = event.location?.trim();
  if (location) {
    parts.push(`${t('calendar.eventLocation')}: ${location}`);
  }
  if (event.kind === 'provider' || !event.editable) {
    parts.push(t('calendar.providerEvent'));
  }
  return parts.join(' · ');
}
