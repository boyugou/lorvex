import { useQuery } from '@tanstack/react-query';
import { hexWithAlpha } from '@/lib/colorUtils';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { getTodaysHabits } from '@/lib/ipc/habits';
import type { HabitSummary } from '@/lib/ipc/habits';
import { useI18n } from '@/lib/i18n';
import { formatNumber } from '@/locales';
import { DAY_SCOPED_QUERY_KEYS } from '@/lib/query/dayScopedQueryKeys';
import { useTodayHabitCompletionActions } from '@/components/habits/useHabitCompletionActions';
import { CollapsibleSection } from '@/components/ui/CollapsibleSection';
import { SectionHeader } from '../primitives';

interface TodayHabitsSectionProps {
  collapsed: boolean;
  onToggleCollapse: () => void;
}

export function TodayHabitsSection({ collapsed, onToggleCollapse }: TodayHabitsSectionProps) {
  const { locale, t } = useI18n();
  const { todayYmd } = useConfiguredDayContext();
  const { adjustHabit, isPendingForHabit } = useTodayHabitCompletionActions(t('common.error'));

  const { data: habits } = useQuery({
    queryKey: DAY_SCOPED_QUERY_KEYS.todaysHabits(todayYmd),
    queryFn: ({ signal }) => getTodaysHabits(signal),
  });

  if (!habits || habits.length === 0) return null;

  const completedCount = habits.filter((h) => h.completions_today >= h.target_count).length;

  return (
    <section>
      <SectionHeader
        title={`${t('today.habits')} · ${formatNumber(locale, completedCount)}/${formatNumber(locale, habits.length)}`}
        collapsed={collapsed}
        onToggleCollapse={onToggleCollapse}
      />
      <CollapsibleSection collapsed={collapsed}>
          <div className="space-y-1">
            {habits.map((habit) => (
              <HabitRow
                key={habit.id}
                habit={habit}
                onAdjust={adjustHabit}
                isPending={isPendingForHabit(habit.id)}
              />
            ))}
          </div>
      </CollapsibleSection>
    </section>
  );
}

// ── Individual habit row ────────────────────────────────────────────

interface HabitRowProps {
  habit: HabitSummary;
  onAdjust: (id: string, delta: number) => void;
  isPending: boolean;
}

const STREAK_THRESHOLD = 2;

function HabitRow({ habit, onAdjust, isPending }: HabitRowProps) {
  const { locale, t } = useI18n();
  const done = habit.completions_today >= habit.target_count;
  const hasCustomColor = !!habit.color;
  const accumulative = habit.progress_kind === 'accumulative';
  const metaLabel = habit.cue ?? '';
  const completionButtonLabel = accumulative
    ? `${t('habits.decrement')}: ${habit.name}`
    : `${done ? t('habits.completedToday') : t('habits.markDone')}: ${habit.name}`;
  const incrementButtonLabel = `${t('habits.increment')}: ${habit.name}`;

  return (
    <div
      className={`w-full flex items-center gap-3 px-3 py-2 rounded-r-control transition-colors text-start group
        ${done ? 'bg-[var(--success-tint-xs)]' : 'bg-surface-2'}
        disabled:opacity-60`}
    >
      {/* Completion circle */}
      <button
        type="button"
        onClick={() => onAdjust(habit.id, accumulative ? -1 : 0)}
        disabled={isPending || (accumulative && habit.completions_today <= 0)}
        aria-label={completionButtonLabel}
        title={accumulative && habit.completions_today <= 0 ? t('habits.decrementAtZero') : undefined}
        className={`shrink-0 w-5 h-5 rounded-full border-2 flex items-center justify-center transition-colors focus-ring-soft
          ${done ? 'border-success bg-success text-on-accent' : hasCustomColor ? '' : 'border-accent/40 group-hover:border-accent/60'}`}
        style={!done && hasCustomColor && habit.color ? { borderColor: hexWithAlpha(habit.color, '99') } : undefined}
      >
        {done && (
          <svg width="10" height="10" viewBox="0 0 10 10" fill="none" aria-hidden="true">
            <path d="M2 5L4.5 7.5L8 3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        )}
      </button>

      {/* Icon + Name */}
      <span className="flex items-center gap-1.5 min-w-0 flex-1">
        {habit.icon && <span className="text-sm shrink-0">{habit.icon}</span>}
        <span className="min-w-0 flex-1">
          <span
            className={`block text-sm truncate ${done ? 'text-text-muted line-through' : 'text-text-primary'}`}
          >
            {habit.name}
          </span>
          {metaLabel && (
            <span className="block truncate text-2xs text-text-muted">
              {metaLabel}
            </span>
          )}
        </span>
      </span>

      {accumulative && (
        <span className="shrink-0 text-xs text-text-muted tabular-nums">
          {formatNumber(locale, habit.completions_today)}/{formatNumber(locale, habit.target_count)}
        </span>
      )}

      {accumulative ? (
        <button
          type="button"
          onClick={() => onAdjust(habit.id, 1)}
          disabled={isPending || habit.completions_today >= habit.target_count}
          aria-label={incrementButtonLabel}
          title={habit.completions_today >= habit.target_count ? t('habits.incrementMaxReached') : undefined}
          className="shrink-0 px-2 py-1 rounded-r-control border border-accent/25 text-accent disabled:opacity-40 focus-ring-soft"
        >
          +
        </button>
      ) : habit.current_streak >= STREAK_THRESHOLD ? (
        <span className="shrink-0 text-xs text-warning flex items-center gap-0.5" aria-label={`${t('habits.currentStreak')}: ${formatNumber(locale, habit.current_streak)}`}>
          🔥 {formatNumber(locale, habit.current_streak)}
        </span>
      ) : null}
    </div>
  );
}
