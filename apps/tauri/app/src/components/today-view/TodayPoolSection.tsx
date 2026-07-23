import type { MouseEvent as ReactMouseEvent } from 'react';

import type { TranslationKey } from '@/lib/i18n';
import type { Task } from '@/lib/ipc/tasks/models';
import { InteractiveTaskCard } from '../task-card/InteractiveTaskCard';
import { SectionHeader } from './primitives';

interface TodayPoolSectionProps {
  tasks: Task[];
  focusedTaskId: string | null;
  onSelectTask?: ((taskId: string) => void) | undefined;
  t: (key: TranslationKey) => string;
  selectionMode?: boolean | undefined;
  selectedIds?: Set<string> | undefined;
  bulkBusy?: boolean | undefined;
  onToggleSelected?: ((taskId: string) => void) | undefined;
  onClickWithModifiers?: ((id: string, event: ReactMouseEvent<HTMLButtonElement>) => void) | undefined;
}

export function TodayPoolSection({
  tasks,
  focusedTaskId,
  onSelectTask,
  t,
  selectionMode = false,
  selectedIds,
  bulkBusy = false,
  onToggleSelected,
  onClickWithModifiers,
}: TodayPoolSectionProps): React.JSX.Element {
  const hasSelection = (selectedIds?.size ?? 0) > 0;
  return (
    <section>
      <SectionHeader
        title={t('today.todayTasks')}
        subtitle={t('today.todayTasksHint')}
        count={tasks.length}
      />
      <div className="space-y-1.5">
        {tasks.map((task) => (
          <InteractiveTaskCard
            key={task.id}
            task={task}
            selectionMode={selectionMode}
            selected={selectedIds?.has(task.id) ?? false}
            bulkBusy={bulkBusy}
            focused={focusedTaskId === task.id}
            hasSelection={hasSelection}
            showListColor={false}
            onToggleSelected={onToggleSelected ?? (() => {})}
            onSelect={(id) => onSelectTask?.(id)}
            onClickWithModifiers={onClickWithModifiers}
          />
        ))}
      </div>
    </section>
  );
}
