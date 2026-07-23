import { describe, expect, it } from 'vitest';

import {
  parseTaskRecurrence,
  taskRecurrencePatchMatchesRaw,
} from './taskRecurrence';

describe('task recurrence parsing', () => {
  it('keeps positional BYSETPOS rules as valid advanced recurrence', () => {
    const raw = JSON.stringify({
      FREQ: 'MONTHLY',
      INTERVAL: 1,
      BYDAY: ['MO'],
      BYSETPOS: [1],
    });

    expect(parseTaskRecurrence(raw)).toMatchObject({
      freq: 'MONTHLY',
      editable: false,
      interval: 1,
      byday: undefined,
    });
  });

  it('rejects unknown recurrence keys', () => {
    expect(parseTaskRecurrence(JSON.stringify({ FREQ: 'DAILY', FOO: 'BAR' }))).toBeNull();
  });

  it('rejects invalid UNTIL dates', () => {
    expect(parseTaskRecurrence(JSON.stringify({ FREQ: 'DAILY', UNTIL: '2026-02-30' }))).toBeNull();
  });

  it('rejects zero intervals', () => {
    expect(parseTaskRecurrence(JSON.stringify({ FREQ: 'DAILY', INTERVAL: 0 }))).toBeNull();
  });

  it('rejects intervals above the task recurrence editor range', () => {
    expect(parseTaskRecurrence(JSON.stringify({ FREQ: 'DAILY', INTERVAL: 100 }))).toBeNull();
  });

  it('matches overlay option patches against stored recurrence regardless of key order', () => {
    const stored = JSON.stringify({
      BYDAY: ['MO', 'TU', 'WE', 'TH', 'FR'],
      FREQ: 'WEEKLY',
      INTERVAL: 1,
    });

    expect(taskRecurrencePatchMatchesRaw({
      FREQ: 'WEEKLY',
      INTERVAL: 1,
      BYDAY: ['MO', 'TU', 'WE', 'TH', 'FR'],
    }, stored)).toBe(true);
  });

  it('does not match overlay option patches against advanced recurrence', () => {
    const stored = JSON.stringify({
      FREQ: 'MONTHLY',
      INTERVAL: 1,
      BYDAY: ['MO'],
      BYSETPOS: [1],
    });

    expect(taskRecurrencePatchMatchesRaw({
      FREQ: 'MONTHLY',
      INTERVAL: 1,
    }, stored)).toBe(false);
  });
});
