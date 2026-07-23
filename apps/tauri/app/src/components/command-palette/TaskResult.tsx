import type { Task } from '@/lib/ipc/tasks/models';
import { formatDueDate } from '@/lib/format';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { useI18n, type TranslationKey } from '@/lib/i18n';
import { TASK_STATUS } from '@lorvex/shared/types';

const STATUS_DOT_CLASS: Record<Task['status'], string> = {
  open: 'bg-accent',
  completed: 'bg-success',
  cancelled: 'bg-danger',
  someday: 'bg-text-muted',
};

export default function TaskResult({ task }: { task: Task }) {
  const { t, locale } = useI18n();
  const dayContext = useConfiguredDayContext();
  const statusLabelKeys: Record<string, TranslationKey> = {
    open: 'task.status.open',
    completed: 'task.status.completed',
    cancelled: 'task.status.cancelled',
    someday: 'task.status.someday',
  };
  const statusLabel = t(statusLabelKeys[task.status] ?? 'task.status.open');
  const todayLabel = t('upcoming.today');
  const tomorrowLabel = t('upcoming.tomorrow');
  const yesterdayLabel = t('upcoming.yesterday');
  const dueDateStr = formatDueDate(task.due_date, { dayContext, locale, todayLabel, tomorrowLabel, yesterdayLabel });
  return (
    <>
      <span className={`w-2.5 h-2.5 rounded-full shrink-0 ring-2 ring-surface-1 ${STATUS_DOT_CLASS[task.status]}`} />
      <div className="flex-1 min-w-0">
        <p className="text-sm text-text-primary truncate font-medium">{task.title}</p>
        {(task.status !== TASK_STATUS.open || dueDateStr) && (
          <div className="flex gap-2 text-2xs text-text-muted/70 mt-0.5">
            {task.status !== TASK_STATUS.open && <span className="font-medium">{statusLabel}</span>}
            {dueDateStr && <span>{dueDateStr}</span>}
          </div>
        )}
      </div>
    </>
  );
}
