import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const recurrenceFieldRenderState = vi.hoisted(() => ({
  forceEditing: false,
  stateCallIndex: 0,
}));

vi.mock('react', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react')>();
  return {
    ...actual,
    useState: vi.fn((initialValue: unknown) => {
      recurrenceFieldRenderState.stateCallIndex += 1;
      const value = typeof initialValue === 'function'
        ? (initialValue as () => unknown)()
        : initialValue;

      if (recurrenceFieldRenderState.forceEditing && recurrenceFieldRenderState.stateCallIndex === 1) {
        return [true, vi.fn()];
      }

      return [value, vi.fn()];
    }),
  };
});

import RecurrenceField from './RecurrenceField';
import type { Translator } from './shared';

const labels: Partial<Record<Parameters<Translator>[0], string>> = {
  'common.cancel': 'Cancel',
  'common.remove': 'Remove',
  'common.save': 'Save',
  'common.saving': 'Saving',
  'quickdate.clear': 'Clear',
  'task.recurrence': 'Recurrence',
  'task.recurrence.add': 'Add recurrence',
  'task.recurrence.daily': 'Day',
  'task.recurrence.dismissUpdate': 'Dismiss',
  'task.recurrence.every': 'Every',
  'task.recurrence.interval': 'Repeat interval',
  'task.recurrence.intervalInvalid': 'Interval must be between 1 and 99',
  'task.recurrence.monthly': 'Month',
  'task.recurrence.on': 'On',
  'task.recurrence.syncedDuringEdit': 'Updated by sync while you were editing.',
  'task.recurrence.until': 'Until',
  'task.recurrence.useLatest': 'Use latest',
  'task.recurrence.weekly': 'Week',
  'task.recurrence.yearly': 'Year',
  'weekday.fri': 'Fri',
  'weekday.mon': 'Mon',
  'weekday.sat': 'Sat',
  'weekday.sun': 'Sun',
  'weekday.thu': 'Thu',
  'weekday.tue': 'Tue',
  'weekday.wed': 'Wed',
};

const t: Translator = (key) => labels[key] ?? key;

describe('RecurrenceField accessibility state', () => {
  beforeEach(() => {
    recurrenceFieldRenderState.forceEditing = true;
    recurrenceFieldRenderState.stateCallIndex = 0;
  });

  it('exposes frequency as a radio group and weekdays as pressed toggles', () => {
    const html = renderToStaticMarkup(
      <RecurrenceField
        locale="en"
        onSave={async () => {}}
        t={t}
        task={{
          id: 'task-1',
          recurrence: '{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO","FR"]}',
        }}
      />,
    );

    expect(html).toContain('role="radiogroup"');
    expect(html).toContain('role="radio"');
    expect(html).toContain('aria-checked="true"');
    expect(html).toContain('aria-checked="false"');
    expect(html).toContain('tabindex="0"');
    expect(html).toContain('tabindex="-1"');
    expect(html).toContain('aria-pressed="true"');
    expect(html).toContain('aria-pressed="false"');
  });
});
