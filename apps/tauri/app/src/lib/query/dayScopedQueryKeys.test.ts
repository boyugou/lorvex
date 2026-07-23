import { describe, expect, it } from 'vitest';

import { DAY_SCOPED_QUERY_KEYS, UPCOMING_TASKS_WINDOW_DAYS } from './dayScopedQueryKeys';
import { QK } from './queryKeys';

describe('DAY_SCOPED_QUERY_KEYS', () => {
  const todayYmd = '2026-04-29';
  const tomorrowYmd = '2026-04-30';

  it('keeps day-relative habit keys isolated by business date', () => {
    expect(DAY_SCOPED_QUERY_KEYS.todaysHabits(todayYmd)).toEqual([QK.todaysHabits, todayYmd]);
    expect(DAY_SCOPED_QUERY_KEYS.habitsWithStats(todayYmd)).toEqual([QK.habitsWithStats, todayYmd]);
    expect(DAY_SCOPED_QUERY_KEYS.weeklyReviewHabits(todayYmd)).toEqual([QK.weeklyReviewHabits, todayYmd]);

    expect(DAY_SCOPED_QUERY_KEYS.todaysHabits(todayYmd)).not.toEqual(
      DAY_SCOPED_QUERY_KEYS.todaysHabits(tomorrowYmd),
    );
    expect(DAY_SCOPED_QUERY_KEYS.habitsWithStats(todayYmd)).not.toEqual(
      DAY_SCOPED_QUERY_KEYS.habitsWithStats(tomorrowYmd),
    );
  });

  it('keeps day-relative review and upcoming keys isolated by business date', () => {
    expect(DAY_SCOPED_QUERY_KEYS.weeklyReview(todayYmd)).toEqual([QK.weeklyReview, todayYmd]);
    expect(DAY_SCOPED_QUERY_KEYS.upcomingTasks(todayYmd)).toEqual([
      QK.upcomingTasks,
      todayYmd,
      UPCOMING_TASKS_WINDOW_DAYS,
    ]);
    expect(DAY_SCOPED_QUERY_KEYS.upcomingWeekTasks(todayYmd)).toEqual([
      QK.upcomingWeekTasks,
      todayYmd,
      UPCOMING_TASKS_WINDOW_DAYS,
    ]);

    expect(DAY_SCOPED_QUERY_KEYS.weeklyReview(todayYmd)).not.toEqual(
      DAY_SCOPED_QUERY_KEYS.weeklyReview(tomorrowYmd),
    );
    expect(DAY_SCOPED_QUERY_KEYS.upcomingTasks(todayYmd)).not.toEqual(
      DAY_SCOPED_QUERY_KEYS.upcomingTasks(tomorrowYmd),
    );
  });

  it('keeps the query head first so existing prefix invalidation still matches', () => {
    expect(DAY_SCOPED_QUERY_KEYS.todaysHabits(todayYmd)[0]).toBe(QK.todaysHabits);
    expect(DAY_SCOPED_QUERY_KEYS.habitsWithStats(todayYmd)[0]).toBe(QK.habitsWithStats);
    expect(DAY_SCOPED_QUERY_KEYS.weeklyReview(todayYmd)[0]).toBe(QK.weeklyReview);
    expect(DAY_SCOPED_QUERY_KEYS.weeklyReviewHabits(todayYmd)[0]).toBe(QK.weeklyReviewHabits);
    expect(DAY_SCOPED_QUERY_KEYS.upcomingTasks(todayYmd)[0]).toBe(QK.upcomingTasks);
    expect(DAY_SCOPED_QUERY_KEYS.upcomingWeekTasks(todayYmd)[0]).toBe(QK.upcomingWeekTasks);
  });
});
