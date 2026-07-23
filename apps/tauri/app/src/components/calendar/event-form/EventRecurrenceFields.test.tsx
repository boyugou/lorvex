import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';

import type { TranslationKey } from '@/lib/i18n';
import { EventRecurrenceFields } from './EventRecurrenceFields';

const labels: Partial<Record<TranslationKey, string>> = {
  'calendar.recurrence.daily': 'Daily',
  'calendar.recurrence.end': 'End',
  'calendar.recurrence.endNever': 'Never',
  'calendar.recurrence.endOnDate': 'On date',
  'calendar.recurrence.interval': 'Interval',
  'calendar.recurrence.intervalInvalid': 'Interval must be between 1 and 99',
  'calendar.recurrence.monthly': 'Monthly',
  'calendar.recurrence.none': 'None',
  'calendar.recurrence.weekdays': 'Weekdays',
  'calendar.recurrence.weekly': 'Weekly',
  'calendar.recurrence.yearly': 'Yearly',
  'common.none': '(none)',
  'settings.advanced': 'Advanced',
  'task.recurrence': 'Recurrence',
  'task.recurrence.until': 'Until',
  'weekday.fri': 'Fri',
  'weekday.mon': 'Mon',
  'weekday.sat': 'Sat',
  'weekday.sun': 'Sun',
  'weekday.thu': 'Thu',
  'weekday.tue': 'Tue',
  'weekday.wed': 'Wed',
};

const t = (key: TranslationKey) => labels[key] ?? key;

describe('EventRecurrenceFields accessibility state', () => {
  it('exposes weekly recurrence weekdays as pressed toggles', () => {
    const html = renderToStaticMarkup(
      <EventRecurrenceFields
        t={t}
        recurrencePreset="weekly"
        onRecurrencePresetChange={vi.fn()}
        recurrenceInterval={1}
        onRecurrenceIntervalChange={vi.fn()}
        recurrenceEndCondition="never"
        onRecurrenceEndConditionChange={vi.fn()}
        normalizedRecurrenceUntil=""
        onRecurrenceUntilDateChange={vi.fn()}
        recurrenceWeekdays={['MO', 'FR']}
        onToggleWeekday={vi.fn()}
        effectiveStartDate="2026-05-08"
      />,
    );

    expect(html).toContain('aria-pressed="true"');
    expect(html).toContain('aria-pressed="false"');
  });

  it('labels the recurrence until date button in empty and populated states', () => {
    const emptyHtml = renderToStaticMarkup(
      <EventRecurrenceFields
        t={t}
        recurrencePreset="daily"
        onRecurrencePresetChange={vi.fn()}
        recurrenceInterval={1}
        onRecurrenceIntervalChange={vi.fn()}
        recurrenceEndCondition="onDate"
        onRecurrenceEndConditionChange={vi.fn()}
        normalizedRecurrenceUntil=""
        onRecurrenceUntilDateChange={vi.fn()}
        recurrenceWeekdays={[]}
        onToggleWeekday={vi.fn()}
        effectiveStartDate="2026-05-08"
      />,
    );

    expect(emptyHtml).toContain('aria-label="Until: (none)"');
    expect(emptyHtml).toContain('>—</button>');

    const populatedHtml = renderToStaticMarkup(
      <EventRecurrenceFields
        t={t}
        recurrencePreset="daily"
        onRecurrencePresetChange={vi.fn()}
        recurrenceInterval={1}
        onRecurrenceIntervalChange={vi.fn()}
        recurrenceEndCondition="onDate"
        onRecurrenceEndConditionChange={vi.fn()}
        normalizedRecurrenceUntil="2026-05-20"
        onRecurrenceUntilDateChange={vi.fn()}
        recurrenceWeekdays={[]}
        onToggleWeekday={vi.fn()}
        effectiveStartDate="2026-05-08"
      />,
    );

    expect(populatedHtml).toContain('aria-label="Until: 2026-05-20"');
    expect(populatedHtml).toContain('>2026-05-20</button>');
  });
});
