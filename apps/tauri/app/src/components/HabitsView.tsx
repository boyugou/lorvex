import { useMemo, useState } from 'react';
import { useListJkNavigation } from '../lib/useListJkNavigation';
import { useQuery } from '@tanstack/react-query';
import { getHabitsWithStats } from '@/lib/ipc/habits';
import type { HabitFrequencyType } from '@lorvex/shared/types';
import { useI18n, type TranslationKey } from '../lib/i18n';
import { useScrollRestore } from '../lib/useScrollRestore';
import { useConfiguredDayContext } from '../lib/dayContext';
import { DAY_SCOPED_QUERY_KEYS } from '../lib/query/dayScopedQueryKeys';
import { STALE_SHORT } from '../lib/query/timing';
import { useMcpServerStatus } from '../lib/hooks/useMcpServerStatus';
import type { View } from '../lib/types';
import { AddHabitForm } from './habits/AddHabitForm';
import { HabitCard } from './habits/HabitCard';
import { HabitContextMenu } from './habits/HabitContextMenu';
import { HabitsViewSkeleton } from './habits/HabitsViewSkeleton';
import { generateLast84Days } from './habits/dateWindow.logic';
import { useHabitCardContextMenu } from './habits/useHabitCardContextMenu';
import { useHabitStatsCompletionActions } from './habits/useHabitCompletionActions';
import { useHabitDeleteAction } from './habits/useHabitDeleteAction';
import AssistantNotConfiguredPanel from './ui/AssistantNotConfiguredPanel';
import { FlameIcon, WarningIcon } from './ui/icons';
import ModuleStatePanel from './ui/ModuleStatePanel';
import { Tooltip } from './ui/Tooltip';
import { Button } from './ui/Button';

/**
 * Empty-state template chips for HabitsView. Each chip pre-fills
 * the AddHabit form so a first-time user can land on a sensible
 * cadence + name pair without typing anything. Editing remains
 * possible before submit — the chip is a scaffold, not a one-tap
 * commit. The 84-day heatmap mockup rendered beside the chips shows
 * what the surface will look like once any habit has accumulated
 * completions, so the user can preview the payoff before
 * committing.
 */
const HABIT_TEMPLATES: ReadonlyArray<{
  key: 'run' | 'read' | 'meditate';
  labelKey: TranslationKey;
  detailKey: TranslationKey;
  frequency: HabitFrequencyType;
  targetCount: number;
}> = [
  { key: 'run', labelKey: 'habits.template.run', detailKey: 'habits.template.runDetail', frequency: 'weekly', targetCount: 3 },
  { key: 'read', labelKey: 'habits.template.read', detailKey: 'habits.template.readDetail', frequency: 'daily', targetCount: 1 },
  { key: 'meditate', labelKey: 'habits.template.meditate', detailKey: 'habits.template.meditateDetail', frequency: 'daily', targetCount: 1 },
];

/**
 * Compact 14×4 cell preview heatmap rendered alongside the template
 * chips. Cells are filled deterministically (seeded by index) so the
 * mockup renders identically across re-renders and themes — only the
 * accent / surface tokens drive the visible color shifts.
 *
 * Cells stagger in over ~750ms (56 cells × 8ms per-cell delay + a
 * 300 ms `fade-in` per cell = ~748 ms before the final cell settles)
 * so the heatmap drips into place rather than appearing as a static
 * placeholder bitmap. Clicking any cell calls `onCellClick`, which
 * opens the AddHabit form pre-filled with the `daily` cadence.
 *
 * Accessibility contract:
 *   - The mockup is interactive in two registers. Mouse users can
 *     click any cell; keyboard / assistive-tech users reach exactly
 *     one representative cell (the first non-empty one) via the tab
 *     ring. That representative button carries an `aria-label`
 *     describing the affordance, every other cell announces with the
 *     same purpose-free decorative label, and the container is not
 *     `aria-hidden` — `aria-hidden` on a subtree containing focusable
 *     descendants is a WAI-ARIA violation (the descendants stay
 *     pointer-activatable, which AT/screen-reader "list buttons"
 *     traversal exposes as phantom buttons).
 *   - The non-representative cells stay `tabIndex={-1}` so keyboard
 *     traversal does not have to walk through 55 identical cells to
 *     escape the mockup.
 */
