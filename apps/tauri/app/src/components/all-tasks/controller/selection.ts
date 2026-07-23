import { useState } from 'react';

import { useI18n } from '@/lib/i18n';
import { useTaskSelection } from '@/lib/tasks/useTaskSelection';

import type { BulkAction } from '../types';

/**
 * AllTasks-specific selection state.
 *
 * Wraps the generic `useTaskSelection` hook and layers on the
 * "bulk-move target list" preference that only this view needs. All
 * multi-select behaviour (plain / ctrl+click / shift+click / shift+arrow
 * / cmd+a / esc) lives in the shared hook so every task list — ListView,
 * AllTasksView, UpcomingView, SomedayView, TodayView — picks it up for
 * free.
 */
export function useAllTasksSelection(visibleTaskIds: Set<string>, bulkAction: BulkAction) {
  // feed the silent-collapse warning strings through the
  // shared hook so every list view picks up the affordance for free.
  const { t, format } = useI18n();
  const base = useTaskSelection(visibleTaskIds, bulkAction, {
    onSelectionCollapsedMessage: (count) =>
      format('allTasks.selectionCollapsed', { count: String(count) }),
    onSelectionCollapsedUndoLabel: () => t('allTasks.selectionCollapsedRestore'),
  });
  const [targetListId, setTargetListId] = useState<string | null>(null);

  const setSelectionModeEnabled = (enabled: boolean) => {
    base.setSelectionModeEnabled(enabled);
    if (!enabled) setTargetListId(null);
  };

  return {
    ...base,
    setSelectionModeEnabled,
    setTargetListId,
    targetListId,
  };
}
