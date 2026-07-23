import { useConfiguredDayContext } from '@/lib/dayContext';
import type { Task } from '@/lib/ipc/tasks/models';
import { formatDueDate } from '@/lib/format';
import { formatNumber } from '@/locales';
import { type DeferredInterventionAction } from '../useWeeklyReviewController';
import { Button } from '@/components/ui/Button';
import { TonalButton } from '@/components/ui/TonalButton';

interface DeferredTaskRowProps {
  task: Task;
  locale: string;
  todayLabel: string;
  tomorrowLabel: string;
  yesterdayLabel: string;
  onOpenDetail: () => void;
  busyAction: DeferredInterventionAction | null;
  scheduleLabel: string;
  scheduleBusyLabel: string;
  rescopeLabel: string;
  rescopeBusyLabel: string;
  archiveLabel: string;
  archiveBusyLabel: string;
  onScheduleTomorrow: () => void;
  onRescope: () => void;
  onArchive: () => void;
}

export default function DeferredTaskRow({
  task,
  locale,
  todayLabel,
  tomorrowLabel,
  yesterdayLabel,
  onOpenDetail,
  busyAction,
  scheduleLabel,
  scheduleBusyLabel,
  rescopeLabel,
  rescopeBusyLabel,
  archiveLabel,
  archiveBusyLabel,
  onScheduleTomorrow,
  onRescope,
  onArchive,
}: DeferredTaskRowProps) {
  const dayContext = useConfiguredDayContext();
  const dueDateStr = formatDueDate(task.due_date, { dayContext, locale, todayLabel, tomorrowLabel, yesterdayLabel });
  const isBusy = busyAction !== null;

  return (
    <div className="px-4 py-3 bg-surface-2 border border-card rounded-r-card">
      <button
        type="button"
        onClick={onOpenDetail}
        className="w-full flex items-center gap-3 hover:bg-surface-3/50 rounded-r-control px-2 py-1.5 cursor-pointer transition-colors text-start focus-ring-soft"
        aria-label={task.title}
      >
        <span className="text-xs chip-warning font-medium px-1.5 py-0.5 rounded-r-control tabular-nums shrink-0">↻{formatNumber(locale, task.defer_count)}</span>
        <div className="flex-1 min-w-0">
          <span className="text-sm text-text-primary truncate">{task.title}</span>
        </div>
        {dueDateStr && <span className="text-xs text-text-muted shrink-0">{dueDateStr}</span>}
      </button>

      <div className="mt-2.5 flex items-center gap-2 ps-6">
        <button
          type="button"
          onClick={onScheduleTomorrow}
          disabled={isBusy}
          className="text-xs px-2.5 py-1.5 rounded-r-control bg-accent text-on-accent active:scale-[0.97] hover:bg-accent/90 transition-[color,background-color,transform] disabled:opacity-50 disabled:cursor-not-allowed focus-ring-strong"
        >
          {busyAction === 'schedule_tomorrow' ? scheduleBusyLabel : scheduleLabel}
        </button>
        <Button
          variant="outline"
          onClick={onRescope}
          disabled={isBusy}
          className="active:scale-[0.97]"
        >
          {busyAction === 'retriage' ? rescopeBusyLabel : rescopeLabel}
        </Button>
        <TonalButton
          tone="danger"
          onClick={onArchive}
          loading={busyAction === 'archive'}
          disabled={isBusy && busyAction !== 'archive'}
          className="active:scale-[0.97]"
        >
          {busyAction === 'archive' ? archiveBusyLabel : archiveLabel}
        </TonalButton>
      </div>
    </div>
  );
}
