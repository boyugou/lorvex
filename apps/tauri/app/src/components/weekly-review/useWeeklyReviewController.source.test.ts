import { describe, expect, it } from 'vitest';

type FsNS = { readFileSync: (path: string, encoding: 'utf8') => string };
const fs = (await import(/* @vite-ignore */ 'node:fs' as string)) as unknown as FsNS;

const controllerPath = 'src/components/weekly-review/useWeeklyReviewController.ts';

describe('weekly review looking-ahead window contract', () => {
  it('uses the centralized seven-day looking-ahead window for tasks, events, and query keys', () => {
    const source = fs.readFileSync(controllerPath, 'utf8');

    expect(source).toContain('WEEKLY_REVIEW_LOOKING_AHEAD_DAYS');
    expect(source).toContain('getWeeklyReviewLookingAheadWindow(dayContext.todayYmd)');
    expect(source).toContain('QUERY_KEYS.weeklyReviewUpcoming(nextWeekStart, nextWeekEnd)');
    expect(source).toContain('QUERY_KEYS.weeklyReviewEvents(nextWeekStart, nextWeekEnd)');
    expect(source).toContain('getUpcomingTasks(WEEKLY_REVIEW_LOOKING_AHEAD_DAYS, signal)');
    expect(source).not.toMatch(/addYmdDays\(dayContext\.todayYmd,\s*8\)/);
    expect(source).not.toMatch(/getUpcomingTasks\(8,\s*signal\)/);
  });
});
