import { DateSection } from './DateSection';
import type { DateSectionContextProps } from './Today';

/**
 * Renders every future date beyond the 7-day "this week" horizon as
 * individual `DateSection` columns. Same prop shape as `Today` /
 * `Week` — only the date slice differs.
 */
export function Later({ dates, ...sectionProps }: { dates: readonly string[] } & DateSectionContextProps) {
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
