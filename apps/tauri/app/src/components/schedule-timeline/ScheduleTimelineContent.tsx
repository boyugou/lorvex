import { useCallback, useMemo } from 'react';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { useI18n } from '@/lib/i18n';
import type { FocusScheduleWithTasks } from '@/lib/ipc/tasks/models';
import { parseTimeToMinutes } from '@/lib/timeUtils';
import { useCurrentTime } from '@/lib/time/useCurrentTime';
import { NowMarker, BufferBlock, EventBlock, ProgressBar } from './BlockComponents';
import { TaskBlock } from './TaskBlock';
import { useScheduleTimelineActions } from './useScheduleTimelineActions';
import { TASK_STATUS } from '@lorvex/shared/types';

type TaskScheduleBlock = FocusScheduleWithTasks['blocks'][number] & { block_type: 'task'; task_id: string };

interface Props {
  schedule: FocusScheduleWithTasks;
  onSelectTask?: ((taskId: string) => void) | undefined;
}

export default function ScheduleTimelineContent({ schedule, onSelectTask }: Props) {
  const { t } = useI18n();
  const dayContext = useConfiguredDayContext();
  const nowTime = useCurrentTime(dayContext.timezone);
  const nowMinutes = parseTimeToMinutes(nowTime);
  const taskMap = useMemo(
    () => new Map(schedule.tasks.map(task => [task.id, task])),
    [schedule.tasks],
  );
  const {
    completingIds,
    dismissMutation,
    handleCompleteTask,
    handleDismissSchedule,
    handleMoveTask,
    handleRemoveTask,
  } = useScheduleTimelineActions({
    blocks: schedule.blocks,
    t,
  });

  const blocks = schedule.blocks;
  const scheduleStart = blocks.length > 0 ? parseTimeToMinutes(blocks[0]!.start_time) : null;
  const scheduleEnd = blocks.length > 0 ? parseTimeToMinutes(blocks[blocks.length - 1]!.end_time) : null;
  const showNow = blocks.length > 0
    && nowMinutes != null
    && scheduleStart != null
    && scheduleEnd != null
    && nowMinutes >= scheduleStart
    && nowMinutes < scheduleEnd;

  const taskBlocks = useMemo(
    () => blocks.filter((b): b is TaskScheduleBlock => b.block_type === 'task' && typeof b.task_id === 'string'),
    [blocks],
  );
  const completedCount = useMemo(
    () => taskBlocks.filter((b) => {
      const task = taskMap.get(b.task_id);
      return task?.status === TASK_STATUS.completed || completingIds.includes(b.task_id);
    }).length,
    [taskBlocks, taskMap, completingIds],
  );

  const taskBlockIds = useMemo(
    () => taskBlocks.map((b) => b.task_id),
    [taskBlocks],
  );

  const handleSelectTask = useCallback(
    (taskId: string) => onSelectTask?.(taskId),
    [onSelectTask],
  );
  const handleMoveTaskUp = useCallback(
    (taskId: string, e: React.MouseEvent) => handleMoveTask(taskId, 'up', e),
    [handleMoveTask],
  );
  const handleMoveTaskDown = useCallback(
    (taskId: string, e: React.MouseEvent) => handleMoveTask(taskId, 'down', e),
    [handleMoveTask],
  );

  return (
    <div>
      {taskBlocks.length > 0 && (
        <ProgressBar completed={completedCount} total={taskBlocks.length} />
      )}

      {schedule.rationale && (
        <div className="bg-accent/5 border border-accent/20 rounded-r-card px-4 py-3 mb-3">
          <p className="text-text-muted text-xs font-medium mb-1">
            {'\u2726'} {t('today.scheduleRationale')}
          </p>
          <p className="text-text-secondary text-sm leading-relaxed">{schedule.rationale}</p>
        </div>
      )}

      <div className="space-y-0">
        {blocks.map((block, i) => {
          const blockStart = parseTimeToMinutes(block.start_time);
          const blockEnd = parseTimeToMinutes(block.end_time);
          const isCurrent = showNow
            && nowMinutes != null
            && blockStart != null
            && blockEnd != null
            && nowMinutes >= blockStart
            && nowMinutes < blockEnd;
          const nextBlock = blocks[i + 1];
          const nextBlockStart = nextBlock ? parseTimeToMinutes(nextBlock.start_time) : null;
          const showNowAfter = showNow
            && !isCurrent
            && nowMinutes != null
            && blockEnd != null
            && nowMinutes >= blockEnd
            && (!nextBlock || nextBlockStart == null || nowMinutes < nextBlockStart);

          if (block.block_type === 'buffer') {
            return (
              <div key={`buffer-${i}`}>
                <BufferBlock block={block} />
                {showNowAfter && <NowMarker time={nowTime} />}
              </div>
            );
          }

          if (block.block_type === 'event') {
            return (
              <div key={`event-${block.event_id ?? i}`}>
                <EventBlock block={block} />
                {showNowAfter && <NowMarker time={nowTime} />}
              </div>
            );
          }

          if (typeof block.task_id !== 'string') {
            return null;
          }

          const taskId = block.task_id;
          const task = taskMap.get(taskId);
          if (!task) return null;

          const taskPos = taskBlockIds.indexOf(taskId);

          return (
            <div key={taskId}>
              <TaskBlock
                block={block}
                task={task}
                taskId={taskId}
                isActive={isCurrent && task.status !== TASK_STATUS.completed}
                completing={completingIds.includes(taskId)}
                onComplete={handleCompleteTask}
                onSelect={handleSelectTask}
                onRemove={handleRemoveTask}
                onMoveUp={handleMoveTaskUp}
                onMoveDown={handleMoveTaskDown}
                canMoveUp={taskPos > 0}
                canMoveDown={taskPos < taskBlockIds.length - 1}
              />
              {showNowAfter && <NowMarker time={nowTime} />}
            </div>
          );
        })}
      </div>

      <div className="flex gap-2 mt-3 px-3">
        <button
          type="button"
          onClick={handleDismissSchedule}
          disabled={dismissMutation.isPending}
          className="flex-1 rounded-r-card border border-card bg-surface-2/50 text-text-secondary text-xs font-medium py-1.5 hover:bg-surface-3/60 transition-colors focus-ring-soft disabled:opacity-50"
        >
          {t('today.scheduleDismiss')}
        </button>
      </div>
    </div>
  );
}
