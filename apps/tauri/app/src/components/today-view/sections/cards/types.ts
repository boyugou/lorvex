import type { MouseEvent as ReactMouseEvent } from 'react';
import type { DashboardSection } from '@/lib/ipc/dashboard';
import type { CurrentFocusWithTasks, FocusScheduleWithTasks, Overview, Task } from '@/lib/ipc/tasks/models';

/**
 * Common props the dashboard cards consume — pulled out of the
 * monolithic `DashboardSectionRenderer` switch so each card can be
 * memoized at its own boundary. Every card receives this as its
 * baseline prop bundle plus its own narrow section-shape prop.
 */
export interface DashboardCardCommonProps {
  plan: CurrentFocusWithTasks | null | undefined;
  overview: Overview | null;
  focusSchedule: FocusScheduleWithTasks | null;
  somedayTasks: Task[];
  upcomingWeekTasks: Task[];
  overdueTasks: Task[];
  todayPoolTasks: Task[];
  onSelectTask?: ((taskId: string) => void) | undefined;
  focusedTaskId?: string | null | undefined;
  aiBriefingEnabled: boolean;
  selectionMode: boolean;
  selectedIds?: Set<string> | undefined;
  bulkBusy: boolean;
  onToggleSelected?: ((taskId: string) => void) | undefined;
  onClickWithModifiers?: ((id: string, event: ReactMouseEvent<HTMLButtonElement>) => void) | undefined;
  collapsed: boolean;
  toggle: () => void;
}

/**
 * `DashboardSection` is a flat interface (single `type` discriminator
 * + optional `limit`) rather than a discriminated union, so this
 * alias is just `DashboardSection` — kept as a parameterized name so
 * future shape narrowing can land in one place if the wire schema
 * splits per-kind.
 */
export type SectionOf<_K extends DashboardSection['type']> = DashboardSection;
