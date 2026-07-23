import { DateSection } from './DateSection';
import type { DateSectionContextProps } from './Today';

/**
 * Renders the next 6 days after today as individual `DateSection`
 * columns. The orchestrator slices `futureDates` into the Today /
 * Week / Later groups upstream so each section component receives only
 * the dates it needs to draw.
 */
export function Week({ dates, ...sectionProps }: { dates: readonly string[] } & DateSectionContextProps) {
  return (
    <>
      {dates.map((date) => (
        <DateSection
          key={date}
          date={date}
          {...sectionProps}
          dayTasks={sectionProps.groupedTasks[date] ?? []}
          dayEvents={sectionProps.groupedEvents[date] ?? []}
          collapsed={sectionProps.collapsedDates.has(date)}
          isDragOver={sectionProps.dragOverDate === date}
          onToggleCollapse={() => sectionProps.toggleDateCollapse(date)}
        />
      ))}
    </>
  );
}
