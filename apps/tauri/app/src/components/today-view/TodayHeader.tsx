import { useCallback, useMemo } from 'react';
import type { TranslationKey } from '@/lib/i18n';
import { useI18n } from '@/lib/i18n';
import { formatNumber } from '@/locales';
import {
  formatOverdueTaskCountLabel,
  formatTodayTaskCountLabel,
} from '@/lib/dates/i18nCountPhrases';
import { useCopyToClipboard } from '@/lib/platform/useCopyToClipboard';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { CurrentFocusWithTasks, Overview, Task } from '@/lib/ipc/tasks/models';
import { Button } from '../ui/Button';
import { Pill } from '../ui/Pill';
import { Tooltip } from '../ui/Tooltip';
import { TASK_STATUS } from '@lorvex/shared/types';

interface TodayHeaderProps {
  greeting: string;
  today: string;
  isAiLayout: boolean;
  stats: Overview['stats'] | undefined;
  todayPoolTasks: Task[];
  overdueTasks: Task[];
  plan: CurrentFocusWithTasks | null | undefined;
  todayEvents: UnifiedCalendarEvent[];
  t: (key: TranslationKey) => string;
  hasSelectableTasks?: boolean | undefined;
  selectionMode?: boolean | undefined;
  bulkBusy?: boolean | undefined;
  onToggleSelectionMode?: (() => void) | undefined;
  /// Opens the task detail panel for the "Up next" task. When
  /// provided, the title in the eyebrow becomes a button. Wired
  /// through TodayViewContent's `onSelectTask`.
  onSelectTask?: ((taskId: string) => void) | undefined;
}

