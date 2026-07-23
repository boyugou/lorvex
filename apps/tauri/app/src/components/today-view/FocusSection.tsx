import { useMemo } from 'react';
import type { DashboardSection } from '@/lib/ipc/dashboard';
import type { CurrentFocusWithTasks, Task } from '@/lib/ipc/tasks/models';
import { useI18n } from '@/lib/i18n';
import TaskCard from '../task-card/TaskCard';
import { SwipeableTaskCard } from '../task-card/SwipeableTaskCard';
import { CollapsibleSection } from '../ui/CollapsibleSection';
import { SectionHeader, formatDurationCompact } from './primitives';
import { useFocusReorderActions } from './useFocusReorderActions';
import { TASK_STATUS } from '@lorvex/shared/types';

export function FocusSection({
  section,
  plan,
  onSelectTask,
  focusedTaskId,
  collapsed,
  onToggleCollapse,
}: {
  section: DashboardSection;
  plan: CurrentFocusWithTasks;
  onSelectTask?: ((taskId: string) => void) | undefined;
  focusedTaskId?: string | null | undefined;
  collapsed?: boolean | undefined;
  onToggleCollapse?: (() => void) | undefined;
}) {
  const { t, formatNumber } = useI18n();

  const taskById = useMemo(() => {
    const map = new Map<string, Task>();
    for (const task of plan.tasks) {
      if (task.status === TASK_STATUS.open) map.set(task.id, task);
    }
    return map;
  }, [plan.tasks]);

  const planOpenTaskIds = useMemo(
    () => plan.task_ids.filter((taskId) => taskById.has(taskId)),
    [plan.task_ids, taskById],
  );
  const {
    dragOverId,
    draggingId,
    focusTaskIds,
    handleDragEnd,
    handleDragLeave,
    handleDragOver,
    handleDragStart,
    handleDropOn,
    handleTaskReorderKeyDown,
    isReorderPending,
    moveTaskByStep,
  } = useFocusReorderActions({
    planOpenTaskIds,
    t,
  });

  const focusTasks = useMemo(
    () => focusTaskIds.map((taskId) => taskById.get(taskId)).filter((task): task is Task => Boolean(task)),
    [focusTaskIds, taskById],
  );

  const focusDurationMinutes = useMemo(
    () => focusTasks.reduce((sum, task) => sum + (task.estimated_minutes ?? 0), 0),
    [focusTasks],
  );

  // The render below renders only `focusTasks.slice(0, section.limit)`,
  // so the "move down" button must compare against the visible count,
  // not the un-sliced length. Without this, when `section.limit <
  // focusTasks.length`, the last visible row's down button would stay
  // enabled and pressing it would move the task into a position
  // that isn't rendered. When `section.limit` is undefined, all
  // tasks render — fall back to the full length.
  const visibleCount = section.limit !== undefined
    ? Math.min(section.limit, focusTasks.length)
    : focusTasks.length;

  return (
    <section>
      <div className="flex items-baseline justify-between">
        <SectionHeader
          title={t('today.focus')}
          count={focusTasks.length}
          subtitle={focusDurationMinutes > 0 ? formatDurationCompact(focusDurationMinutes, t('common.hourShort'), t('common.min'), formatNumber) : undefined}
          collapsed={collapsed}
          onToggleCollapse={onToggleCollapse}
        />
      </div>
      <CollapsibleSection collapsed={collapsed ?? false}>
          <div className="space-y-1.5">
            {focusTasks.slice(0, section.limit).map((task, index) => {
              const isDragOver = dragOverId === task.id && draggingId && draggingId !== task.id;
              return (
                // HTML5 draggable wrapper. Inner <TaskCard> is the
                // actionable target and carries the keyboard metadata.
                // eslint-disable-next-line jsx-a11y/no-static-element-interactions
                <div
                  key={task.id}
                  draggable={!isReorderPending}
                  onDragStart={(event) => handleDragStart(task.id, event, task.title)}
                  onDragEnd={handleDragEnd}
                  onDragOver={(event) => handleDragOver(task.id, event)}
                  onDrop={(event) => {
                    event.preventDefault();
                    handleDropOn(task.id);
                  }}
                  onDragLeave={() => handleDragLeave(task.id)}
                  className={`group relative rounded-r-card transition-[box-shadow,opacity] cursor-grab active:cursor-grabbing ${isDragOver ? 'ring-1 ring-accent/50' : ''} ${draggingId === task.id ? 'opacity-50' : ''}`}
                >
                  {/* chevron-reveal wrapper uses the shared
                      `.reveal-on-hover--sm` modifier of the reveal
                      primitive. Below `sm` the cue is always shown;
                      at `sm`+ it gates on `(hover: hover)` so
                      tablet-class touch devices keep the buttons always-on
                      rather than stranded behind a hover state that
                      never fires. */}
                  <div className="absolute end-1 top-1 z-[var(--z-sticky)] flex flex-col gap-px reveal-on-hover--sm">
                      <button
                        type="button"
                        onClick={(e) => { e.stopPropagation(); moveTaskByStep(task.id, -1); }}
                        disabled={isReorderPending || index === 0}
                      aria-label={t('list.moveUp')}
                      className="h-6 w-6 rounded-r-control border border-surface-3 bg-surface-2 text-xs text-text-muted hover:text-text-primary active:bg-surface-3 disabled:opacity-40 disabled:cursor-not-allowed focus-ring-soft flex items-center justify-center"
                    >
                      ↑
                    </button>
                      <button
                        type="button"
                        onClick={(e) => { e.stopPropagation(); moveTaskByStep(task.id, 1); }}
                        disabled={isReorderPending || index === visibleCount - 1}
                      aria-label={t('list.moveDown')}
                      className="h-6 w-6 rounded-r-control border border-surface-3 bg-surface-2 text-xs text-text-muted hover:text-text-primary active:bg-surface-3 disabled:opacity-40 disabled:cursor-not-allowed focus-ring-soft flex items-center justify-center"
                    >
                      ↓
                    </button>
                  </div>
                  <SwipeableTaskCard task={task}>
                    <TaskCard
                      task={task}
                      rank={index + 1}
                      focused={focusedTaskId === task.id}
                      showListColor={false}
                      onClick={() => onSelectTask?.(task.id)}
                      onKeyDown={(event) => handleTaskReorderKeyDown(task.id, event)}
                      taskButtonAriaDescription={t('list.reorderHint')}
                      taskButtonAriaRoleDescription="draggable"
                      taskButtonAriaKeyShortcuts="Alt+ArrowUp Alt+ArrowDown"
                    />
                  </SwipeableTaskCard>
                </div>
              );
            })}
          </div>
      </CollapsibleSection>
    </section>
  );
}
