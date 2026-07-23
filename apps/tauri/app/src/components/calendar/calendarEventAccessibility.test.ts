import { describe, expect, it } from 'vitest';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { TranslationKey, TranslationVars } from '@/lib/i18n';

import { formatCalendarEventAccessibleLabel } from './calendarEventAccessibility';

function event(overrides: Partial<UnifiedCalendarEvent>): UnifiedCalendarEvent {
  return {
    id: 'event-1',
    title: 'Design review',
    start_date: '2026-05-10',
    end_date: '2026-05-10',
    start_time: '09:00',
    end_time: '09:30',
    all_day: false,
    location: null,
    notes: null,
    color: null,
    recurrence: null,
    exceptions: [],
    created_at: '2026-05-10T09:00:00Z',
    updated_at: '2026-05-10T09:00:00Z',
    kind: 'canonical',
    editable: true,
    event_type: 'event',
    attendees_json: null,
    ...overrides,
  } as UnifiedCalendarEvent;
}

const labels: Record<string, string> = {
  'calendar.eventAllDay': 'All day',
  'calendar.eventLocation': 'Location',
  'calendar.providerEvent': 'System calendar',
};

const t = (key: TranslationKey): string => labels[key] ?? key;

const format = (key: TranslationKey, vars: TranslationVars = {}): string => {
  if (key === 'calendar.eventPillLabel') {
    return `Calendar event: ${String(vars.title)} at ${String(vars.time)}`;
  }
  return key;
};

describe('calendar event accessible labels', () => {
  it('distinguishes duplicate event titles by time range', () => {
    const morning = formatCalendarEventAccessibleLabel(event({ id: 'morning' }), { format, t });
    const afternoon = formatCalendarEventAccessibleLabel(
      event({ id: 'afternoon', start_time: '14:00', end_time: '14:30' }),
      { format, t },
    );

    expect(morning).toBe('Calendar event: Design review at 09:00 – 09:30');
    expect(afternoon).toBe('Calendar event: Design review at 14:00 – 14:30');
  });

  it('includes all-day, location, and provider/read-only context', () => {
    const label = formatCalendarEventAccessibleLabel(
      event({
        all_day: true,
        editable: false,
        kind: 'provider',
        location: 'Board room',
        start_time: null,
        end_time: null,
      }),
      { format, t },
    );

    expect(label).toBe('Calendar event: Design review at All day · Location: Board room · System calendar');
  });
});
