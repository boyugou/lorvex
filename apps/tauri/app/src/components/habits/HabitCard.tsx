import { useCallback, useMemo, useRef } from 'react';
import type { HabitWithStats } from '@/lib/ipc/habits';
import { useI18n } from '@/lib/i18n';
import { LONG_PRESS_IGNORE_ATTRIBUTE, useLongPress } from '@/lib/useLongPress';
import { Tooltip } from '../ui/Tooltip';
import { AskAssistantPill } from '../ui/AskAssistantPill';
import { CheckIcon } from '../ui/icons';

interface HabitCardProps {
  habit: HabitWithStats;
  dates84: string[];
  onAdjust: (habitId: string, delta: number) => void;
  onContextMenu: (event: React.MouseEvent, habit: HabitWithStats) => void;
}

export function HabitCard({ habit, dates84, onAdjust, onContextMenu }: HabitCardProps) {
  const { t, format } = useI18n();
  const rootRef = useRef<HTMLDivElement>(null);
  // Long-press on touch surfaces should open the same edit context
  // menu as right-click on desktop. Synthesize a MouseEvent-ish
  // payload from the long-press coordinates so the shared handler
  // can position the floating menu without caring about the input
  // modality. preventDefault is not needed (touch start already
  // suppressed scroll via the controller's movement threshold).
  const handleLongPress = useCallback(
    (x: number, y: number) => {
      const fakeEvent = {
        preventDefault: () => undefined,
        stopPropagation: () => undefined,
        clientX: x,
        clientY: y,
        currentTarget: rootRef.current,
      } as unknown as React.MouseEvent;
      onContextMenu(fakeEvent, habit);
    },
    [habit, onContextMenu],
  );
  const longPress = useLongPress(handleLongPress);
  const openMenuFromKebab = (event: React.MouseEvent) => {
    event.stopPropagation();
    onContextMenu(event, habit);
  };
  const completionSet = useMemo(
    () => new Set(habit.recent_completion_dates),
    [habit.recent_completion_dates],
  );
  const completedToday = habit.completions_today >= habit.target_count;
  const completionRate30 = Math.min(100, Math.round(habit.completion_rate_30d * 100));
  const freqLabel =
    habit.frequency_type === 'weekly'
      ? t('habits.frequencyWeekly')
      : habit.frequency_type === 'monthly'
        ? t('habits.frequencyMonthly')
        : habit.frequency_type === 'times_per_week'
          ? t('habits.frequencyTimesPerWeek')
          : t('habits.frequencyDaily');

  const accentColor = habit.color ?? null;
  const hasSupportMeta = Boolean(habit.cue);

  return (
    // onContextMenu is a side affordance (right-click to edit habit
    // metadata); the primary action lives on the inner mark-done
    // <button>. There is no general "click the card" contract that
    // would warrant a parent button or keyboard listener here — the
    // browser's own context-menu key (ContextMenu / Shift+F10) drives
    // this handler from the keyboard for free.
    // eslint-disable-next-line jsx-a11y/no-static-element-interactions
    <div
      ref={rootRef}
      className="group/habitcard relative bg-surface-2 border border-surface-3 rounded-r-card p-5 space-y-4"
      onContextMenu={(event) => onContextMenu(event, habit)}
      onTouchStart={longPress.onTouchStart}
      onTouchEnd={longPress.onTouchEnd}
      onTouchMove={longPress.onTouchMove}
    >
      {/* Kebab "More actions" affordance. Visible on hover on desktop,
          always visible on touch (the long-press path is also wired but
          the explicit button gives a discoverable kbd/mouse target). */}
      <button
        type="button"
        onClick={openMenuFromKebab}
        {...{ [LONG_PRESS_IGNORE_ATTRIBUTE]: '' }}
        aria-label={t('habits.moreActions')}
        title={t('habits.moreActions')}
        className="absolute top-2.5 end-2.5 z-[var(--z-sticky)] inline-flex items-center justify-center w-7 h-7 rounded-full text-text-muted hover:text-text-primary hover:bg-surface-3 transition-opacity opacity-0 group-hover/habitcard:opacity-100 focus-visible:opacity-100 focus-ring-soft md:opacity-0 md:group-hover/habitcard:opacity-100 max-md:opacity-100"
      >
        <svg
          aria-hidden="true"
          viewBox="0 0 16 16"
          width="14"
          height="14"
          fill="currentColor"
        >
          <circle cx="3" cy="8" r="1.4" />
          <circle cx="8" cy="8" r="1.4" />
          <circle cx="13" cy="8" r="1.4" />
        </svg>
      </button>
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-center gap-3 min-w-0">
          {habit.icon && (
            <span className="text-2xl shrink-0" aria-hidden="true">
              {habit.icon}
            </span>
          )}
          <div className="min-w-0">
            <div className="flex items-center gap-1.5 min-w-0">
              <Tooltip label={t('habits.aiManagedTooltip')}>
                <h2 className="text-sm font-semibold text-text-primary truncate">
                  {habit.name}
                </h2>
              </Tooltip>
            </div>
            <span className="inline-flex items-center mt-0.5 px-1.5 py-0.5 text-xs rounded-r-control bg-surface-3 text-text-muted font-medium">
              {freqLabel}
            </span>
            {hasSupportMeta && (
              <div className="mt-2 flex flex-wrap items-center gap-1.5">
                {habit.cue && (
                  <span className="inline-flex max-w-full items-center rounded-r-control bg-surface-3/60 px-2 py-1 text-2xs text-text-secondary">
                    <span className="truncate">{habit.cue}</span>
                  </span>
                )}
              </div>
            )}
          </div>
        </div>

        <div className="shrink-0 text-end">
          <div
            className="text-2xl font-bold tabular-nums"
            style={accentColor ? { color: accentColor } : undefined}
          >
            <span className={accentColor ? '' : 'text-accent'}>{habit.current_streak}</span>
          </div>
          <div className="text-xs text-text-muted leading-none mt-0.5">
            {t('habits.currentStreak')}
          </div>
        </div>
      </div>

      {/*
       * Heatmap intensity tiers + axis labels + month dividers.
       * Tier mapping: empty=surface-3, light=accent-tint-xs (0.12),
       * medium=accent-tint-sm (0.20), strong=accent-tint-md (0.32),
       * full=accent-tint-2xl (0.85). Tiers are derived from per-week
       * completion density so a higher streak day reads as "hotter."
       * A slim M/W/F day-of-week column anchors the y-axis; a 1px
       * left rule on the first cell of every month visually
       * separates calendar months without adding labels.
       */}
      <div className="flex items-stretch gap-1.5">
        <div className="flex flex-col gap-0.5 pe-1 text-3xs text-text-muted/60 tabular-nums leading-none select-none">
          {['M', '', 'W', '', 'F', '', ''].map((label, idx) => (
            <div key={idx} className="h-3 flex items-center" aria-hidden="true">{label}</div>
          ))}
        </div>
        <div
          className="flex gap-0.5"
          role="img"
          aria-label={`${habit.name} -- ${t('habits.heatmapAria')} -- ${format(
            'habits.heatmapAriaSummary',
            {
              completed: dates84.filter(
                (date): date is string => date != null && completionSet.has(date),
              ).length,
              total: dates84.filter((date) => date != null).length,
            },
          )}`}
        >
          {Array.from({ length: 12 }, (_, weekIdx) => {
            const weekDates = Array.from({ length: 7 }, (_, dayIdx) => dates84[weekIdx * 7 + dayIdx]);
            const weekHits = weekDates.filter((d) => d != null && completionSet.has(d)).length;
            // Month-boundary detection: a vertical hairline on the
            // first week whose Monday falls into a new calendar month.
            const firstDate = weekDates[0];
            const prevWeekFirst = weekIdx > 0 ? dates84[(weekIdx - 1) * 7] : null;
            const isMonthBoundary =
              firstDate != null
              && prevWeekFirst != null
              && firstDate.slice(0, 7) !== prevWeekFirst.slice(0, 7);
            return (
              <div
                key={weekIdx}
                className={`flex flex-col gap-0.5 ${isMonthBoundary ? 'ps-1 border-s border-surface-3/60' : ''}`}
              >
                {Array.from({ length: 7 }, (_, dayIdx) => {
                  const date = weekDates[dayIdx];
                  const filled = date != null && completionSet.has(date);
                  // Per-cell intensity: ramps with the surrounding
                  // week's density so a busy week is "hotter" than
                  // a one-off completion.
                  const tier = !filled
                    ? 0
                    : weekHits <= 1
                      ? 1
                      : weekHits <= 3
                        ? 2
                        : weekHits <= 5
                          ? 3
                          : 4;
                  // Tier 1's `--accent-tint-xs` fill sits perilously
                  // close to `--surface-3` on dark themes — the cell
                  // can read as empty. Layer an inset 1px stroke in
                  // `--accent-tint-md` on tier 1 so contrast comes
                  // from a defined edge rather than fill alone.
                  // Higher tiers have enough fill density to stand
                  // on their own.
                  const tierBg = filled && !accentColor
                    ? tier === 1
                      ? 'bg-[var(--accent-tint-xs)] shadow-[inset_0_0_0_1px_var(--accent-tint-md)]'
                      : tier === 2
                        ? 'bg-[var(--accent-tint-sm)]'
                        : tier === 3
                          ? 'bg-[var(--accent-tint-md)]'
                          : 'bg-[var(--accent-tint-2xl)]'
                    : filled
                      ? ''
                      : 'bg-surface-3';
                  return (
                    <div
                      key={dayIdx}
                      className={`w-3 h-3 rounded-r-control transition-colors ${tierBg}`}
                      style={filled && accentColor ? {
                        backgroundColor: accentColor,
                        opacity: tier === 1 ? 0.35 : tier === 2 ? 0.55 : tier === 3 ? 0.75 : 1,
                      } : undefined}
                      title={
                        date != null
                          ? format('habits.heatmapCellTooltip', {
                              date,
                              state: filled ? t('habits.cellDone') : t('habits.cellEmpty'),
                            })
                          : undefined
                      }
                      aria-hidden="true"
                    />
                  );
                })}
              </div>
            );
          })}
        </div>
      </div>

      <div className="grid grid-cols-3 gap-2 text-center">
        <div className="bg-surface-3/50 rounded-r-card py-2.5">
          <div className="text-base font-bold text-text-primary tabular-nums">
            {completionRate30}%
          </div>
          <div className="text-xs text-text-muted mt-0.5 leading-tight">
            {t('habits.last30Days')}
          </div>
        </div>
        <div className="bg-surface-3/50 rounded-r-card py-2.5">
          <div className="text-base font-bold text-text-primary tabular-nums">
            {habit.total_completions}
          </div>
          <div className="text-xs text-text-muted mt-0.5 leading-tight">
            {t('habits.totalCompletions')}
          </div>
        </div>
        <div className="bg-surface-3/50 rounded-r-card py-2.5">
          <div className="text-base font-bold text-text-primary tabular-nums">
            {habit.best_streak}
          </div>
          <div className="text-xs text-text-muted mt-0.5 leading-tight">
            {t('habits.bestStreak')}
          </div>
        </div>
      </div>

      <div className="flex justify-start">
        <AskAssistantPill prompt={t('aiManaged.promptHabit')} />
      </div>

      {habit.progress_kind === 'accumulative' ? (
        <AccumulatingHabitControls
          habit={habit}
          completedToday={completedToday}
          onAdjust={onAdjust}
        />
      ) : (
        <button
          type="button"
          onClick={() => onAdjust(habit.id, 0)}
          aria-pressed={completedToday}
          className={[
            'w-full py-2.5 text-sm font-medium rounded-r-card transition-colors border focus-ring-soft',
            completedToday
              ? 'chip-success chip-success-interactive border-success/30'
              : 'bg-surface-3/60 text-text-secondary border-surface-3 hover:bg-surface-3',
          ].join(' ')}
        >
          {completedToday ? (
            <>
              <CheckIcon className="w-3.5 h-3.5 inline-block align-text-bottom" /> {t('habits.completedToday')}
            </>
          ) : t('habits.markDone')}
        </button>
      )}
    </div>
  );
}

