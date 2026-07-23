import type { CSSProperties } from 'react';

import type { TaskDetailControllerState } from '@/components/task-detail/support';
import { CheckIcon } from '@/components/ui/icons';
import { Tooltip } from '@/components/ui/Tooltip';
import { RevealButton, revealOpacityStyle } from '@/components/ui/RevealButton';
import { TaskDetailOverflowMenu } from './TaskDetailOverflowMenu';
import { TASK_STATUS } from '@lorvex/shared/types';

export function TaskDetailHeader({
  controller,
  copyTaskId,
  headerClass,
  headerStyle,
  isActionable,
  isComplete,
  isCompleting,
  statusLabel,
  task,
  taskId,
  t,
}: {
  controller: TaskDetailControllerState;
  copyTaskId: () => void;
  headerClass: string;
  headerStyle: CSSProperties | undefined;
  isActionable: boolean;
  isComplete: boolean;
  isCompleting: boolean;
  statusLabel: string;
  task: NonNullable<TaskDetailControllerState['task']>;
  taskId: string;
  t: TaskDetailControllerState['t'];
}) {
  return (
    <div className={headerClass} style={headerStyle}>
      <div className="group flex items-center gap-2.5">
        {isComplete ? (
          <Tooltip label={`${t('task.reopen')} (⌘↵)`}>
            <button
              type="button"
              onClick={() => { void controller.handleReopen(); }}
              className="w-6 h-6 rounded-full chip-success chip-success-interactive flex items-center justify-center focus-ring-soft"
              aria-label={`${t('task.reopen')} (⌘↵)`}
            >
              <CheckIcon className="w-3.5 h-3.5" />
            </button>
          </Tooltip>
        ) : (
          <Tooltip label={isCompleting ? t('common.saving') : `${t('task.complete')} (⌘↵)`}>
            <button
              type="button"
              onClick={() => { void controller.handleComplete(); }}
              disabled={isCompleting}
              className={`w-6 h-6 rounded-full border-[1.5px] flex items-center justify-center transition-[color,background-color,border-color,transform] duration-200 ${
                isCompleting
                  ? 'bg-success border-success text-on-accent scale-110'
                  : 'border-card hover:border-success/70 text-transparent hover:text-success/70 hover:scale-105'
              } disabled:opacity-60 disabled:cursor-not-allowed focus-ring-soft`}
              aria-label={isCompleting ? t('common.saving') : `${t('task.complete')} (⌘↵)`}
            >
              {isCompleting ? <CheckIcon className="w-3 h-3" /> : ''}
            </button>
          </Tooltip>
        )}
        {task.status !== TASK_STATUS.open && !isComplete && (
          <span className={`text-xs font-medium px-1.5 py-0.5 rounded-r-control ${
            task.status === TASK_STATUS.cancelled ? 'chip-danger' :
            'bg-accent/10 text-accent'
          }`}>{statusLabel}</span>
        )}
        <Tooltip label={t('task.copyId')}>
          <RevealButton
            onClick={copyTaskId}
            tone="accent"
            hitTarget={false}
            style={revealOpacityStyle(0.6)}
            className="text-xs font-mono px-1.5 py-0.5 hover:bg-surface-3/50"
            aria-label={t('task.copyId')}
          >
            {taskId.slice(0, 8)}
          </RevealButton>
        </Tooltip>
      </div>

      <div className="flex items-center gap-1">
        {controller.unsavedChanges && (
          <span className="text-3xs text-text-muted/70 italic me-1">
            {controller.savingTitle || controller.savingBody ? t('common.saving') : t('task.unsavedChanges')}
          </span>
        )}

        <TaskDetailOverflowMenu
          controller={controller}
          isActionable={isActionable}
          isComplete={isComplete}
          task={task}
          t={t}
        />

        <Tooltip label={`${t('common.close')} (Esc)`}>
          <button
            type="button"
            onClick={() => { void controller.handleClose(); }}
            aria-label={t('common.close')}
            className="text-text-muted/60 hover:text-text-primary hover:bg-surface-2/50 transition-colors duration-150 rounded-r-control focus-ring-soft w-7 h-7 flex items-center justify-center"
          >
            <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round">
              <path d="M2 2l8 8M10 2l-8 8" />
            </svg>
          </button>
        </Tooltip>
      </div>
    </div>
  );
}