function HabitsEmptyHeatmapMock({
  heatmapLabel,
  onCellClick,
  templateActionLabel,
}: {
  heatmapLabel: string;
  onCellClick?: () => void;
  templateActionLabel: string;
}) {
  const cols = 14;
  const rows = 4;
  const cells: number[] = [];
  for (let i = 0; i < cols * rows; i++) {
    // Pseudo-random fill density — a third blank, a third
    // half-filled, a third full — gives the heatmap a believable
    // "real habit progress" silhouette without claiming any
    // specific user pattern.
    const hash = ((i * 37) ^ (i >> 2)) & 0xff;
    if (hash < 90) cells.push(0);
    else if (hash < 175) cells.push(1);
    else cells.push(2);
  }
  const interactive = !!onCellClick;
  // First non-empty cell carries the keyboard-reachable affordance.
  // Empty cells would be invisible focus targets and rendering all 56
  // cells in the tab ring is noise — one representative covers the
  // "this region is interactive" affordance.
  const representativeIndex = interactive
    ? cells.findIndex((level) => level > 0)
    : -1;
  const handleKey = (e: React.KeyboardEvent<HTMLButtonElement>) => {
    if (!onCellClick) return;
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      onCellClick();
    }
  };
  return (
    <div className="mt-6 rounded-r-card border border-card bg-surface-2/30 px-4 py-3" role="presentation">
      <p className="text-2xs font-semibold tracking-widest uppercase text-text-muted/70 mb-2.5 text-start">
        {heatmapLabel}
      </p>
      <div
        className="grid gap-1"
        style={{ gridTemplateColumns: `repeat(${cols}, 1fr)` }}
      >
        {cells.map((level, i) => {
          const base = `aspect-square rounded-r-control motion-safe:animate-[fade-in_0.3s_ease-out_both] ${
            level === 0
              ? 'bg-surface-3/40'
              : level === 1
                ? 'bg-accent/30'
                : 'bg-accent/70'
          }`;
          const style = { animationDelay: `${i * 8}ms` } as const;
          if (interactive) {
            const isRepresentative = i === representativeIndex;
            return (
              <button
                key={i}
                type="button"
                tabIndex={isRepresentative ? 0 : -1}
                onClick={onCellClick}
                onKeyDown={isRepresentative ? handleKey : undefined}
                aria-label={templateActionLabel}
                className={`${base} cursor-pointer hover:ring-1 hover:ring-accent/60 hover:scale-110 active:scale-95 transition-[transform,box-shadow] duration-100 ${
                  isRepresentative ? 'focus-ring-soft' : ''
                }`}
                style={style}
              />
            );
          }
          return <div key={i} className={base} style={style} aria-hidden="true" />;
        })}
      </div>
      {interactive && (
        <p className="mt-2 text-2xs text-text-muted/60 text-start" aria-hidden="true">
          {templateActionLabel}
        </p>
      )}
    </div>
  );
}

interface HabitsViewProps {
  /**
   * Forwarded from MainViewContent so the empty-state setup CTA can
   * deep-link into Settings -> Assistant MCP when the MCP server status
   * resolves to false.
   */
  onNavigate?: ((view: View) => void) | undefined;
}

