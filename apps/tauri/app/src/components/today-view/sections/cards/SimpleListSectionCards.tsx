import { memo } from 'react';

import { useI18n } from '@/lib/i18n';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { isTaskInRelativeSections } from '@/lib/tasks/dayBuckets';
import { compareTaskByPriorityThenDue } from '@/lib/tasks/taskComparators';
import TaskCard from '@/components/task-card/TaskCard';
import { InteractiveTaskCard } from '@/components/task-card/InteractiveTaskCard';
import { SwipeableTaskCard } from '@/components/task-card/SwipeableTaskCard';
import { CollapsibleSection } from '@/components/ui/CollapsibleSection';
import { SectionHeader } from '@/components/today-view/primitives';
import { rankFallbackFocusTask } from '@/components/today-view/taskOrdering';
import type { Task } from '@/lib/ipc/tasks/models';
import type { DashboardCardCommonProps, SectionOf } from './types';
import { TASK_STATUS } from '@lorvex/shared/types';

type RowProps = Pick<
  DashboardCardCommonProps,
  | 'selectionMode' | 'selectedIds' | 'bulkBusy' | 'focusedTaskId'
  | 'onSelectTask' | 'onToggleSelected' | 'onClickWithModifiers'
>;

function InteractiveRows({
  tasks,
  rowProps,
}: { tasks: Task[]; rowProps: RowProps }) {
  const hasSelection = (rowProps.selectedIds?.size ?? 0) > 0;
  return (
    <div className="space-y-1.5">
      {tasks.map((task) => (
        <InteractiveTaskCard
          key={task.id}
          task={task}
          selectionMode={rowProps.selectionMode}
          selected={rowProps.selectedIds?.has(task.id) ?? false}
          bulkBusy={rowProps.bulkBusy}
          focused={rowProps.focusedTaskId === task.id}
          hasSelection={hasSelection}
          showListColor={false}
          onToggleSelected={rowProps.onToggleSelected ?? (() => {})}
          onSelect={(id) => rowProps.onSelectTask?.(id)}
          onClickWithModifiers={rowProps.onClickWithModifiers}
        />
      ))}
    </div>
  );
}

/**
 * Priority section — the dashboard's "by priority" fallback list,
 * shown only when no focus plan exists. Filters out tasks already
 * shown in overdue/today pools and applies the legacy fallback
 * ranking so users see the most actionable items first.
 */
export const SectionPriorityCard = memo(function SectionPriorityCard({
  section,
  ...common
}: { section: SectionOf<'priority'> } & DashboardCardCommonProps) {
  const { t } = useI18n();
  const dayContext = useConfiguredDayContext();
  const focusTasks = (common.plan?.tasks ?? []).filter((task) => task.status === TASK_STATUS.open);
  const rawSourceTasks = common.overview?.top_by_priority ?? [];
  if (rawSourceTasks.length === 0) return null;
  if (focusTasks.length > 0) return null;
  const shownIds = new Set([
    ...common.overdueTasks.map((task) => task.id),
    ...common.todayPoolTasks.map((task) => task.id),
  ]);
  const todayIso = dayContext.todayYmd;
  const sourceTasks = rawSourceTasks.filter((task) => {
    if (shownIds.has(task.id)) return false;
    return isTaskInRelativeSections(task, todayIso, ['overdue', 'today', 'tomorrow', 'this_week', 'no_date']);
  });
  if (sourceTasks.length === 0) return null;
  const tasks = !common.plan
    ? [...sourceTasks].sort((left, right) => {
        const rankDiff =
          rankFallbackFocusTask(left, todayIso) - rankFallbackFocusTask(right, todayIso);
        if (rankDiff !== 0) return rankDiff;
        const priLeft = left.priority ?? 3;
        const priRight = right.priority ?? 3;
        if (priLeft !== priRight) return priLeft - priRight;
        return compareTaskByPriorityThenDue(left, right);
      })
    : sourceTasks;
  const sliced = tasks.slice(0, section.limit ?? 10);
  return (
    <section>
      <SectionHeader
        title={t('today.byPriority')}
        subtitle={!common.plan ? t('today.fallbackOrderHint') : t('today.noFocusPlan')}
        count={tasks.length}
        collapsed={common.collapsed}
        onToggleCollapse={common.toggle}
      />
      <CollapsibleSection collapsed={common.collapsed}>
        <InteractiveRows tasks={sliced} rowProps={common} />
      </CollapsibleSection>
    </section>
  );
});

/** Recently-completed section — non-interactive cards in a swipeable wrapper. */
export const SectionRecentlyCompletedCard = memo(function SectionRecentlyCompletedCard({
  section,
  ...common
}: { section: SectionOf<'recently_completed'> } & DashboardCardCommonProps) {
  const { t } = useI18n();
  const items = common.overview?.recently_completed ?? [];
  if (items.length === 0) return null;
  return (
    <section className="mt-4">
      <SectionHeader title={t('today.recentlyCompleted')} count={items.length} collapsed={common.collapsed} onToggleCollapse={common.toggle} />
      <CollapsibleSection collapsed={common.collapsed}>
        <div className="space-y-1.5">
          {items.slice(0, section.limit ?? 5).map((task) => (
            <SwipeableTaskCard key={task.id} task={task}>
              <TaskCard task={task} completed focused={common.focusedTaskId === task.id} showListColor={false} onClick={() => common.onSelectTask?.(task.id)} />
            </SwipeableTaskCard>
          ))}
        </div>
      </CollapsibleSection>
    </section>
  );
});

/** Someday-maybe peek — dimmed list of low-priority backlog. */
export const SectionSomedayPeekCard = memo(function SectionSomedayPeekCard({
  section,
  ...common
}: { section: SectionOf<'someday_peek'> } & DashboardCardCommonProps) {
  const { t } = useI18n();
  if (common.somedayTasks.length === 0) return null;
  const sliced = common.somedayTasks.slice(0, section.limit ?? 3);
  return (
    <section className="mt-4">
      <SectionHeader title={t('today.somedayMaybe')} count={common.somedayTasks.length} collapsed={common.collapsed} onToggleCollapse={common.toggle} />
      <CollapsibleSection collapsed={common.collapsed}>
        <div className="opacity-70">
          <InteractiveRows tasks={sliced} rowProps={common} />
        </div>
      </CollapsibleSection>
    </section>
  );
});

/** Upcoming-week section. */
export const SectionUpcomingWeekCard = memo(function SectionUpcomingWeekCard({
  section,
  ...common
}: { section: SectionOf<'upcoming_week'> } & DashboardCardCommonProps) {
  const { t } = useI18n();
  if (common.upcomingWeekTasks.length === 0) return null;
  const sliced = common.upcomingWeekTasks.slice(0, section.limit ?? 5);
  return (
    <section>
      <SectionHeader title={t('today.upcomingWeek')} count={common.upcomingWeekTasks.length} collapsed={common.collapsed} onToggleCollapse={common.toggle} />
      <CollapsibleSection collapsed={common.collapsed}>
        <InteractiveRows tasks={sliced} rowProps={common} />
      </CollapsibleSection>
    </section>
  );
});
