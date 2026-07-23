import { useCallback, useMemo, useSyncExternalStore, type MouseEvent as ReactMouseEvent } from 'react';
import type { DashboardSection } from '@/lib/ipc/dashboard';
import type { CurrentFocusWithTasks, FocusScheduleWithTasks, Overview, Task } from '@/lib/ipc/tasks/models';
import {
  isCollapsedSectionKeyArray,
  readCollapsedSectionSet,
  serializeCollapsedSectionSet,
  toggleCollapsedSection,
} from '@/lib/collapsibleSections.logic';
import { getUIState, setUIState } from '@/lib/storage/uiState';
import { FocusSection } from '../FocusSection';
import { TodayHabitsSection } from './TodayHabitsSection';
import { SectionAiBriefingCard } from './cards/SectionAiBriefingCard';
import { SectionOverdueAlertCard } from './cards/SectionOverdueAlertCard';
import {
  SectionScheduleCard,
  SectionStatsCard,
} from './cards/SectionScheduleStatsCards';
import {
  SectionPriorityCard,
  SectionRecentlyCompletedCard,
  SectionSomedayPeekCard,
  SectionUpcomingWeekCard,
} from './cards/SimpleListSectionCards';
import type { DashboardCardCommonProps } from './cards/types';
import { TASK_STATUS } from '@lorvex/shared/types';

// Collapse state persisted in localStorage under `lorvex:dashboard.collapsedSections`.
const COLLAPSE_PK = 'dashboard.collapsedSections';

let collapsedListeners: Array<() => void> = [];

function getCollapsedSnapshot(): Set<string> {
  // Runtime-validate the stored shape. Without this, a malformed
  // blob (older version, hand-edited devtools value, crash
  // mid-write) would flow into `new Set()` and silently poison every
  // downstream `.has(sectionType)` lookup — the dashboard would
  // randomly show or hide sections depending on prior corruption.
  const stored = getUIState<string[]>(COLLAPSE_PK, [], isCollapsedSectionKeyArray);
  return readCollapsedSectionSet(stored);
}

let cachedCollapsed: Set<string> | null = null;
function subscribeCollapsed(cb: () => void) {
  collapsedListeners.push(cb);
  return () => { collapsedListeners = collapsedListeners.filter((l) => l !== cb); };
}
function snapshotCollapsed() {
  if (!cachedCollapsed) cachedCollapsed = getCollapsedSnapshot();
  return cachedCollapsed;
}
function toggleCollapsed(sectionType: string) {
  const next = toggleCollapsedSection(getCollapsedSnapshot(), sectionType);
  setUIState(COLLAPSE_PK, serializeCollapsedSectionSet(next));
  cachedCollapsed = next;
  for (const cb of collapsedListeners) cb();
}

export function useCollapsedSections() {
  return useSyncExternalStore(subscribeCollapsed, snapshotCollapsed);
}

interface SectionRendererProps {
  section: DashboardSection;
  plan: CurrentFocusWithTasks | null | undefined;
  overview: Overview | null;
  focusSchedule: FocusScheduleWithTasks | null;
  somedayTasks: Task[];
  upcomingWeekTasks: Task[];
  overdueTasks: Task[];
  todayPoolTasks?: Task[] | undefined;
  onSelectTask?: ((taskId: string) => void) | undefined;
  focusedTaskId?: string | null | undefined;
  aiBriefingEnabled?: boolean | undefined;
  selectionMode?: boolean | undefined;
  selectedIds?: Set<string> | undefined;
  bulkBusy?: boolean | undefined;
  onToggleSelected?: ((taskId: string) => void) | undefined;
  onClickWithModifiers?: ((id: string, event: ReactMouseEvent<HTMLButtonElement>) => void) | undefined;
}

/**
 * Per-kind dispatcher: each `DashboardSection.type` routes to its
 * own memoized `Section*Card` component in `./cards/`. The switch
 * here stays exhaustiveness-checked via the `never` default. Per
 * , splitting the renderer so each card is its own memoized
 * boundary lets a state tick that only affects (e.g.) the overdue
 * card avoid re-rendering the priority list directly above it.
 */
export function DashboardSectionRenderer(props: SectionRendererProps) {
  const {
    section,
    todayPoolTasks = [],
    aiBriefingEnabled = true,
    selectionMode = false,
    bulkBusy = false,
    plan,
    onSelectTask,
    focusedTaskId,
  } = props;
  const collapsedSet = useCollapsedSections();
  const collapsed = collapsedSet.has(section.type);
  const toggle = useCallback(() => toggleCollapsed(section.type), [section.type]);

  // Hoist the focus-section open-task filter out of the switch render so
  // the array identity is stable across renders when `plan.tasks` hasn't
  // changed (matters for the downstream `FocusSection` memo gate).
  const focusTasks = useMemo<Task[]>(
    () => (plan?.tasks ?? []).filter((task) => task.status === TASK_STATUS.open),
    [plan?.tasks],
  );

  const common: DashboardCardCommonProps = {
    plan,
    overview: props.overview,
    focusSchedule: props.focusSchedule,
    somedayTasks: props.somedayTasks,
    upcomingWeekTasks: props.upcomingWeekTasks,
    overdueTasks: props.overdueTasks,
    todayPoolTasks,
    onSelectTask,
    focusedTaskId,
    aiBriefingEnabled,
    selectionMode,
    selectedIds: props.selectedIds,
    bulkBusy,
    onToggleSelected: props.onToggleSelected,
    onClickWithModifiers: props.onClickWithModifiers,
    collapsed,
    toggle,
  };

  switch (section.type) {
    case 'ai_briefing':
      return <SectionAiBriefingCard section={section} {...common} />;

    case 'focus': {
      if (!plan || focusTasks.length === 0) return null;
      return (
        <FocusSection
          section={section}
          plan={plan}
          onSelectTask={onSelectTask}
          focusedTaskId={focusedTaskId}
          collapsed={collapsed}
          onToggleCollapse={toggle}
        />
      );
    }

    case 'schedule':
      return <SectionScheduleCard section={section} {...common} />;

    case 'priority':
      return <SectionPriorityCard section={section} {...common} />;

    case 'overdue_alert':
      return <SectionOverdueAlertCard section={section} {...common} />;

    case 'recently_completed':
      return <SectionRecentlyCompletedCard section={section} {...common} />;

    case 'someday_peek':
      return <SectionSomedayPeekCard section={section} {...common} />;

    case 'upcoming_week':
      return <SectionUpcomingWeekCard section={section} {...common} />;

    case 'habits':
      return <TodayHabitsSection collapsed={collapsed} onToggleCollapse={toggle} />;

    case 'stats':
      return <SectionStatsCard section={section} {...common} />;

    default: {
      // Exhaustiveness guard: adding a new DashboardSection['type'] must
      // trigger a TypeScript error here. We still return null at runtime so
      // unknown sections render gracefully in production.
      const _exhaustive: never = section.type;
      void _exhaustive;
      return null;
    }
  }
}
