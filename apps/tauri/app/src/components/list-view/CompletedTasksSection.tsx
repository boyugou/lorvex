import { useEffect, useMemo, useState } from 'react';

import {
  parseHideCompletedOlderThanDays,
  partitionCompletedTasks,
} from '@/lib/hideCompletedOlderThan';
import { useI18n } from '@/lib/i18n';
import { PREF_HIDE_COMPLETED_OLDER_THAN_DAYS } from '@/lib/preferences/keys';
import { usePreference } from '@/lib/query/usePreference';
import TaskCard from '../task-card/TaskCard';

import { useListView } from './ListViewContext';

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function CompletedTasksSection(): React.JSX.Element | null {
  const { t, format } = useI18n();
  const { completedTasks } = useListView();
  const { value: cutoffDays } = usePreference(
    PREF_HIDE_COMPLETED_OLDER_THAN_DAYS,
    parseHideCompletedOlderThanDays,
  );
  const [showAll, setShowAll] = useState(false);

  // Reset the session expand toggle whenever the underlying data set
  // identity changes — otherwise navigating between lists would carry a
  // stale "show all" flag that surprises users.
  useEffect(() => {
    setShowAll(false);
  }, [completedTasks]);

  const { visible, hidden } = useMemo(
    () => partitionCompletedTasks(completedTasks, Date.now(), cutoffDays),
    [completedTasks, cutoffDays],
  );

  const rendered = showAll ? [...visible, ...hidden] : visible;

  if (rendered.length === 0 && hidden.length === 0) return null;

  return (
    <div className="mt-8">
      <p className="text-text-muted text-xs font-medium mb-3">
        {t('list.recentlyCompleted')}
      </p>
      <div className="space-y-1.5 opacity-70">
        {rendered.map(task => (
          <TaskCard key={task.id} task={task} completed hideListInfo />
        ))}
      </div>
      {hidden.length > 0 && !showAll && (
        <button
          type="button"
          onClick={() => setShowAll(true)}
          className="mt-3 text-xs text-text-muted hover:text-text-secondary transition-colors focus-ring-soft rounded-r-control px-2 py-1"
        >
          {format('listView.showAllHidden', { count: hidden.length })}
        </button>
      )}
    </div>
  );
}
