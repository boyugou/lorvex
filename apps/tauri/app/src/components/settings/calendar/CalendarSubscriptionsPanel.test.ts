import { describe, expect, it } from 'vitest';

import type { CalendarSubscription } from '@/lib/ipc/calendar';
import type { TranslationKey } from '@/lib/i18n';
import {
  buildCalendarSubscriptionToggleCopy,
  localizeCalendarSubscriptionError,
} from './CalendarSubscriptionsPanel';

const translations: Partial<Record<TranslationKey, string>> = {
  'settings.calendarSubStateEnabled': 'Enabled',
  'settings.calendarSubStateDisabled': 'Disabled',
  'settings.calendarSubToggleLabel': '{name} subscription is {state}. Toggle to {nextState}.',
  'settings.calendarSubErrorGeneric': 'Calendar feed could not be synced.',
  'settings.calendarSubErrorInvalidIcs': 'This does not look like an iCalendar feed.',
  'settings.calendarSubErrorInvalidUrl': 'The calendar URL is invalid.',
  'settings.calendarSubErrorNetwork': 'Lorvex could not reach this calendar feed.',
  'settings.calendarSubErrorNotFound': 'The calendar feed was not found.',
  'settings.calendarSubErrorRateLimited': 'The calendar provider is rate limiting requests.',
  'settings.calendarSubErrorTimeout': 'The calendar provider did not respond in time.',
  'settings.calendarSubErrorTooLarge': 'The calendar feed is too large.',
  'settings.calendarSubErrorTruncated': 'The calendar feed was truncated.',
  'settings.calendarSubErrorUnauthorized': 'This calendar feed requires access.',
};

function t(key: TranslationKey): string {
  return translations[key] ?? key;
}

function format(key: TranslationKey, vars: Record<string, string> = {}): string {
  return t(key).replace(/\{([^}]+)\}/g, (match, name) => (
    name in vars ? String(vars[name]) : match
  ));
}

function subscription(overrides: Partial<CalendarSubscription> = {}): CalendarSubscription {
  return {
    id: 'sub-1',
    name: 'Work Calendar',
    url: 'https://example.com/work.ics',
    color: '#3b82f6',
    enabled: true,
    last_fetched_at: null,
    error_message: null,
    sync_health: 'healthy',
    consecutive_failures: 0,
    last_retry_after_hint: null,
    next_retry_at: null,
    created_at: '2026-05-08T17:00:00Z',
    updated_at: '2026-05-08T17:00:00Z',
    ...overrides,
  };
}

describe('buildCalendarSubscriptionToggleCopy', () => {
  it('localizes toggle state and labels the action with subscription context', () => {
    expect(buildCalendarSubscriptionToggleCopy(subscription(), t, format)).toEqual({
      stateLabel: 'Enabled',
      ariaLabel: 'Work Calendar subscription is Enabled. Toggle to Disabled.',
    });

    expect(buildCalendarSubscriptionToggleCopy(subscription({ enabled: false }), t, format)).toEqual({
      stateLabel: 'Disabled',
      ariaLabel: 'Work Calendar subscription is Disabled. Toggle to Enabled.',
    });
  });
});

describe('localizeCalendarSubscriptionError', () => {
  it.each([
    ['Response is not a valid iCalendar file', 'This does not look like an iCalendar feed.'],
    ['Invalid calendar subscription URL: expected https', 'The calendar URL is invalid.'],
    ['ICS body truncated before END:VCALENDAR', 'The calendar feed was truncated.'],
    ['request timed out after 30s', 'The calendar provider did not respond in time.'],
    ['404 not found', 'The calendar feed was not found.'],
    ['403 forbidden', 'This calendar feed requires access.'],
    ['HTTP 429 rate-limit exceeded', 'The calendar provider is rate limiting requests.'],
    ['payload size exceeds configured cap', 'The calendar feed is too large.'],
    ['error sending request for url: dns lookup failed', 'Lorvex could not reach this calendar feed.'],
    ['unrecognized provider response', 'Calendar feed could not be synced.'],
  ])('maps "%s" to user-facing copy', (raw, expected) => {
    expect(localizeCalendarSubscriptionError(raw, t)).toBe(expected);
  });
});
