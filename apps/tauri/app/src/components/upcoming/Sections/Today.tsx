import { DateSection } from './DateSection';
import type { ComponentProps } from 'react';

/**
 * Renders today's column (if present in `futureDates`) inside the
 * Upcoming list view. Today is conceptually distinct from the rest of
 * the week — the user often opens this view to see "what's left for
 * today" — so it owns its own section component rather than being
 * lumped into the week grid.
 */
export function Today({ dates, ...sectionProps }: { dates: readonly string[] } & DateSectionContextProps) {
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

/**
 * Shared prop bag passed straight through from the orchestrator. Each
 * `Sections/{Today,Week,Later}.tsx` accepts the same shape; the type
 * lives here so the three siblings stay in lockstep.
 */
export type DateSectionContextProps = Omit<
  ComponentProps<typeof DateSection>,
  'date' | 'dayTasks' | 'dayEvents' | 'collapsed' | 'isDragOver' | 'onToggleCollapse'
> & {
  groupedTasks: Record<string, ComponentProps<typeof DateSection>['dayTasks']>;
  groupedEvents: Record<string, ComponentProps<typeof DateSection>['dayEvents']>;
  collapsedDates: Set<string>;
  dragOverDate: string | null;
  toggleDateCollapse: (date: string) => void;
};
