import type { MouseEvent as ReactMouseEvent } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import type { TranslationKey } from '@/lib/i18n';
import { formatNumber } from '../../../locales';
import { formatDurationCompact } from '../../today-view/primitives';
import { CollapsibleSection } from '../../ui/CollapsibleSection';
import { ChevronDownIcon, WarningIcon } from '../../ui/icons';
import { UpcomingTaskRow } from '../UpcomingTaskRow';

/**
 * The overdue section at the top of the Upcoming list view. Renders
 * danger-tinted header (count + total estimated minutes) plus the
 * collapsible task list. Always rendered when `tasks.length > 0`; the
 * orchestrator gates visibility before invoking this component.
 */
export function Overdue({
  tasks,
  totalMinutes,
  collapsed,
  onToggleCollapse,
  selectionMode,
  selectedIds,
  bulkBusy,
  focusedId,
  hasSelection,
  onToggleSelected,
  onSelectTask,
  onClickWithModifiers,
  onRescheduleTask,
  onDragEnd,
  locale,
  t,
}: {
  tasks: Task[];
  totalMinutes: number;
  collapsed: boolean;
  onToggleCollapse: () => void;
  selectionMode: boolean;
  selectedIds: Set<string>;
  bulkBusy: boolean;
  focusedId: string | null;
  hasSelection: boolean;
  onToggleSelected: (taskId: string) => void;
  onSelectTask?: ((taskId: string) => void) | undefined;
  onClickWithModifiers: (id: string, event: ReactMouseEvent<HTMLButtonElement>) => void;
  onRescheduleTask: (taskId: string, newDate: string) => void;
  onDragEnd: () => void;
  locale: string;
  t: (key: TranslationKey) => string;
}) {
  return (
    <section className="rounded-r-card bg-[var(--danger-tint-xs)] px-4 py-3 -mx-4">
      <h2 className="mb-3">
        <button
          type="button"
          className="flex items-baseline gap-2 select-none focus-ring-soft rounded-r-control text-start hover:opacity-80 transition-opacity"
          onClick={onToggleCollapse}
          aria-expanded={!collapsed}
        >
          {/* Chevron is decorative; state lives in `aria-expanded`
              on the parent button. */}
          <ChevronDownIcon aria-hidden="true" className={`w-3 h-3 text-danger transition-transform duration-150 ${collapsed ? '-rotate-90' : ''}`} />
          <span className="text-danger text-xs font-medium inline-flex items-center gap-1"><WarningIcon className="w-3 h-3" /> {t('upcoming.overdueSection')}</span>
          <span className="chip-tight chip-danger text-2xs tabular-nums font-medium">{formatNumber(locale, tasks.length)}</span>
          {totalMinutes > 0 && (
            <span className="text-danger/70 text-xs">
              · {formatDurationCompact(totalMinutes, t('common.hourShort'), t('common.min'), (value) => formatNumber(locale, value))}
            </span>
          )}
        </button>
      </h2>
      <CollapsibleSection collapsed={collapsed}>
          <div className="space-y-1.5">
            {tasks.map((task) => (
              <UpcomingTaskRow
                key={task.id}
                task={task}
                selectionMode={selectionMode}
                selected={selectedIds.has(task.id)}
                bulkBusy={bulkBusy}
                focused={focusedId === task.id}
                hasSelection={hasSelection}
                onToggleSelected={onToggleSelected}
                onSelect={onSelectTask}
                onClickWithModifiers={onClickWithModifiers}
                onRescheduleTask={onRescheduleTask}
                onDragEnd={onDragEnd}
              />
            ))}
          </div>
      </CollapsibleSection>
    </section>
  );
}