interface AccumulatingHabitControlsProps {
  habit: HabitWithStats;
  completedToday: boolean;
  onAdjust: (habitId: string, delta: number) => void;
}

function AccumulatingHabitControls({
  habit,
  completedToday,
  onAdjust,
}: AccumulatingHabitControlsProps) {
  const { t } = useI18n();
  const decrementDisabled = habit.completions_today <= 0;
  const incrementDisabled = habit.completions_today >= habit.target_count;
  const decrementHintId = `habit-${habit.id}-dec-hint`;
  const incrementHintId = `habit-${habit.id}-inc-hint`;

  return (
    <div className="flex items-center justify-between gap-3 rounded-r-card border border-surface-3 bg-surface-3/50 px-3 py-2.5">
      <button
        type="button"
        onClick={() => onAdjust(habit.id, -1)}
        disabled={decrementDisabled}
        aria-label={t('habits.decrement')}
        aria-describedby={decrementDisabled ? decrementHintId : undefined}
        title={decrementDisabled ? t('habits.decrementAtZero') : undefined}
        className="min-tap inline-flex items-center justify-center rounded-r-card border border-surface-3 text-text-secondary disabled:opacity-40 disabled:cursor-not-allowed focus-ring-soft"
      >
        -
      </button>
      {decrementDisabled && (
        <span id={decrementHintId} className="sr-only">
          {t('habits.decrementAtZero')}
        </span>
      )}
      <div className="text-center">
        <div className="text-sm font-semibold text-text-primary tabular-nums">
          {habit.completions_today}/{habit.target_count}
        </div>
        <div className="text-xs text-text-muted">
          {completedToday ? t('habits.completedToday') : t('habits.markDone')}
        </div>
      </div>
      <button
        type="button"
        onClick={() => onAdjust(habit.id, 1)}
        disabled={incrementDisabled}
        aria-label={t('habits.increment')}
        aria-describedby={incrementDisabled ? incrementHintId : undefined}
        title={incrementDisabled ? t('habits.incrementMaxReached') : undefined}
        className="min-tap inline-flex items-center justify-center rounded-r-card border border-accent/30 text-accent disabled:opacity-40 disabled:cursor-not-allowed focus-ring-soft"
      >
        +
      </button>
      {incrementDisabled && (
        <span id={incrementHintId} className="sr-only">
          {t('habits.incrementMaxReached')}
        </span>
      )}
    </div>
  );
}
