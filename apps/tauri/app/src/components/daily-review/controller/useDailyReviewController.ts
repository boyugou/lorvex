import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useMounted } from '@/lib/useMounted';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { getCalendarEventsUnified } from '@/lib/ipc/calendar';
import { getTodaysHabits } from '@/lib/ipc/habits';
import { getDailyReviewByDate, getDailyReviews, getOverview, upsertDailyReview } from '@/lib/ipc/tasks/reviews';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { HabitSummary } from '@/lib/ipc/habits';
import type { Task } from '@/lib/ipc/tasks/models';
import { reportClientError } from '@/lib/errors/errorLogging';
import { useI18n } from '@/lib/i18n';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { addYmdDays } from '@/lib/dayContextMath';
import { useLazyRef } from '@/lib/useLazyRef';
import { useScrollRestore } from '@/lib/useScrollRestore';
import { DAY_SCOPED_QUERY_KEYS } from '@/lib/query/dayScopedQueryKeys';
import { QUERY_KEYS, invalidateDailyReviewQueries } from '@/lib/query/queryKeys';
import { toast } from '@/lib/notifications/toast';
import { useCopyToClipboard } from '@/lib/platform/useCopyToClipboard';
import { DRAFT_KEYS, clearDraft, readDraft, writeDraft } from '@/lib/storage/drafts';
import {
  readDailyReviewDraftFromStorage,
  serializeDailyReviewDraft,
} from './draft.logic';
import { installDailyReviewDraftAutosaveRuntime } from './draftAutosave.runtime';
import {
  buildDailyReviewDraftPayload,
  buildDailyReviewReflectionExpansionState,
  buildDailyReviewUnmountPersistence,
  buildDailyReviewUpsertInput,
  resolveDailyReviewInitialState,
  shouldResetDailyReviewComposedDate,
} from './controller.logic';
import {
  cleanupDailyReviewJustSavedReset,
  createBrowserDailyReviewTimerHost,
  createDailyReviewJustSavedRuntimeState,
  scheduleDailyReviewJustSavedReset,
} from './justSaved.runtime';
import { formatDailyReviewScaleCopyParts } from './scaleMetadata.logic';

