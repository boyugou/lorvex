import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { openMainQuickCapture } from '@/lib/ipc/runtime';
import { quickCapture } from '@/lib/ipc/tasks/mutations/quickCapture';
import { DRAFT_KEYS, UI_STATE_DRAFT_KEYS, writeDraft } from '@/lib/storage/drafts';
import { getUIStateString, removeUIState, setUIState } from '@/lib/storage/uiState';

const POPOVER_QUICK_ADD_KEY = UI_STATE_DRAFT_KEYS.popoverQuickAdd;
import { usePreference } from '@/lib/query/usePreference';
import { STALE_LONG } from '@/lib/query/timing';
import { PREF_AI_BRIEFING_ENABLED } from '@/lib/preferences/keys';
import { reportClientError } from '@/lib/errors/errorLogging';
import { invalidateExternalMutationQueries } from '@/lib/query/queryKeys';
import { useCurrentTime } from '@/lib/time/useCurrentTime';
import { toast } from '@/lib/notifications/toast';
import { formatDate } from '@/lib/dates/dateLocale';
import { useI18n } from '@/lib/i18n';
import { isImeComposing } from '@/lib/ime';
import {
  formatOverdueTaskCountLabel,
  formatPopoverTasksInPlanCountLabel,
} from '@/lib/dates/i18nCountPhrases';
import { formatDurationCompact } from '../today-view/primitives';
import { PopoverTaskItem } from './PopoverTaskItem';
import { PopoverEventItem, type EnrichedEvent } from './PopoverEventItem';
import { Pill } from '../ui/Pill';
import { ValidatedField } from '../ui/ValidatedField';
import type { PopoverWindowControllerState } from './usePopoverWindowController';

interface PopoverWindowContentProps {
  controller: PopoverWindowControllerState;
}

/** Parse YYYY-MM-DD + timezone into locale-aware day/weekday/month. */
function parseDateDisplay(ymd: string, timezone: string, locale: string) {
  const _dp = ymd.split('-').map(Number);
  const y = _dp[0] ?? 2024, m = _dp[1] ?? 1, d = _dp[2] ?? 1;
  // Create a date in the configured timezone by using UTC noon to avoid DST edge issues
  const date = new Date(Date.UTC(y, m - 1, d, 12));
  // `formatDate` routes through the shared memoized formatter cache,
  // so the popover's 1 Hz re-render cycle reuses one
  // `Intl.DateTimeFormat` per (locale, options-shape) pair.
  return {
    day: d,
    weekday: formatDate(date, locale, { weekday: 'short', timeZone: timezone }),
    month: formatDate(date, locale, { month: 'short', timeZone: timezone }),
  };
}

