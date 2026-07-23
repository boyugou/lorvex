import { describe, expect, it } from 'vitest';

type FsNS = { readFileSync: (path: string, encoding: 'utf8') => string };
const fs = (await import(/* @vite-ignore */ 'node:fs' as string)) as unknown as FsNS;

describe('DayTimeline keyboard reschedule wiring', () => {
  it('attaches shortcut metadata and keyboard handling to task buttons', () => {
    const source = fs.readFileSync('src/components/calendar/day-panel/DayTimeline.tsx', 'utf8');

    expect(source).toContain('resolveDayTimelineKeyboardReschedule');
    expect(source).toContain('onKeyDown={makeTaskKeyDown(task.id, null)}');
    expect(source).toContain('onKeyDown={makeTaskKeyDown(pt.task.id, pt.task.due_time ?? null)}');
    expect(source).toContain('aria-keyshortcuts={onRescheduleTask ? DAY_TIMELINE_TASK_KEYSHORTCUTS : undefined}');
    expect(source).toContain("aria-description={onRescheduleTask ? t('calendar.dayTimelineKeyboardHint') : undefined}");
  });
});
