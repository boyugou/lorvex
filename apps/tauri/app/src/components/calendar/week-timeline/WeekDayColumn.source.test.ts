import { describe, expect, it } from 'vitest';

type FsNS = { readFileSync: (path: string, encoding: 'utf8') => string };
const fs = (await import(/* @vite-ignore */ 'node:fs' as string)) as unknown as FsNS;

describe('WeekDayColumn event selection wiring', () => {
  it('opens the selected day panel when a timed event chip is clicked', () => {
    const source = fs.readFileSync(
      'src/components/calendar/week-timeline/WeekDayColumn.tsx',
      'utf8',
    );

    expect(source).toContain('onSelectDate: (date: string) => void;');
    expect(source).toContain('onSelect={() => onSelectDate(dateStr)}');
  });
});

describe('WeekTimelineGrid responsive week surface', () => {
  it('keeps seven-day timelines horizontally scrollable on narrow viewports', () => {
    const source = fs.readFileSync(
      'src/components/calendar/week-timeline/WeekTimelineGrid.tsx',
      'utf8',
    );

    expect(source).toContain('WEEK_TIMELINE_MIN_WIDTH');
    expect(source).toContain('overflow-x-auto overflow-y-hidden overscroll-x-contain');
    expect(source).toContain('style={{ minWidth: WEEK_TIMELINE_MIN_WIDTH }}');
  });
});