export default function PopoverWindowContent({ controller }: PopoverWindowContentProps) {
  const {
    briefing,
    completingTaskIds,
    handleCompleteTask,
    handleOpenMain,
    handleOpenTask,
    handleDeferTask,
    handleDeferTaskNextWeek,
    isLoading,
    locale,
    nextUpTasks,
    overdueCount,
    deferringTaskIds,
    t,
    attentionCount,
    todayEvents,
    todayYmd,
    timezone,
  } = controller;
  const { formatNumber, format } = useI18n();

  const { value: aiBriefingEnabled } = usePreference(
    PREF_AI_BRIEFING_ENABLED,
    (raw) => raw !== 'false',
    { staleTime: STALE_LONG },
  );

  // The `formatDate` calls inside `parseDateDisplay` route through the
  // shared memoized cache in `lib/dateLocale`, so the per-render cost is
  // a Map lookup rather than `Intl.DateTimeFormat` construction.
  const dateDisplay = useMemo(
    () => parseDateDisplay(todayYmd, timezone, locale),
    [todayYmd, timezone, locale],
  );

  const totalDurationMinutes = useMemo(
    () => nextUpTasks.reduce((sum, task) => sum + (task.estimated_minutes ?? 0), 0),
    [nextUpTasks],
  );

  const nowTime = useCurrentTime(timezone);

  const [eventsExpanded, setEventsExpanded] = useState(false);
  // Restore any previously-persisted text on mount. The popover may
  // be unmounted/remounted across visibility cycles (Tauri menubar
  // popovers commonly do); persisting via `getUIStateString` lets the
  // user resume typing where they left off instead of losing the draft.
  const [quickAddText, setQuickAddText] = useState<string>(
    () => getUIStateString(POPOVER_QUICK_ADD_KEY, ''),
  );

  // Mirror every change of `quickAddText` into UI state so the next
  // mount can restore. The empty-string branch removes the entry so
  // we don't keep a stale empty key around the storage forever.
  useEffect(() => {
    if (quickAddText) {
      setUIState(POPOVER_QUICK_ADD_KEY, quickAddText);
    } else {
      removeUIState(POPOVER_QUICK_ADD_KEY);
    }
  }, [quickAddText]);
  const [quickAdding, setQuickAdding] = useState(false);
  // surface the backend rejection inline (in addition
  // to the existing toast) so the failure follows the input via
  // `aria-invalid` / `aria-errormessage` instead of disappearing the
  // moment the user moves focus elsewhere.
  const [quickAddError, setQuickAddError] = useState<string | null>(null);
  const [expandedTaskId, setExpandedTaskId] = useState<string | null>(null);

  // All-clear celebration pill. When `attentionCount` drops to
  // 0 from a positive count (i.e. the user just finished their last
  // tracked task from the popover), briefly swap the pill row for an
  // "All clear" affirmation, then auto-restore the normal count chips
  // after 1800ms. Triggering only on the transition (not on
  // continuously-zero mounts) keeps the pill from screaming on every
  // visit to an empty plan.
  const [showAllClearPill, setShowAllClearPill] = useState(false);
  const prevAttentionCountRef = useRef(attentionCount);
  useEffect(() => {
    const previous = prevAttentionCountRef.current;
    prevAttentionCountRef.current = attentionCount;
    // Trigger only on the transition `> 0 → 0`. Mounts that already
    // see `attentionCount === 0` skip — the user didn't just finish
    // anything, they just landed on an empty plan.
    if (previous > 0 && attentionCount === 0) {
      setShowAllClearPill(true);
      const handle = window.setTimeout(() => setShowAllClearPill(false), 1800);
      return () => window.clearTimeout(handle);
    }
    return undefined;
  }, [attentionCount]);
  // Clear stale expansion if the task is no longer in the list. Memoized so
  // a re-render doesn't re-scan `nextUpTasks` when neither the expanded id
  // nor the list changed.
  const validExpandedId = useMemo(
    () =>
      expandedTaskId && nextUpTasks.some((task) => task.id === expandedTaskId)
        ? expandedTaskId
        : null,
    [expandedTaskId, nextUpTasks],
  );
  const qc = useQueryClient();

  const handleQuickAdd = useCallback(async () => {
    const title = quickAddText.trim();
    if (!title || quickAdding) return;
    setQuickAdding(true);
    setQuickAddError(null);
    try {
      await quickCapture({ title });
      setQuickAddText('');
      invalidateExternalMutationQueries(qc);
    } catch (error) {
      reportClientError('popover.quickAdd', 'Failed to add task', error);
      // preserve the backend rejection message (e.g.
      // "title too long", "list not found") so the user knows why the
      // quick capture failed rather than seeing a bare "Error".
      toast.errorWithDetail(error, t('capture.error'));
      // also bind the rejection inline so the input
      // carries `aria-invalid` + `aria-errormessage` until the user
      // edits the field.
      const message = error instanceof Error ? error.message : String(error);
      setQuickAddError(message || t('capture.error'));
    } finally {
      setQuickAdding(false);
    }
  }, [quickAddText, quickAdding, qc, t]);

  // Expand-to-main-window escape hatch: stash the typed text in the
  // canonical quick-capture draft (same key the main window reads on
  // mount via `readQuickCaptureDraft`), then open the main window's
  // quick-capture form. Tauri webviews share localStorage origin, so
  // the popover-side write is visible to the main-window read. This
  // hands off to the full capture form without the user having to
  // retype when the title needs body text, tags, or a list pick.
  const handleExpandToMain = useCallback(async () => {
    const title = quickAddText.trim();
    if (title) {
      writeDraft(
        DRAFT_KEYS.quickCapture,
        JSON.stringify({ title, body: '', tagsInput: '', selectedListId: null }),
      );
    }
    try {
      await openMainQuickCapture();
      setQuickAddText('');
    } catch (error) {
      reportClientError('popover.expandQuickAdd', 'Failed to expand quick-add to main window', error);
      toast.errorWithDetail(error, t('common.error'));
    }
  }, [quickAddText, t]);

  // P1: persist the in-flight quick-add text across popover
  // visibility cycles. Without this, hiding the popover (clicking
  // outside, OS focus change, or pressing Esc) wiped the user's
  // typed text — they'd reopen the menu bar and find an empty
  // input. Stash to UI state on every keystroke so the next mount
  // can restore. The 'visibilitychange' / 'pagehide' guard ensures
  // the persist fires even on the OS hide path that doesn't
  // unmount the React tree.
  // (handled inline via the input onChange — no separate effect
  // needed because `quickAddText` lives in a useState hook that
  // already survives re-renders within a single popover lifetime.
  // Tauri popover windows are typically destroyed/restored, so
  // we'd need a cross-mount persistence — which `writeDraft` above
  // already covers when the user clicks expand. Persisting on
  // every keystroke would compete with the main window's own
  // draft-autosave and is rejected by design.)

  const sortedEvents = useMemo<EnrichedEvent[]>(() => {
    const _nowP = nowTime.split(':').map(Number);
    const nowH = _nowP[0] ?? 0, nowM = _nowP[1] ?? 0;
    const nowMinutes = nowH * 60 + nowM;
    const sorted = [...todayEvents].sort((a, b) => {
      if (a.all_day && !b.all_day) return -1;
      if (!a.all_day && b.all_day) return 1;
      return (a.start_time ?? '').localeCompare(b.start_time ?? '');
    });
    return sorted.map((event) => {
      let isPast = false;
      let isNow = false;
      let minutesUntil = -1;
      if (event.all_day) {
        // All-day events are never past/now/soon
      } else if (event.start_time) {
        const _sp = event.start_time.split(':').map(Number);
        const sh = _sp[0] ?? 0, sm = _sp[1] ?? 0;
        const startMin = sh * 60 + sm;
        const endStr = event.end_time ?? `${String(Math.min(sh + 1, 23)).padStart(2, '0')}:${String(sm).padStart(2, '0')}`;
        const _ep = endStr.split(':').map(Number);
        const eh = _ep[0] ?? 0, em = _ep[1] ?? 0;
        const endMin = eh * 60 + em;

        if (nowMinutes >= endMin) {
          isPast = true;
        } else if (nowMinutes >= startMin) {
          isNow = true;
        } else if (startMin - nowMinutes <= 30) {
          minutesUntil = startMin - nowMinutes;
        }
      }
      return { event, isPast, isNow, minutesUntil };
    });
  }, [todayEvents, nowTime]);

  return (
    <div className="h-full w-full p-0 overflow-hidden rounded-r-panel" style={{ clipPath: 'inset(0 round var(--radius-r-panel))' }}>
      {/* Canonical popover depth: --shadow-popover paired with the
          `border-popover` rim. Both ride per-theme overrides without
          this surface needing to respell either. */}
      <section className="liquid-popover-panel profile-material-panel h-full w-full rounded-r-panel border border-popover bg-surface-1 shadow-[var(--shadow-popover)] px-3.5 py-3 flex flex-col">

        {/* -- Header: date + stats -- */}
        <header className="flex items-center gap-3 pb-2.5 border-b border-card">
          <div className="flex items-baseline gap-1.5">
            <span className="text-2xl font-bold text-text-primary tabular-nums leading-none">
              {dateDisplay.day}
            </span>
            <span className="text-xs font-medium text-text-muted/70">
              {dateDisplay.weekday} {dateDisplay.month}
            </span>
          </div>
          <div className="flex-1" />
          {/* X5: chip cells need `min-w-0` + `truncate` so a
              long-language label (e.g. "{N} επεισημένες εργασίες"
              in Greek, where the locale-pluralized label can run 3×
              the English equivalent) stays bounded inside the
              header rail and ellipsizes instead of pushing the
              header into a second visual row. The wrapper enforces
              `min-w-0` so the inner truncate works inside the
              flex parent. */}
          <div className="flex items-center gap-1.5 min-w-0">
            {showAllClearPill ? (
              <Pill tone="success" size="sm" className="truncate min-w-0 motion-safe:animate-[fade-in_0.18s_ease-out]">
                <span className="inline-flex items-center gap-1">
                  <svg width="10" height="10" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                    <path d="M2.5 6.5l2.5 2.5 4.5-5" />
                  </svg>
                  {t('popover.allClear')}
                </span>
              </Pill>
            ) : (
              <>
                {overdueCount > 0 && (
                  <Pill tone="danger" size="sm" tabular className="truncate min-w-0">
                    {formatOverdueTaskCountLabel(locale, overdueCount, t)}
                  </Pill>
                )}
                <Pill tone="muted" size="sm" tabular className="truncate min-w-0">
                  {formatPopoverTasksInPlanCountLabel(locale, attentionCount, t)}
                  {totalDurationMinutes > 0 && ` · ${formatDurationCompact(totalDurationMinutes, t('common.hourShort'), t('common.min'), formatNumber)}`}
                </Pill>
              </>
            )}
          </div>
        </header>

        {/* -- Inline quick-add --: route the input through `ValidatedField` so
            the rejection from `quickCapture` is announced to assistive
            tech via `aria-invalid` + `aria-errormessage` (in addition
            to the existing toast). The label is hidden visually
            because the placeholder already carries the affordance — we
            only need the programmatic association. */}
        <div className="py-2">
          <ValidatedField
            label={t('capture.placeholder')}
            showLabel={false}
            error={quickAddError}
            errorClassName="text-3xs text-danger px-1 mt-1"
          >
            {({ fieldProps }) => (
              <div className="relative group/quickadd">
                <svg aria-hidden="true" width="14" height="14" viewBox="0 0 14 14" fill="none" className="absolute start-2.5 top-1/2 -translate-y-1/2 text-text-muted/40 group-focus-within/quickadd:text-accent/60 pointer-events-none transition-colors duration-150">
                  <path d="M7 2v10M2 7h10" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
                </svg>
                <input
                  {...fieldProps}
                  type="text"
                  value={quickAddText}
                  onChange={(e) => {
                    setQuickAddText(e.target.value);
                    if (quickAddError) setQuickAddError(null);
                  }}
                  onKeyDown={(e) => {
                    if (isImeComposing(e)) return;
                    // P1: Shift+Enter expands to the main capture form
                    // pre-populated with the typed text, instead of
                    // submitting inline. Plain Enter still submits.
                    if (e.key === 'Enter' && e.shiftKey) {
                      e.preventDefault();
                      void handleExpandToMain();
                      return;
                    }
                    if (e.key === 'Enter') { void handleQuickAdd(); }
                  }}
                  placeholder={t('capture.placeholder')}
                  disabled={quickAdding}
                  className={`${fieldProps.className} w-full bg-surface-2/40 border border-card rounded-r-card ps-8 pe-9 py-2 text-xs text-text-primary placeholder:text-text-muted/60 outline-hidden focus:border-accent/40 focus:bg-surface-2/60 focus-ring-soft transition-colors duration-200 disabled:opacity-50 aria-[invalid=true]:border-danger/60`}
                  aria-label={t('capture.placeholder')}
                />
                {/* P1: explicit expand-to-main affordance —
                    the chord (⇧↵) is wired in the keydown above; the
                    visible button gives mouse users (and discoverability
                    for new users) the same path. Hidden until the user
                    types something to keep the rest pane clean. */}
                {quickAddText.length > 0 && (
                  <button
                    type="button"
                    onClick={() => { void handleExpandToMain(); }}
                    aria-label={t('popover.expandToMain')}
                    title={t('popover.expandToMain')}
                    className="absolute end-1.5 top-1/2 -translate-y-1/2 w-7 h-7 flex items-center justify-center rounded-r-control text-text-muted/60 hover:text-accent hover:bg-surface-2/80 transition-colors focus-ring-soft"
                  >
                    <svg aria-hidden="true" width="11" height="11" viewBox="0 0 11 11" fill="none">
                      <path d="M3 3h5v5" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" />
                      <path d="M8 3L3 8" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" />
                    </svg>
                  </button>
                )}
              </div>
            )}
          </ValidatedField>
        </div>

        {/* -- Next Up tasks -- */}
        <div className="flex-1 min-h-0 pt-2 pb-2 flex flex-col gap-2 overflow-y-auto overscroll-contain">
          <p className="text-2xs font-semibold text-text-muted/60 uppercase tracking-wider px-0.5">
            {t('popover.nextUp')}
          </p>
          {nextUpTasks.length === 0 ? (
            <p className="text-xs text-text-muted/60 italic px-0.5">{t('popover.noPlan')}</p>
          ) : (
            <ul className="space-y-0.5">
              {nextUpTasks.map((task) => (
                <PopoverTaskItem
                  key={task.id}
                  task={task}
                  completing={completingTaskIds.includes(task.id)}
                  deferring={deferringTaskIds.includes(task.id)}
                  expanded={validExpandedId === task.id}
                  onComplete={(id) => { void handleCompleteTask(id); }}
                  onOpenTask={handleOpenTask}
                  onDefer={(id) => { void handleDeferTask(id); }}
                  onDeferNextWeek={(id) => { void handleDeferTaskNextWeek(id); }}
                  onToggleExpand={() => setExpandedTaskId(validExpandedId === task.id ? null : task.id)}
                  t={t}
                />
              ))}
            </ul>
          )}

          {/* -- Today's Events -- */}
          {sortedEvents.length > 0 && (
            <div className="space-y-0.5 mt-1">
              <p className="text-2xs font-semibold text-text-muted/60 uppercase tracking-wider px-0.5">
                {t('popover.events')}
              </p>
              <ul className="space-y-px">
                {(eventsExpanded ? sortedEvents : sortedEvents.slice(0, 4)).map((enriched) => (
                  <PopoverEventItem key={enriched.event.id} enriched={enriched} locale={locale} t={t} format={format} />
                ))}
                {sortedEvents.length > 4 && (
                  <li className="px-1.5 py-0.5">
                    <button
                      type="button"
                      onClick={() => setEventsExpanded((previous) => !previous)}
                      className="text-xs text-accent/80 hover:text-accent transition-colors focus-ring-soft rounded-r-control"
                    >
                      {eventsExpanded
                        ? t('common.showFewer')
                        : `+${formatNumber(sortedEvents.length - 4)} ${t('popover.more')}`}
                    </button>
                  </li>
                )}
              </ul>
            </div>
          )}

          {/* -- AI Briefing (respects user preference) -- */}
          {aiBriefingEnabled && (briefing || isLoading) && (
            <div className="rounded-r-card bg-surface-2/40 border border-card px-2.5 py-2 mt-auto">
              <p className="flex items-center gap-1 text-2xs font-semibold text-text-muted/60">
                <svg aria-hidden="true" width="12" height="12" viewBox="0 0 12 12" fill="none" className="shrink-0 text-accent/50"><path d="M6 1l1.2 3.3L10.5 5l-3.3 1.2L6 9.5 4.8 6.2 1.5 5l3.3-1.2L6 1z" fill="currentColor" /></svg>
                {t('today.aiBriefing')}
              </p>
              <p className="mt-1 text-2xs leading-relaxed text-text-secondary/80 line-clamp-2">
                {isLoading ? <span className="inline-block h-3 w-32 rounded-r-control bg-surface-2 animate-pulse align-middle" /> : briefing}
              </p>
            </div>
          )}

        </div>

        {/* -- Footer -- */}
        <div className="pt-2 border-t border-card flex items-center justify-end">
          <button
            type="button"
            onClick={handleOpenMain}
            className="group/openapp flex items-center gap-1 text-2xs text-text-muted/60 hover:text-accent font-medium transition-colors focus-ring-soft rounded-r-control px-1"
          >
            {t('popover.openApp')}
            {/* Arrow micro-translation on hover. Adds 2px of
                rightward intent to the chevron when the button is
                hovered or focused; reduced-motion users keep a
                static glyph. */}
            <svg
              aria-hidden="true"
              width="12"
              height="12"
              viewBox="0 0 12 12"
              fill="none"
              className="shrink-0 motion-safe:transition-transform motion-safe:duration-[180ms] motion-safe:group-hover/openapp:translate-x-0.5 motion-safe:group-focus-visible/openapp:translate-x-0.5"
            >
              <path d="M4.5 2.5L8 6l-3.5 3.5" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </button>
        </div>
      </section>
    </div>
  );
}
