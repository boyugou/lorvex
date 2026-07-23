import { memo, type MouseEvent as ReactMouseEvent } from 'react';
import type { DashboardSection } from '@/lib/ipc/dashboard';
import type { CurrentFocusWithTasks, FocusScheduleWithTasks, Overview, Task } from '@/lib/ipc/tasks/models';
import { DashboardSectionRenderer } from './sections';

interface CommonRendererProps {
  plan: CurrentFocusWithTasks | null | undefined;
  overview: Overview | null;
  focusSchedule: FocusScheduleWithTasks | null;
  somedayTasks: Task[];
  upcomingWeekTasks: Task[];
  overdueTasks: Task[];
  todayPoolTasks: Task[];
  onSelectTask?: ((taskId: string) => void) | undefined;
  focusedTaskId: string | null;
  aiBriefingEnabled: boolean;
}

interface FocusTopProps extends CommonRendererProps {
  focusSection: DashboardSection;
}

/**
 * Renders the dedicated "focus" pinned-to-top section. Memoized so
 * unrelated state changes (selection mode, picker open/close,
 * keyboard nav focus moving inside non-focus sections) don't
 * re-render the focus board.
 */
export const TodayFocusTopSection = memo(function TodayFocusTopSection({
  focusSection,
  ...common
}: FocusTopProps) {
  return (
    <DashboardSectionRenderer
      key="focus-top"
      section={focusSection}
      {...common}
    />
  );
});

interface NonFocusProps extends CommonRendererProps {
  sections: DashboardSection[];
  selectionMode: boolean;
  selectedIds: Set<string>;
  bulkBusy: boolean;
  onToggleSelected: (taskId: string) => void;
  onClickWithModifiers: (id: string, event: ReactMouseEvent<HTMLButtonElement>) => void;
}

/**
 * Renders the cascade of non-focus dashboard sections
 * (priority, overdue, upcoming-week, someday, recently-completed,
 * habits, stats). Memoized at the boundary so selection mode toggles
 * and overview/plan ticks each re-render only the cards that actually
 * read the changed prop.
 */
export const TodayNonFocusSections = memo(function TodayNonFocusSections({
  sections,
  selectionMode,
  selectedIds,
  bulkBusy,
  onToggleSelected,
  onClickWithModifiers,
  ...common
}: NonFocusProps) {
  return (
    <>
      {sections.map((section, index) => (
        <DashboardSectionRenderer
          key={`${section.type}-${index}`}
          section={section}
          {...common}
          selectionMode={selectionMode}
          selectedIds={selectedIds}
          bulkBusy={bulkBusy}
          onToggleSelected={onToggleSelected}
          onClickWithModifiers={onClickWithModifiers}
        />
      ))}
    </>
  );
});