export function TodayHeader({
  greeting,
  today,
  isAiLayout,
  stats,
  todayPoolTasks,
  overdueTasks,
  plan,
  todayEvents,
  t,
  hasSelectableTasks = false,
  selectionMode = false,
  bulkBusy = false,
  onToggleSelectionMode,
  onSelectTask,
}: TodayHeaderProps): React.JSX.Element {
  const { copy, copying } = useCopyToClipboard();
  const { locale } = useI18n();

  // Materialize the focus-plan open-task list once per `plan` change instead
  // of re-walking `task_ids` + scanning `tasks` each time the copy handler
  // fires.
  const openFocusTasks = useMemo<Task[]>(() => {
    if (!plan || plan.tasks.length === 0) return [];
    return plan.task_ids
      .map((id) => plan.tasks.find((tk) => tk.id === id))
      .filter((tk): tk is Task => !!tk && tk.status === TASK_STATUS.open);
  }, [plan]);

  const handleCopyPlan = useCallback(async () => {
    if (copying) return;
    const lines: string[] = [`${today}\n`];
    if (todayPoolTasks.length > 0) {
      lines.push(`${t('today.todayTasks')}:`);
      for (const task of todayPoolTasks) {
        const dur = task.estimated_minutes ? ` (${task.estimated_minutes}${t('common.min')})` : '';
        lines.push(`  - [ ] ${task.title}${dur}`);
      }
      lines.push('');
    }
    if (plan && plan.tasks.length > 0) {
      if (openFocusTasks.length > 0) {
        lines.push(`${t('today.focus')}:`);
        for (const task of openFocusTasks) {
          const dur = task.estimated_minutes ? ` (${task.estimated_minutes}${t('common.min')})` : '';
          lines.push(`  - [ ] ${task.title}${dur}`);
        }
        lines.push('');
      }
    }
    if (todayEvents.length > 0) {
      lines.push(`${t('calendar.events')}:`);
      for (const event of todayEvents) {
        const time = event.all_day ? t('calendar.eventAllDay') : event.start_time ?? '';
        lines.push(`  ${time} ${event.title}`);
      }
      lines.push('');
    }
    await copy(lines.join('\n').trimEnd(), t('today.planCopied'));
  }, [copy, copying, todayPoolTasks, plan, openFocusTasks, t, today, todayEvents]);

  const showCopyButton = todayPoolTasks.length > 0 || (plan != null && plan.tasks.length > 0);

  // "Up next" eyebrow surfaces the single next-thing-to-do — the
  // first open focus-plan task if a focus plan exists, else the
  // top of the today pool. Keeps the header useful for a glance
  // without scrolling: even when the user has 12 things today they
  // immediately see the one the rest of the view is sorted around.
  const upNextTask: Task | null = openFocusTasks[0] ?? todayPoolTasks[0] ?? null;

  // Tablet-portrait widths (768-1024px) are now common. The
  // legacy flat `px-8` (32px) horizontally cropped pill rows and
  // truncated long titles on those widths. Stepping down to `px-4`
  // below `md` gives the same content ~32px more usable width on
  // portrait tablets while keeping the desktop visual rhythm at and
  // above the `md` breakpoint. Mirrored across AllTasks / Eisenhower /
  // Upcoming view headers so the entry-point bar reads as a single
  // family.
  // Heading column uses `items-start` and the chip cluster uses
  // `items-center` so the heading sits flush to its own block while
  // the right-side chips (AI Layout pill, Copy plan, Select) align to
  // the visual center of the heading rather than its baseline — the
  // optical descent of the chips no longer drags the row down. The
  // greeting eyebrow uses `mb-1` for the same reason.
  return (
    <header className="px-4 sm:px-8 pt-1.5 pb-5 shrink-0">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-text-muted/80 text-2xs font-semibold tracking-widest uppercase mb-1">{greeting}</p>
          <h2 className="text-text-primary text-2xl font-light leading-tight">{today}</h2>
          {upNextTask && (
            <div className="mt-1.5 flex items-center gap-2 max-w-[32rem]">
              <span className="text-text-muted/70 text-xs shrink-0">{t('today.upNext')}:</span>
              {onSelectTask ? (
                <button
                  type="button"
                  onClick={() => onSelectTask(upNextTask.id)}
                  className="min-w-0 truncate text-xs text-text-secondary hover:text-text-primary hover:underline transition-colors focus-ring-soft rounded-r-control"
                  aria-label={t('today.upNextOpenAria')}
                >
                  {upNextTask.title}
                </button>
              ) : (
                <span className="min-w-0 truncate text-xs text-text-secondary">{upNextTask.title}</span>
              )}
            </div>
          )}
        </div>
        <div className="flex items-center gap-3 pt-4 shrink-0">
          {isAiLayout && (
            <span className="text-text-muted text-xs">
              ✦ {t('today.aiLayout')}
            </span>
          )}
          {showCopyButton && (
            <Tooltip label={t('today.copyPlan')}>
              <button
                type="button"
                onClick={() => { void handleCopyPlan(); }}
                disabled={copying}
                className="text-text-muted text-xs px-2.5 py-1.5 rounded-r-control hover:text-text-secondary hover:bg-surface-2 transition-colors disabled:opacity-50 focus-ring-soft"
              >
                {copying ? t('common.copying') : t('today.copyPlan')}
              </button>
            </Tooltip>
          )}
          {hasSelectableTasks && onToggleSelectionMode && (
            <Button
              variant="outline"
              onClick={onToggleSelectionMode}
              disabled={bulkBusy}
            >
              {selectionMode ? t('common.done') : t('allTasks.select')}
            </Button>
          )}
        </div>
      </div>

      {(overdueTasks.length > 0 || todayPoolTasks.length > 0) && (
        <div className="flex flex-wrap items-center gap-2 mt-2.5">
          {overdueTasks.length > 0 && (
            <Pill tone="danger" size="cozy" tabular className="tracking-wide">
              {formatOverdueTaskCountLabel(locale, overdueTasks.length, t)}
            </Pill>
          )}
          {todayPoolTasks.length > 0 && (
            <Pill tone="warning" size="cozy" tabular className="tracking-wide">
              {formatTodayTaskCountLabel(locale, todayPoolTasks.length, t)}
            </Pill>
          )}
        </div>
      )}

      <DayProgressBar stats={stats} />
    </header>
  );
}

function DayProgressBar({ stats }: { stats: Overview['stats'] | undefined }): React.JSX.Element | null {
  const { locale } = useI18n();
  if (!stats) return null;
  const total = stats.today_pool_count + stats.completed_today;
  if (total <= 0) return null;
  const pct = Math.round((stats.completed_today / total) * 100);
  const allDone = stats.today_pool_count === 0 && stats.completed_today > 0;

  return (
    <div className="mt-3.5 flex items-center gap-3">
      <div className="flex-1 h-1.5 rounded-full bg-surface-3/60 overflow-hidden">
        {/*
          The width transition is tightened to 300ms.
          The bar sits at the top of TodayView and is updated whenever
          a task flips state — the longer 700ms ease meant the bar was
          still creeping toward its target percentage well after the
          rest of the row had repainted (checkbox state, count pill).
          300ms matches the rest of the view's micro-interactions and
          lands the bar's final width inside the same animation
          envelope as the row that triggered the change.
        */}
        <div
          className={`progress-fill h-full rounded-full transition-[transform,background-color,box-shadow] duration-300 ease-out ${
            allDone ? 'bg-success shadow-[var(--shadow-glow-success)]' : 'bg-[var(--success-tint-lg)]'
          }`}
          style={{ transform: `scaleX(${pct / 100})` }}
        />
      </div>
      <span className={`text-2xs tabular-nums shrink-0 font-medium ${
        allDone ? 'text-success' : 'text-text-muted'
      }`}>
        {formatNumber(locale, stats.completed_today)}/{formatNumber(locale, total)}
      </span>
    </div>
  );
}
