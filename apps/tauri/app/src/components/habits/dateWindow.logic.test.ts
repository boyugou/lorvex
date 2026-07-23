import { describe, expect, it } from 'vitest';

import { generateLast84Days } from './dateWindow.logic';

describe('generateLast84Days', () => {
  it('returns an 84-day UTC window ending on the configured day', () => {
    const dates = generateLast84Days('2026-04-30');

    expect(dates).toHaveLength(84);
    expect(dates[0]).toBe('2026-02-06');
    expect(dates[83]).toBe('2026-04-30');
  });

  it('walks across leap days without host-timezone drift', () => {
    const dates = generateLast84Days('2024-03-01');

    expect(dates.at(-2)).toBe('2024-02-29');
    expect(dates.at(-1)).toBe('2024-03-01');
  });
});
