import { memo } from 'react';
import { useI18n } from '@/lib/i18n';
import type { Task } from '@/lib/ipc/tasks/models';
import TaskCard from '../task-card/TaskCard';

interface SelectableTaskCardProps {
  task: Task;
  selected: boolean;
  bulkBusy: boolean;
  completed?: boolean | undefined;
  onToggleSelected: (id: string) => void;
}

/**
 * Selection-mode task card. The card's primary row button owns the
 * checkbox semantics so keyboard and screen-reader users encounter one
 * coherent selection control, not a separate checkbox plus row toggle.
 *
 * This component is selection-only. For the combined selection-or-swipe
 * decision, use `InteractiveTaskCard` which delegates here in selection mode.
 */
export const SelectableTaskCard = memo(function SelectableTaskCard({
  task,
  selected,
  bulkBusy,
  completed,
  onToggleSelected,
}: SelectableTaskCardProps) {
  const { t } = useI18n();
  const selectionLabel = `${t('task.bulkSelect')}: ${task.title}`;
  return (
    <div className="flex items-stretch gap-2">
      <span
        aria-hidden="true"
        className={`mt-3 w-5 h-5 rounded-r-control border flex items-center justify-center text-xs transition-colors shrink-0 ${selected ? 'bg-accent text-on-accent border-accent' : 'border-surface-3 text-text-primary'}`}
      >
        {selected ? '\u2713' : ''}
      </span>
      <div className="flex-1">
        <TaskCard
          task={task}
          completed={completed}
          disableComplete
          hideQuickActions
          taskButtonRole="checkbox"
          taskButtonAriaChecked={selected}
          taskButtonAriaLabel={selectionLabel}
          taskButtonDisabled={bulkBusy}
          onClick={() => onToggleSelected(task.id)}
        />
      </div>
    </div>
  );
})
