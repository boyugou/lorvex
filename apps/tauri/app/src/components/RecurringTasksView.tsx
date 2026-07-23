/**
 * Recurring Tasks index.
 *
 * Read-only power-user dashboard that lists every task with an active
 * recurrence rule (`recurrence IS NOT NULL AND archived_at IS NULL`).
 * Gives a user with many recurring rules a single place to answer
 * "which tasks recur, and are any dormant or misconfigured?" without
 * having to open each task detail one at a time.
 *
 * Editing lives in `task-detail/metadata-editor/RecurrenceField.tsx`;
 * clicking a card here opens the detail panel so the existing edit
 * surface stays the single source of truth. This keeps the view scope
 * honestly read-only (CLAUDE rule 1: the MCP server owns writes).
 */
import { memo, useCallback, useMemo, useRef } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useVirtualizer } from '@tanstack/react-virtual';

import { useI18n, type TranslationKey } from '../lib/i18n';
import { formatPageTitle } from '../lib/pageTitle';
import type { QuickCaptureInitialData } from '../app-shell/main-window/types';
import { getRecurringTasks } from '@/lib/ipc/tasks/queries';
import type { Task } from '@/lib/ipc/tasks/models';
import { QUERY_KEYS } from '../lib/query/queryKeys';
import { REFETCH_INTERVAL, STALE_DEFAULT } from '../lib/query/timing';
import { useScrollRestore } from '../lib/useScrollRestore';
import { parseRecurrence } from './task-detail/metadata-editor/shared';
import ModuleStatePanel from './ui/ModuleStatePanel';
import { RecurringTasksViewSkeleton } from './RecurringTasksViewSkeleton';
import { RecurrenceIcon, WarningIcon } from './ui/icons';
import { StaleDataBanner } from './ui/StaleDataBanner';
import TaskCard from './task-card/TaskCard';
import {
  LIST_VIEW_OVERSCAN,
  LIST_VIEW_ROW_ESTIMATE_PX,
  shouldVirtualizeListView,
} from './list-view/virtualization';

interface Props {
  onSelectTask?: ((taskId: string) => void) | undefined;
  /**
   * Opens QuickCapture, optionally pre-populated. Used by the empty-state
   * template CTAs ("Weekly review Fridays", "Pay rent on 1st", "Pick up
   * groceries Sundays") so a user with zero recurring rules can land
   * in the capture form already pre-filled with a sensible cadence
   * example. Editing the recurrence itself still happens in
   * task-detail's RecurrenceField after capture — the CTA is a
   * scaffold, not a one-tap commit.
   */
  onOpenQuickCapture?: ((data?: QuickCaptureInitialData) => void) | undefined;
}

/**
 * Empty-state templates surfaced as CTAs when a user has zero
 * recurring tasks. The label is rendered through i18n; the
 * `title` we pre-fill into QuickCapture is the user-facing
 * cadence-encoded phrase so the captured task is already
 * meaningful even before the user opens the detail panel to set
 * the actual RRULE.
 */
const RECURRING_TEMPLATES: ReadonlyArray<{
  key: 'weeklyReview' | 'payRent' | 'groceries';
  labelKey: TranslationKey;
  titleKey: TranslationKey;
}> = [
  { key: 'weeklyReview', labelKey: 'recurring.template.weeklyReview', titleKey: 'recurring.template.weeklyReview' },
  { key: 'payRent', labelKey: 'recurring.template.payRent', titleKey: 'recurring.template.payRent' },
  { key: 'groceries', labelKey: 'recurring.template.groceries', titleKey: 'recurring.template.groceries' },
];

/**
 * Extracts a short cadence label for the inline badge — e.g. "Weekly",
 * "Every 2 weeks · MO,WE". Falls back to the raw FREQ token (or, if the
 * rule is so malformed that `parseRecurrence` returns null, to a
 * "Custom" chip) so a user looking for stale rules still sees a flag
 * they can click through to fix.
 */
function useCadenceBadge(task: Task): string {
  const { t } = useI18n();
  const rule = task.recurrence ? parseRecurrence(task.recurrence) : null;
  if (!rule) return t('recurring.cadenceCustom');
  const freqKey: TranslationKey = ({
    DAILY: 'recurring.cadenceDaily',
    WEEKLY: 'recurring.cadenceWeekly',
    MONTHLY: 'recurring.cadenceMonthly',
    YEARLY: 'recurring.cadenceYearly',
  } as const)[rule.freq];
  const base = t(freqKey);
  const interval = rule.interval && rule.interval > 1 ? `×${rule.interval}` : '';
  const byday = rule.freq === 'WEEKLY' && rule.byday && rule.byday.length > 0
    ? ` · ${rule.byday.join(',')}`
    : '';
  return `${base}${interval}${byday}`;
}

function RecurrenceBadge({ task }: { task: Task }) {
  const label = useCadenceBadge(task);
  return (
    <span className="chip-tight gap-1 text-3xs font-medium text-accent/90 bg-accent/10 border border-accent/25 tabular-nums shrink-0">
      <RecurrenceIcon className="w-3 h-3" />
      {label}
    </span>
  );
}

