import type { TranslationKey } from '@/lib/i18n';
import { formatNumber } from '../../locales';
import { formatTaskCountLabel } from '../../lib/dates/i18nCountPhrases';
import { AddTaskHeaderButton } from '../task-list-view/AddTaskHeaderButton';

/**
 * Header strip for `AllTasksView`: title, filtered/total count, and
 * the "+ Add task" button. Extracted from the shell so the orchestrator
 * doesn't carry per-render JSX for what's effectively a banner.
 */
export function Header({
  locale,
  t,
  tasksLen,
  totalCount,
  hasActiveFilter,
  onAddTask,
}: {
  locale: string;
  t: (key: TranslationKey) => string;
  tasksLen: number;
  totalCount: number;
  hasActiveFilter: boolean;
  onAddTask?: (() => void) | undefined;
}) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <div>
        <h2 className="text-text-primary text-2xl font-light">{t('allTasks.title')}</h2>
        <p className="text-text-muted text-xs mt-2">
          {hasActiveFilter
            ? `${formatNumber(locale, tasksLen)} / ${formatTaskCountLabel(locale, totalCount, t)}`
            : formatTaskCountLabel(locale, tasksLen, t)}
        </p>
      </div>
      {onAddTask && (
        <AddTaskHeaderButton
          labelKey="allTasks.addTask"
          tooltipKey="allTasks.addTaskTooltip"
          onClick={onAddTask}
        />
      )}
    </div>
  );
}
