import { useState } from 'react';

import { getUIStateBoolean, setUIState } from '@/lib/storage/uiState';
import type { TaskDetailControllerState } from '@/components/task-detail/support';
import { XIcon } from '@/components/ui/icons';
import { CollapsibleSection } from '@/components/ui/CollapsibleSection';
import { SectionLabel } from '@/components/task-detail/TaskDetailPrimitives';
import { TaskSecondaryMetaFields } from '@/components/task-detail/metadata-editor/TaskSecondaryMetaFields';
import { TaskDetailDebugInfo } from '../TaskDetailInfoSections';
import { TaskDetailEventLinks } from '../TaskDetailEventLinks';
import { TaskDetailRelations } from '../TaskDetailRelations';
import { TASK_STATUS } from '@lorvex/shared/types';

const MORE_STORAGE_KEY = 'taskDetail:moreExpanded';

export function TaskDetailMoreSection({
  actionBarController,
  controller,
  taskId,
  t,
}: {
  actionBarController: TaskDetailControllerState & { task: NonNullable<TaskDetailControllerState['task']> };
  controller: TaskDetailControllerState;
  taskId: string;
  t: TaskDetailControllerState['t'];
}) {
  const [expanded, setExpanded] = useState(() => getUIStateBoolean(MORE_STORAGE_KEY, false));

  const task = controller.task!;
  const hasDeps = !!task.depends_on || controller.blocksIds.length > 0;
  const hasSecondaryMeta = !!(
    task.estimated_minutes || task.recurrence
    || task.defer_count > 0
    || task.planned_date || task.due_time
  );
  const hasIndicator = hasDeps || hasSecondaryMeta;

  const toggle = () => {
    setExpanded((prev) => {
      const next = !prev;
      setUIState(MORE_STORAGE_KEY, next);
      return next;
    });
  };

  return (
    <div>
      <button
        type="button"
        onClick={toggle}
        aria-expanded={expanded}
        className="group flex items-center gap-2 w-full text-2xs text-text-muted/50 hover:text-text-muted transition-colors duration-150 py-2 px-1 -mx-1 rounded-r-control hover:bg-surface-2/40 focus-ring-soft"
      >
        <svg
          aria-hidden="true"
          className="w-3 h-3 transition-transform duration-200 opacity-40 group-hover:opacity-70"
          style={{ transform: expanded ? 'rotate(90deg)' : 'rotate(0deg)' }}
          viewBox="0 0 16 16"
          fill="currentColor"
        >
          <path d="M6 3.5l4.5 4.5L6 12.5" stroke="currentColor" strokeWidth="1.5" fill="none" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        <span className="font-medium tracking-wide uppercase">{expanded ? t('taskDetail.hideDetails') : t('taskDetail.showDetails')}</span>
        {!expanded && hasIndicator && (
          <span className="w-1.5 h-1.5 rounded-full bg-accent/40 shrink-0" />
        )}
      </button>

      <CollapsibleSection collapsed={!expanded}>
        <div className="space-y-4 pt-2">
          <section>
            <SectionLabel>{t('taskDetail.section.schedule')}</SectionLabel>
            <TaskSecondaryMetaFields
              task={task}
              locale={controller.locale}
              t={t}
              onSave={async (patch) => { await controller.saveMetaPatch(patch); }}
            />
          </section>

          <TaskDetailRelations controller={controller} />
          <TaskDetailEventLinks taskId={taskId} t={t} />

          <section>
            <SectionLabel>{t('taskDetail.section.tracking')}</SectionLabel>
            <div className="space-y-3">
              <TaskDetailDebugInfo controller={{ attribution: controller.attribution, t, task }} />
            </div>
          </section>

          {(task.status === TASK_STATUS.open || task.status === TASK_STATUS.someday) && task.recurrence && (
            <section>
              <SectionLabel>{t('taskDetail.section.actions')}</SectionLabel>
              <div className="flex gap-2 flex-wrap items-center">
                <button
                  type="button"
                  onClick={() => { void actionBarController.handleDelete(false); }}
                  disabled={actionBarController.actionPending}
                  className="inline-flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-r-control border border-card bg-surface-2/50 text-text-secondary hover:bg-surface-2 hover:border-accent/30 transition-colors active:scale-[0.97] focus-ring-soft disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <XIcon className="w-3.5 h-3.5" />
                  {t('task.cancelRecurringSkip')}
                </button>
                <button
                  type="button"
                  onClick={() => { void actionBarController.handleDelete(true); }}
                  disabled={actionBarController.actionPending}
                  className="inline-flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-r-control border border-danger/20 hover:border-danger/30 chip-danger-subtle chip-danger-interactive active:scale-[0.97] focus-ring-soft disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <XIcon className="w-3.5 h-3.5" />
                  {t('task.cancelRecurringSeries')}
                </button>
              </div>
            </section>
          )}
        </div>
      </CollapsibleSection>
    </div>
  );
}
