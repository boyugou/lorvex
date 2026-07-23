import type { Task } from '@/lib/ipc/tasks/models';
import type { TranslationKey } from '@/lib/i18n';
import { formatNumber } from '@/locales';
import type { OverdueSeverityGroup } from '../useWeeklyReviewController';

const SEVERITY_CONFIG: Record<OverdueSeverityGroup['label'], {
  labelKey: TranslationKey;
  color: string;
  dotColor: string;
  bgColor: string;
}> = {
  month_plus: {
    labelKey: 'review.overdueMonth',
    color: 'text-danger',
    dotColor: 'bg-danger',
    bgColor: 'tonal-surface-danger-xs',
  },
  two_weeks: {
    labelKey: 'review.overdueTwoWeeks',
    color: 'text-warning',
    dotColor: 'bg-warning',
    bgColor: 'tonal-surface-warning-xs',
  },
  week: {
    labelKey: 'review.overdueWeek',
    color: 'text-accent',
    dotColor: 'bg-accent',
    bgColor: 'tonal-surface-accent-xs',
  },
};

interface OverdueSeveritySectionProps {
  groups: OverdueSeverityGroup[];
  totalOverdue: number;
  locale: string;
  onSelectTask: (taskId: string) => void;
  inlineActionByTaskId: Record<string, 'complete' | 'cancel' | undefined>;
  onComplete: (task: Task) => void;
  onCancel: (task: Task) => void;
  onReschedule: (task: Task) => void;
  t: (key: TranslationKey) => string;
}

export default function OverdueSeveritySection({
  groups,
  totalOverdue,
  locale,
  onSelectTask,
  inlineActionByTaskId,
  onComplete,
  onCancel,
  onReschedule,
  t,
}: OverdueSeveritySectionProps) {
  if (groups.length === 0 && totalOverdue === 0) return null;

  return (
    <div className="space-y-3">
      {groups.map((group) => {
        const config = SEVERITY_CONFIG[group.label];
        return (
          <div key={group.label} className={`rounded-r-card border overflow-hidden ${config.bgColor}`}>
            <div className="flex items-center gap-2 px-4 py-2.5 border-b border-inherit">
              <span className={`w-2 h-2 rounded-full shrink-0 ${config.dotColor}`} />
              <span className={`text-xs font-semibold ${config.color}`}>{t(config.labelKey)}</span>
              <span className="text-3xs text-text-muted tabular-nums">({formatNumber(locale, group.tasks.length)})</span>
            </div>
            <div className="divide-y divide-surface-3/30">
              {group.tasks.map((task) => {
                const busy = inlineActionByTaskId[task.id];
                return (
                  <div key={task.id} className="px-4 py-2.5">
                    <button
                      type="button"
                      onClick={() => onSelectTask(task.id)}
                      className="w-full text-start focus-ring-soft rounded-r-control"
                    >
                      <div className="flex items-center gap-2">
                        <span className="text-sm text-text-primary truncate flex-1">{task.title}</span>
                        {task.due_date && (
                          <span className={`text-2xs tabular-nums shrink-0 ${config.color}`}>
                            {task.due_date}
                          </span>
                        )}
                      </div>
                    </button>
                    <div className="mt-2 flex items-center gap-1.5">
                      <button
                        type="button"
                        onClick={() => onReschedule(task)}
                        disabled={!!busy}
                        className="text-2xs px-2 py-1 rounded-r-control bg-accent/10 text-accent hover:bg-accent/20 active:scale-[0.97] transition-[color,background-color,transform] disabled:opacity-50 disabled:cursor-not-allowed focus-ring-soft"
                      >
                        {t('review.reschedule')}
                      </button>
                      <button
                        type="button"
                        onClick={() => onComplete(task)}
                        disabled={!!busy}
                        className="text-2xs px-2 py-1 rounded-r-control chip-success chip-success-interactive active:scale-[0.97] transition-[color,background-color,transform] disabled:opacity-50 disabled:cursor-not-allowed focus-ring-soft"
                      >
                        {busy === 'complete' ? t('review.completing') : t('review.complete')}
                      </button>
                      <button
                        type="button"
                        onClick={() => onCancel(task)}
                        disabled={!!busy}
                        className="text-2xs px-2 py-1 rounded-r-control chip-danger chip-danger-interactive active:scale-[0.97] transition-[color,background-color,transform] disabled:opacity-50 disabled:cursor-not-allowed focus-ring-soft"
                      >
                        {busy === 'cancel' ? t('review.cancelling') : t('common.cancel')}
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        );
      })}
      {totalOverdue > groups.reduce((s, g) => s + g.tasks.length, 0) && (
        <p className="text-text-muted text-xs">
          + {formatNumber(locale, totalOverdue - groups.reduce((s, g) => s + g.tasks.length, 0))} {t('review.more')}
        </p>
      )}
    </div>
  );
}
