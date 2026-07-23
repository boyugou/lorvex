import { useState } from 'react';
import TaskCard from '@/components/task-card/TaskCard';
import { SwipeableTaskCard } from '@/components/task-card/SwipeableTaskCard';
import { formatDurationCompact } from '@/components/today-view/primitives';
import type { CompletionDayGroup } from '../useWeeklyReviewController';
import type { TranslationKey } from '@/lib/i18n';
import { useI18n } from '@/lib/i18n';
import { formatReviewTaskCountLabel } from '@/lib/dates/i18nCountPhrases';

interface AccomplishmentsSectionProps {
  completionsByDay: CompletionDayGroup[];
  totalCount: number;
  onSelectTask: (taskId: string) => void;
  t: (key: TranslationKey) => string;
}

export default function AccomplishmentsSection({
  completionsByDay,
  totalCount,
  onSelectTask,
  t,
}: AccomplishmentsSectionProps) {
  const { locale, formatNumber } = useI18n();
  const [expandedDays, setExpandedDays] = useState<Set<string>>(() => {
    // Expand the most recent day by default
    const first = completionsByDay[0];
    if (first) return new Set([first.dateYmd]);
    return new Set();
  });

  const toggleDay = (dateYmd: string) => {
    setExpandedDays((prev) => {
      const next = new Set(prev);
      if (next.has(dateYmd)) {
        next.delete(dateYmd);
      } else {
        next.add(dateYmd);
      }
      return next;
    });
  };

  if (totalCount === 0) {
    return (
      <div className="bg-surface-2 border border-card rounded-r-card px-5 py-8 text-center">
        <p className="text-text-muted text-sm">{t('review.noCompletions')}</p>
        <p className="text-text-muted/60 text-xs mt-1">{t('review.noCompletionsHint')}</p>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {completionsByDay.map((group) => {
        const isExpanded = expandedDays.has(group.dateYmd);
        const progressMax = Math.max(...completionsByDay.map((g) => g.tasks.length));
        const progressPct = progressMax > 0 ? (group.tasks.length / progressMax) * 100 : 0;

        return (
          <div key={group.dateYmd} className="bg-surface-2 border border-card rounded-r-card overflow-hidden">
            <button
              type="button"
              onClick={() => toggleDay(group.dateYmd)}
              className="w-full flex items-center gap-3 px-4 py-3 hover:bg-surface-3/30 transition-colors text-start focus-ring-soft"
            >
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-medium text-text-primary">{group.dayLabel}</span>
                  <span className="text-xs text-text-muted tabular-nums">
                    {formatReviewTaskCountLabel(locale, group.tasks.length, t)}
                  </span>
                  {group.totalMinutes > 0 && (
                    <span className="text-xs text-text-muted/60 tabular-nums">
                      {formatDurationCompact(group.totalMinutes, t('common.hourShort'), t('common.min'), formatNumber)}
                    </span>
                  )}
                </div>
                {/* Mini progress bar */}
                <div className="mt-1.5 h-1 rounded-full bg-surface-3/60 overflow-hidden">
                  <div
                    className="progress-fill h-full rounded-full bg-[var(--success-tint-lg)] transition-transform duration-500"
                    style={{ transform: `scaleX(${progressPct / 100})` }}
                  />
                </div>
              </div>
              <svg
                width={16}
                height={16}
                viewBox="0 0 16 16"
                fill="none"
                xmlns="http://www.w3.org/2000/svg"
                aria-hidden="true"
                className={`text-text-muted shrink-0 transition-transform duration-200 ${isExpanded ? 'rotate-0' : '-rotate-90'}`}
              >
                <path d="M4 6l4 4 4-4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </button>
            {isExpanded && (
              // swap the Tailwind v3
              // `animate-in fade-in slide-in-from-top-1 duration-200`
              // utilities (silently inert under Tailwind v4 without the
              // `tailwindcss-animate` plugin we don't ship) for the
              // v4-native arbitrary `animate-[slide-in-up_…]` shorthand
              // that resolves against the `slide-in-up` keyframe in
              // index.css. The expansion now actually animates.
              <div className="px-2 pb-2 animate-[slide-in-up_0.2s_ease-out]">
                <div className="space-y-0.5">
                  {group.tasks.map((task) => (
                    <SwipeableTaskCard key={task.id} task={task}>
                      <TaskCard task={task} completed onClick={() => onSelectTask(task.id)} />
                    </SwipeableTaskCard>
                  ))}
                </div>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}
