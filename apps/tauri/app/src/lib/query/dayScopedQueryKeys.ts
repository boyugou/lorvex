import { QUERY_KEYS } from './queryKeyFactory';

export const UPCOMING_TASKS_WINDOW_DAYS = 7;

export const DAY_SCOPED_QUERY_KEYS = {
  todaysHabits: (todayYmd: string) => QUERY_KEYS.todaysHabits(todayYmd),
  habitsWithStats: (todayYmd: string) => QUERY_KEYS.habitsWithStats(todayYmd),
  weeklyReview: (todayYmd: string) => QUERY_KEYS.weeklyReview(todayYmd),
  weeklyReviewHabits: (todayYmd: string) => QUERY_KEYS.weeklyReviewHabits(todayYmd),
  upcomingTasks: (todayYmd: string, days = UPCOMING_TASKS_WINDOW_DAYS) => QUERY_KEYS.upcomingTasks(todayYmd, days),
  upcomingWeekTasks: (todayYmd: string, days = UPCOMING_TASKS_WINDOW_DAYS) =>
    QUERY_KEYS.upcomingWeekTasks(todayYmd, days),
};
