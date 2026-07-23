import { describe, expect, it } from 'vitest';

import { parseRecurrence } from './shared';

describe('task recurrence helpers', () => {
  it('parses advanced positional rules as non-editable recurrence instead of absence', () => {
    const raw = JSON.stringify({
      FREQ: 'MONTHLY',
      INTERVAL: 1,
      BYDAY: ['MO'],
      BYSETPOS: [1],
    });

    expect(parseRecurrence(raw)).toMatchObject({
      freq: 'MONTHLY',
      editable: false,
      interval: 1,
    });
  });

  it('rejects intervals above the task recurrence editor range', () => {
    expect(parseRecurrence(JSON.stringify({ FREQ: 'DAILY', INTERVAL: 100 }))).toBeNull();
  });
});
