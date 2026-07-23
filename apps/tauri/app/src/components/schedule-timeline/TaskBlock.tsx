import { memo, useCallback } from 'react';
import { useI18n } from '@/lib/i18n';
import type { ScheduleBlock, Task } from '@/lib/ipc/tasks/models';
import { RevealButton, revealOpacityStyle } from '@/components/ui/RevealButton';
import { PRIORITY_ICONS, PRIORITY_LABEL_KEYS } from '../task-card/support';
import { minutesBetween } from './blocks';
import { TASK_STATUS } from '@lorvex/shared/types';

// ---------------------------------------------------------------------------
// Small action sub-components
// ---------------------------------------------------------------------------

function CheckCircle({
  completing,
  onClick,
  ariaLabel,
}: {
  completing: boolean;
  onClick: (e: React.MouseEvent) => void;
  ariaLabel: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={completing}
      aria-label={ariaLabel}
      className="w-6 h-6 shrink-0 flex items-center justify-center focus-ring-soft rounded-full disabled:cursor-default group/complete"
    >
      <span
        className={`flex w-[16px] h-[16px] rounded-full border-[1.5px] items-center justify-center transition-colors ${
          completing
            ? 'border-success/60 bg-[var(--success-tint-md)]'
            : 'border-text-muted/30 group-hover/complete:border-success/50 group-hover/complete:bg-[var(--success-tint-xs)]'
        }`}
      >
        {completing && (
          <svg width="8" height="8" viewBox="0 0 10 10" fill="none" className="text-success">
            <path d="M2 5.5L4 7.5L8 3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        )}
      </span>
    </button>
  );
}

function RemoveButton({ onClick, label }: { onClick: (e: React.MouseEvent) => void; label: string }) {
  return (
    <RevealButton
      onClick={onClick}
      style={revealOpacityStyle(0.6)}
      className="shrink-0 p-1.5 flex items-center justify-center"
      aria-label={label}
    >
      <svg width="14" height="14" viewBox="0 0 16 16" fill="none" aria-hidden="true">
        <path d="M4.5 4.5L11.5 11.5M11.5 4.5L4.5 11.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      </svg>
    </RevealButton>
  );
}

function MoveButtons({ canUp, canDown, onUp, onDown, upLabel, downLabel }: {
  canUp: boolean; canDown: boolean;
  onUp: (e: React.MouseEvent) => void; onDown: (e: React.MouseEvent) => void;
  upLabel: string; downLabel: string;
}) {
  // each arrow is a RevealButton (tone='subtle',
  // size='comfortable'); each button self-arms its reveal on `group:hover`,
  // so this wrapper carries no reveal state of its own.
  // `disabled:opacity-20` keeps the original disabled-arrow look.
  const baseClass = 'flex items-center justify-center disabled:opacity-20';
  return (
    <div className="flex flex-col gap-0 shrink-0">
      <RevealButton
        onClick={onUp}
        disabled={!canUp}
        tone="subtle"
        size="comfortable"
        style={revealOpacityStyle(0.6)}
        className={baseClass}
        aria-label={upLabel}
      >
        <svg width="12" height="12" viewBox="0 0 16 16" fill="none" aria-hidden="true">
          <path d="M4 10L8 6L12 10" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </RevealButton>
      <RevealButton
        onClick={onDown}
        disabled={!canDown}
        tone="subtle"
        size="comfortable"
        style={revealOpacityStyle(0.6)}
        className={baseClass}
        aria-label={downLabel}
      >
        <svg width="12" height="12" viewBox="0 0 16 16" fill="none" aria-hidden="true">
          <path d="M4 6L8 10L12 6" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </RevealButton>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main TaskBlock component
// ---------------------------------------------------------------------------

interface TaskBlockProps {
  block: ScheduleBlock;
  task: Task;
  taskId: string;
  isActive: boolean;
  completing: boolean;
  /** Stable reference: receives `taskId` so parents can pass a single callback per timeline render. */
  onComplete: (taskId: string, e: React.MouseEvent) => void;
  onSelect: (taskId: string) => void;
  onRemove?: ((taskId: string, e: React.MouseEvent) => void) | undefined;
  onMoveUp?: ((taskId: string, e: React.MouseEvent) => void) | undefined;
  onMoveDown?: ((taskId: string, e: React.MouseEvent) => void) | undefined;
  canMoveUp?: boolean;
  canMoveDown?: boolean;
}

export const TaskBlock = memo(function TaskBlock({
  block, task, taskId, isActive, completing, onComplete, onSelect,
  onRemove, onMoveUp, onMoveDown, canMoveUp, canMoveDown,
}: TaskBlockProps) {
  const { t } = useI18n();
  const duration = minutesBetween(block.start_time, block.end_time);
  const isCompleted = task.status === TASK_STATUS.completed;
  const showActions = !isCompleted && !completing;

  // Bind the taskId at the TaskBlock level so each parent in the
  // ScheduleTimelineContent map can pass a single stable callback
  // instead of allocating an arrow per child per render.
  const handleComplete = useCallback(
    (e: React.MouseEvent) => onComplete(taskId, e),
    [onComplete, taskId],
  );
  const handleSelect = useCallback(() => onSelect(taskId), [onSelect, taskId]);
  const handleRemove = useCallback(
    (e: React.MouseEvent) => onRemove?.(taskId, e),
    [onRemove, taskId],
  );
  const handleMoveUp = useCallback(
    (e: React.MouseEvent) => onMoveUp?.(taskId, e),
    [onMoveUp, taskId],
  );
  const handleMoveDown = useCallback(
    (e: React.MouseEvent) => onMoveDown?.(taskId, e),
    [onMoveDown, taskId],
  );

  return (
    <div
      className={`flex items-start gap-3 py-2.5 px-3 rounded-r-card transition-colors group ${
        isCompleted || completing ? 'opacity-50' : isActive ? 'bg-accent/5 ring-1 ring-accent/20' : 'hover:bg-surface-3'
      }`}
    >
      <span className="text-text-muted text-xs font-mono w-11 shrink-0 pt-0.5 text-end">
        {block.start_time}
      </span>

      <div className="w-6 shrink-0 flex items-center justify-center self-stretch">
        {isCompleted || completing ? (
          <div className="w-0.5 h-full rounded-full bg-[var(--success-tint-lg)]" />
        ) : (
          <CheckCircle completing={false} onClick={handleComplete} ariaLabel={t('task.complete')} />
        )}
      </div>

      <button
        type="button"
        onClick={handleSelect}
        className="flex-1 min-w-0 text-start focus-ring-soft rounded-r-control"
      >
        <span className={`text-sm leading-snug ${
          isCompleted || completing ? 'text-text-secondary line-through' : 'text-text-primary'
        }`}>
          {(isCompleted || completing) && <span className="text-success me-1">{'\u2713'}</span>}
          {task.priority && task.priority <= 3 && (
            <span className={`me-1 ${
              task.priority === 1 ? 'text-danger' : task.priority === 2 ? 'text-warning' : 'text-text-muted'
            }`} role="img" aria-label={t(PRIORITY_LABEL_KEYS[task.priority] ?? 'task.priorityP3')}>{PRIORITY_ICONS[task.priority]}</span>
          )}
          {task.title}
        </span>
      </button>

      <span className="text-text-muted text-xs shrink-0 tabular-nums pt-0.5">
        {duration}{t('common.min')}
      </span>

      {showActions && onMoveUp && onMoveDown && (
        <MoveButtons canUp={!!canMoveUp} canDown={!!canMoveDown} onUp={handleMoveUp} onDown={handleMoveDown} upLabel={t('schedule.moveUp')} downLabel={t('schedule.moveDown')} />
      )}

      {showActions && onRemove && (
        <RemoveButton onClick={handleRemove} label={t('schedule.removeFromSchedule')} />
      )}
    </div>
  );
});
