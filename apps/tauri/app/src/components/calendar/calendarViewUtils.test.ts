import { describe, expect, it } from 'vitest';

import { recurrenceFromRaw, recurrencePresetToRaw } from './calendarViewUtils';

describe('calendar recurrence form helpers', () => {
  it('marks positional monthly recurrence as advanced instead of clearing it', () => {
    const raw = JSON.stringify({
      FREQ: 'MONTHLY',
      INTERVAL: 1,
      BYDAY: ['MO'],
      BYSETPOS: [1],
    });

    expect(recurrenceFromRaw(raw, '2026-05-01')).toMatchObject({
      preset: 'advanced',
      interval: 1,
      byday: [],
      endCondition: 'never',
    });
  });

  it('does not synthesize a writable payload for preserved advanced recurrence', () => {
    expect(recurrencePresetToRaw('advanced', 1, [], 'never', '', '2026-05-01')).toBeNull();
  });

  it('falls back when stored task recurrence intervals exceed the editor range', () => {
    expect(recurrenceFromRaw(JSON.stringify({ FREQ: 'DAILY', INTERVAL: 100 }), '2026-05-01')).toMatchObject({
      preset: 'none',
      interval: 1,
    });
  });
});
