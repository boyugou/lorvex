import type { DashboardSection } from '@/lib/ipc/dashboard';
import type { CurrentFocusWithTasks, Overview, Task } from '@/lib/ipc/tasks/models';
import { isTaskInRelativeSections } from '@/lib/tasks/dayBuckets';
import { compareTaskByPriorityThenDue } from '@/lib/tasks/taskComparators';
import { rankFallbackFocusTask } from './taskOrdering';
import { TASK_STATUS } from '@lorvex/shared/types';

/** Extract visible task IDs from a dashboard section (mirrors DashboardSectionRenderer logic). */
export function getSectionTaskIds(
  section: DashboardSection,
  plan: CurrentFocusWithTasks | null | undefined,
  overview: Overview | null,
  overdueTasks: Task[],
  todayPoolTasks: Task[],
  somedayTasks: Task[],
  upcomingWeekTasks: Task[],
  todayYmd: string,
): string[] {
  // Build the open-task id set once instead of running a nested
  // `tasks.some(...)` scan inside the `task_ids.filter(...)` — the
  // original was O(focus_ids × focus_tasks) on every call.
  const openTaskIdSet = plan
    ? new Set(plan.tasks.filter((t) => t.status === TASK_STATUS.open).map((t) => t.id))
    : null;
  const focusOpenIds = plan && openTaskIdSet
    ? plan.task_ids.filter((id) => openTaskIdSet.has(id))
    : [];

  switch (section.type) {
    case 'focus':
      return plan && focusOpenIds.length > 0 ? focusOpenIds.slice(0, section.limit) : [];

    case 'priority': {
      const rawSrc = overview?.top_by_priority ?? [];
      if (rawSrc.length === 0 || focusOpenIds.length > 0) return [];
      const shownIds = new Set([
        ...overdueTasks.map((t) => t.id),
        ...todayPoolTasks.map((t) => t.id),
      ]);
      const src = rawSrc.filter((t) => !shownIds.has(t.id) && isTaskInRelativeSections(t, todayYmd, ['overdue', 'today', 'tomorrow', 'this_week', 'no_date']));
      const sorted = !plan
        ? [...src].sort((a, b) => {
            const rankDiff = rankFallbackFocusTask(a, todayYmd) - rankFallbackFocusTask(b, todayYmd);
            if (rankDiff !== 0) return rankDiff;
            const priA = a.priority ?? 3;
            const priB = b.priority ?? 3;
            if (priA !== priB) return priA - priB;
            return compareTaskByPriorityThenDue(a, b);
          })
        : src;
      return sorted.slice(0, section.limit ?? 10).map((t) => t.id);
    }

    case 'overdue_alert': {
      if ((overview?.stats?.overdue_count ?? 0) === 0) return [];
      const focusSet = new Set(focusOpenIds);
      return overdueTasks.filter((t) => !focusSet.has(t.id)).slice(0, section.limit ?? 5).map((t) => t.id);
    }

    case 'recently_completed':
      return (overview?.recently_completed ?? []).slice(0, section.limit ?? 5).map((t) => t.id);

    case 'someday_peek':
      return somedayTasks.slice(0, section.limit ?? 3).map((t) => t.id);

    case 'upcoming_week':
      return upcomingWeekTasks.slice(0, section.limit ?? 5).map((t) => t.id);

    // These section types do not surface task IDs — they're header-only
    // decorations, metric readouts, or habit checklists. Listing them
    // explicitly lets the exhaustiveness guard catch genuinely new variants.
    case 'ai_briefing':
    case 'schedule':
    case 'habits':
    case 'stats':
      return [];

    default: {
      // Exhaustiveness guard: adding a new DashboardSection['type'] must
      // trigger a TypeScript error here. We still return [] at runtime so
      // unknown sections silently contribute no task IDs.
      const _exhaustive: never = section.type;
      void _exhaustive;
      return [];
    }
  }
}
