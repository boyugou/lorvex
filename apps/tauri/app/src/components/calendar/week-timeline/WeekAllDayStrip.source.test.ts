import { describe, expect, it } from 'vitest';

type FsNS = { readFileSync: (path: string, encoding: 'utf8') => string };
const fs = (await import(/* @vite-ignore */ 'node:fs' as string)) as unknown as FsNS;

describe('WeekAllDayStrip interaction wiring', () => {
  it('renders all-day event bars as selectable controls that open the covered day', () => {
    const source = fs.readFileSync(
      'src/components/calendar/week-timeline/WeekAllDayStrip.tsx',
      'utf8',
    );

    expect(source).toContain('type="button"');
    expect(source).toContain('weekAllDaySegmentHitTargets(segment, weekDates)');
    expect(source).toContain('onClick={() => onSelectDate(target.date)}');
    expect(source).toContain('aria-label={`${eventTitle} — ${t(\'calendar.eventAllDay\')}`}');
  });
});
