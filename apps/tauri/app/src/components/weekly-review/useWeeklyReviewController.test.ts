import { describe, expect, it } from 'vitest';

import {
  getWeeklyReviewLookingAheadWindow,
  WEEKLY_REVIEW_LOOKING_AHEAD_DAYS,
} from './useWeeklyReviewController';

describe('getWeeklyReviewLookingAheadWindow', () => {
  it('uses a strict tomorrow-through-today-plus-seven inclusive window', () => {
    const window = getWeeklyReviewLookingAheadWindow('2026-05-12');

    expect(WEEKLY_REVIEW_LOOKING_AHEAD_DAYS).toBe(7);
    expect(window).toEqual({
      startYmd: '2026-05-13',
      endYmd: '2026-05-19',
    });
    expect(window.endYmd).not.toBe('2026-05-20');
  });

  it('keeps the seven-day boundary correct across month rollover', () => {
    expect(getWeeklyReviewLookingAheadWindow('2026-01-28')).toEqual({
      startYmd: '2026-01-29',
      endYmd: '2026-02-04',
    });
  });
});
