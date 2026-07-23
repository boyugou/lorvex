import { describe, expect, it } from 'vitest';

import { normalizeRecurrenceIntervalInput } from './mutations.logic';

describe('calendar event recurrence mutation helpers', () => {
  it('normalizes blank non-integer and unsafe interval input to the minimum', () => {
    expect(normalizeRecurrenceIntervalInput('')).toBe(1);
    expect(normalizeRecurrenceIntervalInput('  ')).toBe(1);
    expect(normalizeRecurrenceIntervalInput('2.5')).toBe(1);
    expect(normalizeRecurrenceIntervalInput('abc')).toBe(1);
    expect(normalizeRecurrenceIntervalInput(String(Number.MAX_SAFE_INTEGER + 1))).toBe(1);
  });

  it('clamps recurrence intervals to the shared task/calendar editor range', () => {
    expect(normalizeRecurrenceIntervalInput('0')).toBe(1);
    expect(normalizeRecurrenceIntervalInput('42')).toBe(42);
    expect(normalizeRecurrenceIntervalInput('100')).toBe(99);
    expect(normalizeRecurrenceIntervalInput('365')).toBe(99);
  });
});