export function useDailyReviewController() {
  const { t, format, locale } = useI18n();
  const qc = useQueryClient();
  const { todayYmd, timezone } = useConfiguredDayContext();
  const scroll = useScrollRestore('daily-review');
  // --------------- queries ---------------
  const {
    data: reviews = [],
    isLoading,
    isError,
    refetch,
  } = useQuery({
    queryKey: QUERY_KEYS.dailyReviews(),
    queryFn: ({ signal }) => getDailyReviews(30, signal),
  });

  const { data: todayReview, isFetched: todayReviewLoaded } = useQuery({
    queryKey: QUERY_KEYS.dailyReview(todayYmd),
    queryFn: ({ signal }) => getDailyReviewByDate(todayYmd, signal),
    staleTime: 10_000,
  });

  // Day summary data
  const { data: overview } = useQuery({
    queryKey: QUERY_KEYS.overview(),
    queryFn: ({ signal }) => getOverview(signal),
    staleTime: 30_000,
  });

  const { data: todaysHabits } = useQuery({
    queryKey: DAY_SCOPED_QUERY_KEYS.todaysHabits(todayYmd),
    queryFn: ({ signal }) => getTodaysHabits(signal),
    staleTime: 30_000,
  });

  const { data: todayEvents } = useQuery({
    queryKey: QUERY_KEYS.dailyReviewEvents(todayYmd),
    queryFn: ({ signal }) => getCalendarEventsUnified(todayYmd, todayYmd, signal),
    staleTime: 60_000,
  });

  // --------------- derived data ---------------
  // Last 7 days trend for mini chart
  const last7DaysTrend = useMemo(() => {
    const sorted = [...reviews].sort((a, b) => a.date.localeCompare(b.date)).slice(-7);
    return sorted.map(r => ({
      date: r.date,
      mood: r.mood,
      energy: r.energy_level,
    }));
  }, [reviews]);

  const streak = useMemo(() => {
    const dateSet = new Set(reviews.map(r => r.date));
    let count = 0;
    let cursor = todayYmd;
    while (dateSet.has(cursor)) {
      count++;
      cursor = addYmdDays(cursor, -1);
    }
    return count;
  }, [reviews, todayYmd]);

  // Day summary derived
  const daySummary = useMemo(() => {
    const completedTasks: Task[] = overview?.recently_completed ?? [];
    const stats = overview?.stats;
    const completedCount = stats?.completed_today ?? 0;

    const habits: HabitSummary[] = todaysHabits ?? [];
    const habitsCompleted = habits.filter(h => h.completions_today >= h.target_count).length;
    const habitsTotal = habits.length;

    const events: UnifiedCalendarEvent[] = todayEvents ?? [];
    const eventCount = events.length;

    // Tasks needing attention (overdue + today's pool)
    const attentionCount = stats?.attention_count ?? 0;

    return {
      completedTasks,
      completedCount,
      attentionCount,
      habits,
      habitsCompleted,
      habitsTotal,
      events,
      eventCount,
    };
  }, [overview, todaysHabits, todayEvents]);

  // --------------- copy handler ---------------
  const { copy, copying } = useCopyToClipboard();
  const handleCopyTodayEntry = useCallback(async () => {
    if (copying || !todayReview) return;
    const lines: string[] = [`${t('dailyReview.title')} \u2014 ${todayReview.date}\n`];
    const parts = formatDailyReviewScaleCopyParts({
      mood: todayReview.mood,
      energyLevel: todayReview.energy_level,
      locale,
      t,
    });
    if (parts.length > 0) {
      lines.push(parts.join('  |  '));
      lines.push('');
    }
    if (todayReview.summary) {
      lines.push(todayReview.summary);
      lines.push('');
    }
    if (todayReview.wins) {
      lines.push(`**${t('dailyReview.wins')}:** ${todayReview.wins}`);
      lines.push('');
    }
    if (todayReview.blockers) {
      lines.push(`**${t('dailyReview.blockers')}:** ${todayReview.blockers}`);
      lines.push('');
    }
    if (todayReview.learnings) {
      lines.push(`**${t('dailyReview.learnings')}:** ${todayReview.learnings}`);
      lines.push('');
    }
    await copy(lines.join('\n').trimEnd(), t('dailyReview.entryCopied'));
  }, [copy, copying, locale, todayReview, t]);

  // --------------- form state ---------------
  const [summary, setSummary] = useState('');
  const [mood, setMood] = useState<number | null>(null);
  const [energy, setEnergy] = useState<number | null>(null);
  const [wins, setWins] = useState('');
  const [blockers, setBlockers] = useState('');
  const [learnings, setLearnings] = useState('');
  const [saving, setSaving] = useState(false);
  const [showValidation, setShowValidation] = useState(false);
  const [justSaved, setJustSaved] = useState(false);
  const [initialized, setInitialized] = useState(false);
  const [reflectionHydrationRevision, setReflectionHydrationRevision] = useState(0);
  // capture the calendar day the panel is showing when the
  // user starts composing, so a save submitted after local midnight is
  // still attributed to the day the user was reviewing — not the next
  // day. `todayYmd` comes from a TanStack query that refreshes in the
  // background, so we freeze it at initialization and pin it for the
  // lifetime of this session's draft.
  const [composedForDate, setComposedForDate] = useState<string | null>(null);
  const dirtyRef = useRef(false);
  const mountedRef = useMounted();
  const displayDateYmd = composedForDate ?? todayYmd;
  const showTodayScopedInsights = displayDateYmd === todayYmd;
  const justSavedRuntimeStateRef = useLazyRef(() => createDailyReviewJustSavedRuntimeState());
  useEffect(() => () => {
    cleanupDailyReviewJustSavedReset(
      justSavedRuntimeStateRef.current,
      createBrowserDailyReviewTimerHost(),
    );
    // justSavedRuntimeStateRef is a stable MutableRefObject from useLazyRef.
  }, [justSavedRuntimeStateRef]);

  useEffect(() => {
    const nextState = resolveDailyReviewInitialState({
      initialized,
      dirty: dirtyRef.current,
      todayReviewLoaded,
      storedDraft: readDailyReviewDraftFromStorage(() => readDraft(DRAFT_KEYS.dailyReview)),
      todayReview: todayReview ?? null,
      todayYmd,
    });
    if (!nextState) return;

    setSummary(nextState.form.summary);
    setMood(nextState.form.mood);
    setEnergy(nextState.form.energy);
    setWins(nextState.form.wins);
    setBlockers(nextState.form.blockers);
    setLearnings(nextState.form.learnings);
    setComposedForDate(nextState.form.expectedDate);
    dirtyRef.current = nextState.source === 'draft';
    setInitialized(true);
    setReflectionHydrationRevision((revision) => revision + 1);
    if (nextState.source === 'draft') {
      toast.info(t('dailyReview.draftRestored'));
    }
  }, [todayReview, todayReviewLoaded, initialized, t, todayYmd]);

  useEffect(() => {
    if (!shouldResetDailyReviewComposedDate({
      composedForDate,
      dirty: dirtyRef.current,
      todayYmd,
    })) {
      return;
    }
    setComposedForDate(null);
    setInitialized(false);
  }, [composedForDate, todayYmd]);

  const markDirty = useCallback(() => {
    dirtyRef.current = true;
    setInitialized(true);
    // Ensure we have a pinned expected_date even if the panel opened
    // on an empty day (no remote review, no restored draft) and the
    // user started typing before the init effect fired.
    setComposedForDate((prev) => prev ?? todayYmd);
  }, [todayYmd]);

  // debounce-persist a draft to localStorage while the
  // user is typing. The unmount flush is a safety net for graceful
  // unmount; a hard crash (OOM, OS kill, power loss) bypasses unmount
  // entirely, so autosave is the primary durability guarantee. 500 ms
  // matches the app's draft autosave cadence.
  useEffect(() => {
    if (!initialized || !dirtyRef.current) return;
    const draft = buildDailyReviewDraftPayload({
      summary,
      mood,
      energy,
      wins,
      blockers,
      learnings,
      composedForDate,
      todayYmd,
    });
    if (!draft) return;
    return installDailyReviewDraftAutosaveRuntime({
      delayMs: 500,
      draft,
      persistSerializedDraft: (serializedDraft) => {
        writeDraft(DRAFT_KEYS.dailyReview, serializedDraft);
      },
      reportPersistError: (err) => {
        reportClientError(
          'dailyReview.autosave.draft',
          'Failed to persist daily-review draft to localStorage',
          err,
          undefined,
          'warn',
        );
      },
      serializeDraft: serializeDailyReviewDraft,
      timerHost: createBrowserDailyReviewTimerHost(),
    });
  }, [
    blockers,
    composedForDate,
    energy,
    initialized,
    learnings,
    mood,
    summary,
    todayYmd,
    wins,
  ]);

  const handleSave = useCallback(async () => {
    const input = buildDailyReviewUpsertInput({
      summary,
      mood,
      energy,
      wins,
      blockers,
      learnings,
      composedForDate,
      todayYmd,
    });
    if (!input || saving) return;
    setSaving(true);
    try {
      await upsertDailyReview(input);
      // Successful save — drop any pending draft so next mount reads
      // fresh remote state, not the stale draft.
      clearDraft(DRAFT_KEYS.dailyReview);
      dirtyRef.current = false;
      invalidateDailyReviewQueries(qc);
      if (input.expected_date !== todayYmd) {
        setComposedForDate(null);
        setInitialized(false);
      }
      setJustSaved(true);
      toast.success(t('dailyReview.saved'));
      // Reset the just-saved state after a delay.
      scheduleDailyReviewJustSavedReset({
        delayMs: 3000,
        isMounted: () => mountedRef.current,
        setJustSaved,
        state: justSavedRuntimeStateRef.current,
        timerHost: createBrowserDailyReviewTimerHost(),
      });
    } catch (error) {
      reportClientError('dailyReview.save', 'Failed to save daily review', error);
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      if (mountedRef.current) {
        setSaving(false);
      }
    }
    // justSavedRuntimeStateRef is a stable MutableRefObject from useLazyRef.
  }, [blockers, composedForDate, energy, justSavedRuntimeStateRef, learnings, mood, mountedRef, qc, saving, summary, t, todayYmd, wins]);

  const handleSaveClick = useCallback(() => {
    if (!summary.trim()) {
      setShowValidation(true);
      return;
    }
    void handleSave();
  }, [summary, handleSave]);

  // --------------- unmount flush ---------------
  // Initialize the latest-form ref with `null` and assign on each
  // render, so we don't allocate a fresh object literal every render
  // only to discard it (useRef keeps the first value).
  type LatestForm = {
    summary: string;
    mood: number | null;
    energy: number | null;
    wins: string;
    blockers: string;
    learnings: string;
    composedForDate: string | null;
  };
  const latestFormRef = useRef<LatestForm | null>(null);
  latestFormRef.current = { summary, mood, energy, wins, blockers, learnings, composedForDate };

  useEffect(() => {
    return () => {
      if (!dirtyRef.current) return;
      // Always populated by the render-side assignment above; the
      // null guard is a TS narrow, not a runtime invariant.
      const latest = latestFormRef.current;
      if (!latest) return;
      const {
        summary: s,
        mood: m,
        energy: e,
        wins: w,
        blockers: b,
        learnings: l,
        composedForDate: cfd,
      } = latest;
      const persistence = buildDailyReviewUnmountPersistence({
        summary: s,
        mood: m,
        energy: e,
        wins: w,
        blockers: b,
        learnings: l,
        composedForDate: cfd,
        todayYmd,
      });
      if (!persistence.draft) return;
      // Persist a durable draft FIRST so even if the unmount save fails
      // (async IPC hangs, DB error, app force-quits before the promise
      // resolves) the next mount restores the user's in-flight content.
      // `writeDraft` swallows storage quota / disabled exceptions; a
      // failure here is non-fatal because the IPC save below is also
      // attempted, and the worst-case outcome (both fail) is silent
      // loss of the in-flight draft.
      writeDraft(DRAFT_KEYS.dailyReview, serializeDailyReviewDraft(persistence.draft));
      if (!persistence.upsertInput) return;
      void upsertDailyReview(persistence.upsertInput)
        .then(() => {
          invalidateDailyReviewQueries(qc);
          // IPC save succeeded — draft is now redundant, drop it.
          clearDraft(DRAFT_KEYS.dailyReview);
        })
        .catch((err) => {
          reportClientError(
            'dailyReview.unmountSave',
            'Unmount save failed — draft preserved in localStorage for next mount',
            err,
          );
        });
    };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps -- refs only, runs on unmount

  const pastReviews = useMemo(
    () => reviews.filter((review) => review.date !== displayDateYmd),
    [reviews, displayDateYmd],
  );

  const reflectionExpansion = useMemo(
    () => buildDailyReviewReflectionExpansionState({
      scopeDate: displayDateYmd,
      hydrationRevision: reflectionHydrationRevision,
      wins,
      blockers,
      learnings,
    }),
    [blockers, displayDateYmd, learnings, reflectionHydrationRevision, wins],
  );

  return {
    // i18n
    t,
    format,
    locale,
    todayYmd,
    displayDateYmd,
    showTodayScopedInsights,
    timezone,
    // scroll
    scroll,
    // query state
    reviews,
    isLoading,
    isError,
    refetch,
    // today
    todayReview: todayReview ?? null,
    // derived
    pastReviews,
    last7DaysTrend,
    streak: showTodayScopedInsights ? streak : 0,
    daySummary,
    // copy
    copying,
    handleCopyTodayEntry,
    // form state
    summary,
    setSummary,
    mood,
    setMood,
    energy,
    setEnergy,
    wins,
    setWins,
    blockers,
    setBlockers,
    learnings,
    setLearnings,
    reflectionExpansion,
    saving,
    justSaved,
    showValidation,
    setShowValidation,
    markDirty,
    handleSaveClick,
  };
}

export type DailyReviewController = ReturnType<typeof useDailyReviewController>;