export default function RecurringTasksView({ onSelectTask, onOpenQuickCapture }: Props) {
  const { t, formatNumber } = useI18n();
  const scroll = useScrollRestore('recurring-tasks');

  const { data: tasks, isLoading, isError, refetch } = useQuery({
    queryKey: QUERY_KEYS.recurringTasks(),
    queryFn: ({ signal }) => getRecurringTasks(signal),
    staleTime: STALE_DEFAULT,
    refetchInterval: REFETCH_INTERVAL,
  });

  // Audit-friendly order: group by FREQ so duplicate "Daily standup"
  // rules or drifting weeklies cluster together and are easy to spot.
  // `get_recurring_tasks` already sorts by TASK_ORDER_BY; this is a
  // secondary stable grouping on the client.
  const groups = useMemo(() => {
    if (!tasks) return [] as Array<{ freq: string; tasks: Task[] }>;
    const buckets = new Map<string, Task[]>();
    for (const task of tasks) {
      const rule = task.recurrence ? parseRecurrence(task.recurrence) : null;
      const freq = rule?.freq ?? 'CUSTOM';
      const bucket = buckets.get(freq);
      if (bucket) bucket.push(task);
      else buckets.set(freq, [task]);
    }
    const freqOrder = ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY', 'CUSTOM'];
    return freqOrder
      .filter((freq) => buckets.has(freq))
      .map((freq) => ({ freq, tasks: buckets.get(freq)! }));
  }, [tasks]);

  const total = tasks?.length ?? 0;

  // virtualize the flat row stream when the recurring
  // count crosses the shared list-view threshold (50 rows). Power
  // users with hundreds of recurring rules paid the full DOM cost on
  // every render — same regression the AllTasks/Kanban/Eisenhower
  // views already addressed via `@tanstack/react-virtual`. We only
  // window when there are enough rows to make the virtualizer's
  // measurement passes worthwhile (`shouldVirtualizeListView`).
  type RecurringRow =
    | { kind: 'header'; freq: string; count: number }
    | { kind: 'task'; task: Task };
  const flatRows = useMemo<RecurringRow[]>(() => {
    const out: RecurringRow[] = [];
    for (const group of groups) {
      out.push({ kind: 'header', freq: group.freq, count: group.tasks.length });
      for (const task of group.tasks) {
        out.push({ kind: 'task', task });
      }
    }
    return out;
  }, [groups]);
  const virtualize = shouldVirtualizeListView(flatRows.length);
  const virtualParentRef = useRef<HTMLDivElement | null>(null);
  const mergedScrollRef = useCallback(
    (node: HTMLDivElement | null) => {
      virtualParentRef.current = node;
      (scroll.ref as React.MutableRefObject<HTMLDivElement | null>).current = node;
    },
    [scroll.ref],
  );
  const HEADER_ROW_HEIGHT = 36;
  const virtualizer = useVirtualizer({
    count: flatRows.length,
    getScrollElement: () => virtualParentRef.current,
    estimateSize: (index) =>
      flatRows[index]?.kind === 'header' ? HEADER_ROW_HEIGHT : LIST_VIEW_ROW_ESTIMATE_PX,
    overscan: LIST_VIEW_OVERSCAN,
    getItemKey: (index) => {
      const row = flatRows[index];
      if (!row) return index;
      return row.kind === 'header' ? `h:${row.freq}` : `t:${row.task.id}`;
    },
  });

  return (
    <div className="h-full flex flex-col overflow-hidden">
      <title>{formatPageTitle(t('nav.recurring'))}</title>
      <header className="px-4 sm:px-8 pt-1.5 pb-5 shrink-0">
        <div className="flex items-baseline justify-between">
          <div>
            <div className="flex items-center gap-2.5">
              <h2 className="text-text-primary text-2xl font-light">{t('recurring.title')}</h2>
              {total > 0 && (
                <span className="chip-tight text-2xs font-medium text-text-muted/60 bg-surface-2/60 tabular-nums">
                  {formatNumber(total)}
                </span>
              )}
            </div>
            <p className="text-text-muted/70 text-xs mt-2 leading-relaxed">
              {t('recurring.subtitle')}
            </p>
          </div>
        </div>
      </header>

      <div
        ref={mergedScrollRef}
        onScroll={scroll.onScroll}
        className="flex-1 overflow-y-auto overscroll-contain px-4 sm:px-8 pb-8"
      >
        {isError && total > 0 && (
          <StaleDataBanner t={t} onRetry={() => { void refetch(); }} />
        )}
        {isLoading ? (
          <RecurringTasksViewSkeleton />
        ) : isError && total === 0 ? (
          <ModuleStatePanel
            variant="error"
            icon={<WarningIcon className="w-9 h-9" />}
            title={t('common.error')}
            actionLabel={t('error.tryAgain')}
            onAction={() => { void refetch(); }}
          />
        ) : total === 0 ? (
          <div className="flex flex-col items-center justify-center py-12 sm:py-24 text-center" role="status" aria-live="polite">
            <div className="mb-4 text-text-muted/60"><RecurrenceIcon className="w-9 h-9" /></div>
            <p className="text-text-secondary text-sm font-medium">{t('recurring.empty')}</p>
            <p className="text-text-muted text-xs mt-1.5 max-w-[26rem] leading-relaxed">{t('recurring.emptyHintActions')}</p>
            {onOpenQuickCapture && (
              <div className="mt-5 flex flex-col items-stretch sm:flex-row sm:items-center gap-2 max-w-md">
                {RECURRING_TEMPLATES.map((tpl) => (
                  <button
                    key={tpl.key}
                    type="button"
                    onClick={() => onOpenQuickCapture({ title: t(tpl.titleKey) })}
                    className="group rounded-r-card border border-card bg-surface-2/40 px-3.5 py-2.5 text-start hover:border-accent/30 hover:bg-surface-2 active:scale-[0.98] transition-[color,background-color,border-color,transform] duration-150 focus-ring-soft"
                  >
                    <span className="block text-xs font-medium text-text-primary">{t(tpl.labelKey)}</span>
                    <span className="block text-2xs text-text-muted mt-0.5 group-hover:text-accent transition-colors">+ {t('recurring.templateCtaLabel')}</span>
                  </button>
                ))}
              </div>
            )}
          </div>
        ) : virtualize ? (
          <div
            style={{ height: `${virtualizer.getTotalSize()}px`, width: '100%', position: 'relative' }}
          >
            {virtualizer.getVirtualItems().map((virtualItem) => {
              const row = flatRows[virtualItem.index];
              if (!row) return null;
              return (
                <div
                  key={virtualItem.key}
                  data-index={virtualItem.index}
                  ref={virtualizer.measureElement}
                  style={{
                    position: 'absolute',
                    top: 0,
                    left: 0,
                    width: '100%',
                    transform: `translateY(${virtualItem.start}px)`,
                  }}
                >
                  {row.kind === 'header' ? (
                    <RecurringSectionHeader freq={row.freq} count={row.count} />
                  ) : (
                    <div className="py-0.5">
                      <RecurringTaskRow task={row.task} onSelectTask={onSelectTask} />
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        ) : (
          <div className="space-y-6">
            {groups.map((group) => (
              <RecurringFrequencySection
                key={group.freq}
                freq={group.freq}
                tasks={group.tasks}
                onSelectTask={onSelectTask}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Frequency section — groups tasks by FREQ so duplicates surface visually
// ---------------------------------------------------------------------------

function RecurringFrequencySection({
  freq,
  tasks,
  onSelectTask,
}: {
  freq: string;
  tasks: Task[];
  onSelectTask?: ((taskId: string) => void) | undefined;
}) {
  return (
    <section>
      <RecurringSectionHeader freq={freq} count={tasks.length} />
      <div className="space-y-1.5">
        {tasks.map((task) => (
          <RecurringTaskRow
            key={task.id}
            task={task}
            onSelectTask={onSelectTask}
          />
        ))}
      </div>
    </section>
  );
}

/**
 * Header row shared between the non-virtualized layout and the
 * virtualized flat-row stream. Factored out so both
 * paths render byte-identical markup; the only difference between
 * them is that the virtualized form drops the section-level
 * `space-y-1.5` wrapper (the virtualizer positions rows absolutely,
 * so a flexbox gap on the parent is meaningless).
 */
const RecurringSectionHeader = memo(function RecurringSectionHeader({
  freq,
  count,
}: {
  freq: string;
  count: number;
}) {
  const { t, formatNumber } = useI18n();
  const labelKey: TranslationKey = ({
    DAILY: 'recurring.cadenceDaily',
    WEEKLY: 'recurring.cadenceWeekly',
    MONTHLY: 'recurring.cadenceMonthly',
    YEARLY: 'recurring.cadenceYearly',
    CUSTOM: 'recurring.cadenceCustom',
  } as const)[freq] ?? 'recurring.cadenceCustom';
  return (
    <h2 className="mb-2.5 flex items-center gap-2 px-2 -ms-2">
      <span className="text-text-secondary text-xs font-semibold">{t(labelKey)}</span>
      <span className="text-text-muted/60 text-2xs tabular-nums bg-surface-2/50 px-1.5 py-px rounded-r-control">
        {formatNumber(count)}
      </span>
    </h2>
  );
});

// ---------------------------------------------------------------------------
// Single recurring-task row — plain TaskCard + cadence badge overlay
// ---------------------------------------------------------------------------

const RecurringTaskRow = memo(function RecurringTaskRow({
  task,
  onSelectTask,
}: {
  task: Task;
  onSelectTask?: ((taskId: string) => void) | undefined;
}) {
  // Wrap the card so the cadence badge sits inside the card's right
  // gutter without forking TaskCard's layout. Absolute positioning
  // over `relative` keeps the existing card height and breakpoints
  // intact on narrow widths.
  return (
    <div className="relative">
      <TaskCard
        task={task}
        onClick={() => onSelectTask?.(task.id)}
      />
      <div className="pointer-events-none absolute top-2.5 end-4 flex items-center">
        <RecurrenceBadge task={task} />
      </div>
    </div>
  );
});
