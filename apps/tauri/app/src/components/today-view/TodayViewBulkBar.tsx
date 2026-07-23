import { memo } from 'react';

import { BulkActionBar } from '../ui/BulkActionBar';
import type { BulkAction } from '@/lib/tasks/useTaskSelection';

interface Props {
  selectedCount: number;
  bulkAction: BulkAction;
  onSelectAll: () => void;
  onInvertSelection?: () => void;
  onClearSelection: () => void;
  onComplete: () => void;
  onDefer: () => void;
  onCancel: () => void;
  onMove: (listId: string | null) => void;
  onFocus: () => void;
}

/**
 * Selection-mode bar above the Today body. Lifted out of
 * `TodayViewContent` so the (much) more frequent overview/plan/event
 * data ticks don't re-render the bar at all when selection mode is
 * inactive.
 */
function TodayViewBulkBarImpl({
  selectedCount,
  bulkAction,
  onSelectAll,
  onInvertSelection,
  onClearSelection,
  onComplete,
  onDefer,
  onCancel,
  onMove,
  onFocus,
}: Props) {
  return (
    <div className="px-4 sm:px-8 pb-2 shrink-0">
      <BulkActionBar
        selectedCount={selectedCount}
        bulkAction={bulkAction}
        onSelectAll={onSelectAll}
        onInvertSelection={onInvertSelection}
        onClearSelection={onClearSelection}
        onComplete={onComplete}
        onDefer={onDefer}
        onCancel={onCancel}
        onMove={onMove}
        onFocus={onFocus}
        showFocus
      />
    </div>
  );
}

export const TodayViewBulkBar = memo(TodayViewBulkBarImpl);