export default function HabitsView({ onNavigate }: HabitsViewProps = {}) {
  const { t } = useI18n();
  const scroll = useScrollRestore('habits');
  const mcpStatus = useMcpServerStatus();
  const mcpUnconfigured = mcpStatus !== null && mcpStatus.resolved === false;
  const { todayYmd } = useConfiguredDayContext();
  const dates84 = useMemo(() => generateLast84Days(todayYmd), [todayYmd]);
  const { adjustHabit } = useHabitStatsCompletionActions(t('common.error'));
  const deleteHabit = useHabitDeleteAction();
  const habitMenu = useHabitCardContextMenu();
  const [showAddForm, setShowAddForm] = useState(false);
  // Template-driven pre-fill for the AddHabitForm. `null` means the
  // user opened the form from the bare "+ Add habit" CTA and gets
  // empty defaults; a template selection populates name + cadence
  // before mount.
  const [addFormPrefill, setAddFormPrefill] = useState<{ name: string; frequency: HabitFrequencyType; targetCount: number } | null>(null);
  const openAddForm = (prefill: typeof addFormPrefill = null) => {
    setAddFormPrefill(prefill);
    setShowAddForm(true);
  };
  const closeAddForm = () => {
    setShowAddForm(false);
    setAddFormPrefill(null);
  };

  const {
    data: habits = [],
    isLoading,
    isError,
    refetch,
  } = useQuery({
    queryKey: DAY_SCOPED_QUERY_KEYS.habitsWithStats(todayYmd),
    queryFn: ({ signal }) => getHabitsWithStats(signal),
    staleTime: STALE_SHORT,
  });
  const jk = useListJkNavigation(habits.length);

  if (isLoading) {
    return <HabitsViewSkeleton />;
  }

  if (isError) {
    return (
      <ModuleStatePanel
        variant="error"
        icon={<WarningIcon className="w-9 h-9" />}
        title={t('habits.loadFailed')}
        subtitle={t('habits.loadFailedHint')}
        actionLabel={t('error.tryAgain')}
        onAction={() => void refetch()}
      />
    );
  }

  return (
    <div ref={scroll.ref} onScroll={scroll.onScroll} className="h-full overflow-y-auto">
      <div className="px-4 sm:px-8 pt-1.5 pb-5">
        <div className="mb-8 flex items-start justify-between gap-3">
          <div>
            <h2 className="text-text-primary text-2xl font-light">{t('nav.habits')}</h2>
            <p className="text-xs text-text-muted mt-2">{t('habits.viewSubtitle')}</p>
          </div>
          {!showAddForm && (
            <Tooltip label={t('habits.addHabitTooltip')}>
              <Button variant="ghost" size="sm" onClick={() => openAddForm(null)}>
                + {t('habits.addHabit')}
              </Button>
            </Tooltip>
          )}
        </div>

        {showAddForm && (
          <AddHabitForm
            onClose={closeAddForm}
            {...(addFormPrefill
              ? {
                  initialValues: {
                    name: addFormPrefill.name,
                    frequency: addFormPrefill.frequency,
                    targetCount: addFormPrefill.targetCount,
                  },
                }
              : {})}
          />
        )}

        {habits.length === 0 && !showAddForm ? (
          mcpUnconfigured ? (
            <AssistantNotConfiguredPanel onNavigate={onNavigate} />
          ) : (
            <div className="flex flex-col items-center justify-center py-12 sm:py-16 text-center" role="status" aria-live="polite">
              <div className="mb-4 text-text-muted/60"><FlameIcon className="w-9 h-9" /></div>
              <p className="text-text-secondary text-sm font-medium">{t('habits.noHabits')}</p>
              <p className="text-text-muted text-xs mt-1.5 max-w-[26rem] leading-relaxed">{t('habits.noHabitsHint')}</p>
              <button
                type="button"
                onClick={() => openAddForm(null)}
                className="mt-6 text-xs px-4 py-2 rounded-r-control bg-accent text-on-accent active:scale-[0.97] hover:bg-accent/90 transition-[color,background-color,transform] duration-150 focus-ring-strong"
              >
                + {t('habits.addHabit')}
              </button>
              <div className="mt-5 grid grid-cols-1 sm:grid-cols-3 gap-2 max-w-2xl w-full">
                {HABIT_TEMPLATES.map((tpl) => (
                  <button
                    key={tpl.key}
                    type="button"
                    onClick={() => openAddForm({ name: t(tpl.labelKey), frequency: tpl.frequency, targetCount: tpl.targetCount })}
                    className="group rounded-r-card border border-card bg-surface-2/40 px-3.5 py-2.5 text-start hover:border-accent/30 hover:bg-surface-2 active:scale-[0.98] transition-[color,background-color,border-color,transform] duration-150 focus-ring-soft"
                  >
                    <span className="block text-xs font-medium text-text-primary">{t(tpl.labelKey)}</span>
                    <span className="block text-2xs text-text-muted mt-0.5 group-hover:text-accent transition-colors">{t(tpl.detailKey)}</span>
                  </button>
                ))}
              </div>
              <div className="w-full max-w-2xl">
                <HabitsEmptyHeatmapMock
                  heatmapLabel={t('habits.emptyHeatmapLabel')}
                  templateActionLabel={t('habits.emptyHeatmapClickHint')}
                  onCellClick={() => openAddForm({ name: '', frequency: 'daily', targetCount: 1 })}
                />
              </div>
            </div>
          )
        ) : habits.length === 0 ? null : (
          <>
            <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
              {habits.map((habit, index) => (
                <div
                  key={habit.id}
                  ref={jk.register(index)}
                  // Roving tabindex: the first habit card is keyboard-reachable
                  // via Tab so the grid joins the natural focus order; jk/arrow
                  // keys then walk siblings without each card claiming its own
                  // Tab stop (which would force users to Tab through every
                  // card to escape the grid). Pairs with `jk.register` which
                  // programmatically focuses the active row.
                  tabIndex={index === 0 ? 0 : -1}
                  className="focus-ring-soft rounded-r-card"
                >
                  <HabitCard
                    habit={habit}
                    dates84={dates84}
                    onAdjust={adjustHabit}
                    onContextMenu={habitMenu.openMenu}
                  />
                </div>
              ))}
            </div>

            <p className="mt-8 text-center text-xs text-text-muted">
              {t('habits.managedByAI')}
            </p>
          </>
        )}
      </div>

      <HabitContextMenu
        menuState={habitMenu.menuState}
        onClose={habitMenu.closeMenu}
        onDelete={deleteHabit}
      />
    </div>
  );
}
