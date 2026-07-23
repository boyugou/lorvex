import { describe, expect, it } from 'vitest';

type FsNS = { readFileSync: (path: string, encoding: 'utf8') => string };
const fs = (await import(/* @vite-ignore */ 'node:fs' as string)) as unknown as FsNS;

describe('CalendarViewContent week timeline shell', () => {
  it('bounds week mode as a flex surface so the timeline owns vertical scrolling', () => {
    const source = fs.readFileSync('src/components/calendar/CalendarViewContent.tsx', 'utf8');

    expect(source).toContain('!isCalendarLoading && !hasCalendarError && (viewMode ===');
    expect(source).toContain("viewMode === 'month' || viewMode === 'week'");
    expect(source).toContain("? 'min-h-0 flex flex-col'");
    expect(source).toContain(": 'overflow-y-auto overscroll-contain'");
    expect(source).toContain('${calendarContentLayoutClass}');
    expect(source).toMatch(
      /<div className="animate-\[fade-in_0\.15s_ease-out\] flex-1 min-h-0 flex flex-col">\s*<WeekGrid/,
    );
  });
});
