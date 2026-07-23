import type { ReactNode } from 'react';

import { formatNumber } from '@/locales';
import type { DailyReviewController } from '../controller/useDailyReviewController';
import { StatGrid } from '@/components/ui/StatGrid';
import { TonalIconBubble } from '@/components/ui/TonalIconBubble';
import {
  BarrierIcon,
  CalendarDayIcon,
  CheckIcon,
  FlameIcon,
} from '@/components/ui/icons';

export function DaySummarySection({ c }: { c: DailyReviewController }) {
  const { daySummary } = c;

  return (
    <section className="bg-surface-2 rounded-r-card border border-card overflow-hidden">
      <div className="px-5 py-3.5 border-b border-card flex items-center gap-2">
        <CalendarDayIcon className="w-4 h-4 text-accent" />
        <h2 className="heading-section">{c.t('dailyReview.daySummary')}</h2>
      </div>

      <div className="px-5 py-4">
        <StatGrid density="wide">
          <StatSummaryCard
            icon={<CheckIcon className="w-4 h-4 text-success" />}
            value={daySummary.completedCount}
            label={c.t('dailyReview.tasksCompleted')}
            accent="success"
            locale={c.locale}
          />
          <StatSummaryCard
            icon={<BarrierIcon className="w-4 h-4 text-warning" />}
            value={daySummary.attentionCount}
            label={c.t('dailyReview.needsAttention')}
            accent="warning"
            locale={c.locale}
          />
          <StatSummaryCard
            icon={<FlameIcon className="w-4 h-4 text-accent" />}
            value={`${formatNumber(c.locale, daySummary.habitsCompleted)}/${formatNumber(c.locale, daySummary.habitsTotal)}`}
            label={c.t('dailyReview.habitsCompleted')}
            accent="accent"
            locale={c.locale}
          />
          <StatSummaryCard
            icon={<CalendarDayIcon className="w-4 h-4 text-text-muted" />}
            value={daySummary.eventCount}
            label={c.t('dailyReview.calendarEvents')}
            accent="muted"
            locale={c.locale}
          />
        </StatGrid>

        {daySummary.completedTasks.length > 0 && (
          <div className="mt-4 space-y-1">
            {daySummary.completedTasks.slice(0, 8).map(task => (
              <div key={task.id} className="flex items-center gap-2.5 px-3 py-1.5 rounded-r-card bg-[var(--success-tint-xs)]">
                <TonalIconBubble tone="success" size="xs" tint="md" className="shrink-0">
                  <CheckIcon className="w-2.5 h-2.5 text-success" />
                </TonalIconBubble>
                <span className="text-text-secondary text-xs truncate">{task.title}</span>
              </div>
            ))}
            {daySummary.completedTasks.length > 8 && (
              <p className="text-text-muted text-2xs px-3 py-1">
                +{formatNumber(c.locale, daySummary.completedTasks.length - 8)} {c.t('nav.more')}
              </p>
            )}
          </div>
        )}

        {daySummary.habits.length > 0 && (
          <div className="mt-4 flex flex-wrap gap-2">
            {daySummary.habits.map(habit => {
              const done = habit.completions_today >= habit.target_count;
              return (
                <span
                  key={habit.id}
                  className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs transition-colors ${
                    done
                      ? 'chip-success'
                      : 'bg-surface-3/40 text-text-muted'
                  }`}
                >
                  {habit.icon && <span className="text-sm">{habit.icon}</span>}
                  <span className={done ? 'line-through' : ''}>{habit.name}</span>
                  {done && <CheckIcon className="w-3 h-3" />}
                </span>
              );
            })}
          </div>
        )}
      </div>
    </section>
  );
}

function StatSummaryCard({
  icon,
  value,
  label,
  accent,
  locale,
}: {
  icon: ReactNode;
  value: string | number;
  label: string;
  accent: string;
  locale: string;
}) {
  const accentColors: Record<string, string> = {
    success: 'text-success',
    warning: 'text-warning',
    accent: 'text-accent',
    muted: 'text-text-primary',
  };

  return (
    <div className="bg-surface-1/60 border border-card rounded-r-card px-3 py-3 text-center">
      <div className="flex items-center justify-center mb-1.5">{icon}</div>
      <p className={`text-lg font-light tabular-nums ${accentColors[accent] ?? 'text-text-primary'}`}>
        {typeof value === 'number' ? formatNumber(locale, value) : value}
      </p>
      <p className="text-text-muted/70 text-3xs mt-0.5 font-medium leading-tight">{label}</p>
    </div>
  );
}
