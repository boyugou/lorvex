import { describe, expect, it } from 'vitest';

type FsNS = { readFileSync: (path: string, encoding: 'utf8') => string };
const fs = (await import(/* @vite-ignore */ 'node:fs' as string)) as unknown as FsNS;

describe('DayEventRow event control labels', () => {
  it('uses composed event context for editable and non-editable rows', () => {
    const source = fs.readFileSync('src/components/calendar/day-panel/DayEventRow.tsx', 'utf8');

    expect(source).toContain('formatCalendarEventAccessibleLabel(event');
    expect(source).toContain('role="group" aria-label={eventLabel}');
    expect(source).toContain('aria-label={eventLabel}');
    expect(source).toContain('const deleteLabel = `${t(\'calendar.deleteEvent\')}: ${eventLabel}`;');
    expect(source).not.toContain('aria-label={event.title}');
  });
});
