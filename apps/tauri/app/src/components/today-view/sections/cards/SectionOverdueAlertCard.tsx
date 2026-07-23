import { memo } from 'react';

import { useI18n } from '@/lib/i18n';
import { formatOverdueTaskCountLabel } from '@/lib/dates/i18nCountPhrases';
import { InteractiveTaskCard } from '@/components/task-card/InteractiveTaskCard';
import { CollapsibleSection } from '@/components/ui/CollapsibleSection';
import { TonalButton } from '@/components/ui/TonalButton';
import { useDashboardSectionActions } from '../useDashboardSectionActions';
import type { DashboardCardCommonProps, SectionOf } from './types';
import { TASK_STATUS } from '@lorvex/shared/types';

interface Props extends DashboardCardCommonProps {
  section: SectionOf<'overdue_alert'>;
}

/**
 * Overdue alert card — danger-tinted block listing overdue tasks
 * with a single-click "reschedule all to today" affordance.
 */
export const SectionOverdueAlertCard = memo(function SectionOverdueAlertCard({
  section,
  plan,
  overdueTasks,
  focusedTaskId,
  selectionMode,
  selectedIds,
  bulkBusy,
  onToggleSelected,
  onSelectTask,
  collapsed,
  toggle,
}: Props) {
  const { t, locale } = useI18n();
  const { handleRescheduleOverdueToToday, isReschedulingOverdue } = useDashboardSectionActions();
  if (overdueTasks.length === 0) return null;
  const focusTasks = (plan?.tasks ?? []).filter((task) => task.status === TASK_STATUS.open);
  const focusIds = new Set(focusTasks.map((task) => task.id));
  const source = overdueTasks.filter((task) => !focusIds.has(task.id));
  if (source.length === 0) return null;
  const items = source.slice(0, section.limit ?? 5);
  return (
    <section>
      <div className={`tonal-surface-danger-xs border rounded-r-card ${collapsed ? 'px-4 py-2.5' : 'px-4 py-3'}`}>
        <div className="flex items-center justify-between gap-3">
          <h2 className="m-0">
            <button
              type="button"
              className="text-danger text-sm font-medium cursor-pointer select-none flex items-center gap-1.5 bg-transparent border-none p-0"
              onClick={toggle}
              aria-expanded={!collapsed}
            >
              <span className={`text-xs transition-transform duration-150 ${collapsed ? '' : 'rotate-90'}`}>›</span>
              {formatOverdueTaskCountLabel(locale, source.length, t)}
            </button>
          </h2>
          <CollapsibleSection collapsed={collapsed}>
            <TonalButton
              tone="danger"
              size="lg"
              disabled={isReschedulingOverdue}
              onClick={() => { void handleRescheduleOverdueToToday(source); }}
              className="font-medium"
            >
              {isReschedulingOverdue ? t('common.saving') : t('today.rescheduleToToday')}
            </TonalButton>
          </CollapsibleSection>
        </div>
        <CollapsibleSection collapsed={collapsed}>
          <p className="text-text-muted text-xs mt-1.5">{t('today.overdueAdvice')}</p>
          {items.length > 0 && (
            <div className="space-y-1.5 mt-3">
              {items.map((task) => (
                <InteractiveTaskCard
                  key={task.id}
                  task={task}
                  selectionMode={selectionMode}
                  selected={selectedIds?.has(task.id) ?? false}
                  bulkBusy={bulkBusy}
                  focused={focusedTaskId === task.id}
                  showListColor={false}
                  onToggleSelected={onToggleSelected ?? (() => {})}
                  onSelect={(id) => onSelectTask?.(id)}
                />
              ))}
            </div>
          )}
        </CollapsibleSection>
      </div>
    </section>
  );
});
