import { describe, expect, it } from 'vitest';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import { buildTaskDetailEventLinkSearchResults } from './useTaskDetailEventLinkSearch';

const baseEvent: UnifiedCalendarEvent = {
  id: 'event-1',
  title: 'Planning',
  description: null,
  recurrence: null,
  recurrence_exceptions: null,
  timezone: null,
  start_date: '2026-05-08',
  start_time: '09:00',
  end_date: null,
  end_time: '09:30',
  all_day: false,
  location: null,
  url: null,
  color: null,
  event_type: 'meeting',
  person_name: null,
  created_at: '',
  updated_at: '',
  kind: 'canonical',
  editable: true,
  attendees_json: null,
};

describe('buildTaskDetailEventLinkSearchResults', () => {
  it('excludes provider events by their unified provider id', () => {
    const providerEvent = {
      ...baseEvent,
      id: 'native-calendar:work:evt-123',
      kind: 'provider',
      editable: false,
    } satisfies UnifiedCalendarEvent;
    const canonicalEvent = {
      ...baseEvent,
      id: 'canonical-1',
      title: 'Planning follow-up',
    } satisfies UnifiedCalendarEvent;

    expect(buildTaskDetailEventLinkSearchResults(
      [providerEvent, canonicalEvent],
      ['native-calendar:work:evt-123'],
      'planning',
    )).toEqual([canonicalEvent]);
  });
});
