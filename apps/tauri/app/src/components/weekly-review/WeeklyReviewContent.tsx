import { useCallback, useMemo } from 'react';
import { useScrollRestore } from '@/lib/useScrollRestore';
import { useCopyToClipboard } from '@/lib/platform/useCopyToClipboard';
import { addYmdDays } from '@/lib/dayContextMath';
import { resolveDateLocale } from '@/lib/dates/dateLocale';
import { formatPageTitle } from '@/lib/pageTitle';
import { formatNumber } from '@/locales';
import {
  SparkleIcon,
  WarningIcon,
  CheckIcon,
  ClockIcon,
  TargetIcon,
} from '../ui/icons';
import ModuleStatePanel from '../ui/ModuleStatePanel';
import { Tooltip } from '../ui/Tooltip';
import { formatDurationCompact } from '../today-view/primitives';
import {
  formatReviewCompletedTaskCountLabel,
} from '@/lib/dates/i18nCountPhrases';
import { type WeeklyReviewControllerState } from './useWeeklyReviewController';
import AccomplishmentsSection from './content/AccomplishmentsSection';
import DeferredTaskRow from './content/DeferredTaskRow';
import LookingAheadSection from './content/LookingAheadSection';
import OverdueSeveritySection from './content/OverdueSeveritySection';
import ReviewSection from './content/ReviewSection';
import StalledListRow from './content/StalledListRow';
import StatCard from './content/StatCard';
import { WeeklyReviewSkeleton } from './WeeklyReviewSkeleton';
import { buildWeeklyReviewClipboardText } from './copyReview.logic';

interface WeeklyReviewContentProps {
  controller: WeeklyReviewControllerState;
}

function formatReviewDateRange(todayYmd: string, locale: string): string {
  // Anchor both endpoints at UTC midnight so local-time DST transitions
  // cannot shift the displayed day. The YMDs come from dayContext which
  // already resolves the configured timezone; from here the Date objects
  // are only used as opaque formatting anchors with `timeZone: 'UTC'`.
  const startYmd = addYmdDays(todayYmd, -6);
  const end = new Date(`${todayYmd}T00:00:00Z`);
  const start = new Date(`${startYmd}T00:00:00Z`);

  const sameYear = start.getUTCFullYear() === end.getUTCFullYear();
  const sameMonth = sameYear && start.getUTCMonth() === end.getUTCMonth();

  const resolvedLocale = resolveDateLocale(locale);
  const fmtFull = new Intl.DateTimeFormat(resolvedLocale, {
    month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC',
  });
  const fmtShort = new Intl.DateTimeFormat(resolvedLocale, {
    month: 'short', day: 'numeric', timeZone: 'UTC',
  });
  const fmtDay = new Intl.DateTimeFormat(resolvedLocale, {
    day: 'numeric', timeZone: 'UTC',
  });

  if (sameMonth) {
    return `${fmtShort.format(start)} – ${fmtDay.format(end)}, ${end.getUTCFullYear()}`;
  }
  if (sameYear) {
    return `${fmtShort.format(start)} – ${fmtFull.format(end)}`;
  }
  return `${fmtFull.format(start)} – ${fmtFull.format(end)}`;
}

export default function WeeklyReviewContent({ controller }: WeeklyReviewContentProps) {
  const {
    dayContext,
    shelvingListId,
    shelveList,
    deferredActionByTaskId,
    isError,
    isLoading,
    locale,
    onOpenList,
    onSelectTask,
    refetch,
    review,
    runDeferredIntervention,
    t,
    // New enriched data
    completionsByDay,
    overdueBySeverity,
    upcomingNextWeek,
    nextWeekEvents,
    completedLastWeek,
    totalFocusMinutes,
    habitsCompletionRate,
    inlineActionByTaskId,
    completeTask,
    cancelTask,
  } = controller;
  const formatLocaleNumber = useCallback((value: number) => formatNumber(locale, value), [locale]);

  const scroll = useScrollRestore('weekly-review');
  const dateRangeLabel = useMemo(
    () => formatReviewDateRange(dayContext.todayYmd, locale),
    [dayContext.todayYmd, locale],
  );

  const completedCount = review?.completed_this_week.length ?? 0;
  const trendVsLastWeek = completedCount - completedLastWeek;

  const { copy, copying } = useCopyToClipboard();
  const handleCopyReview = useCallback(async () => {
    if (copying || !review) return;
    await copy(buildWeeklyReviewClipboardText({ review, locale, t }), t('review.reviewCopied'));
  }, [copy, copying, locale, review, t]);

  if (isLoading || isError || !review) {
    return (
      <div className="h-full flex flex-col overflow-hidden">
        <title>{formatPageTitle(t('nav.review'))}</title>
        <header className="px-4 sm:px-8 pt-1.5 pb-5 shrink-0">
          <h2 className="text-text-primary text-2xl font-light">{t('review.title')}</h2>
          <p className="text-text-muted text-xs mt-1">{dateRangeLabel}</p>
        </header>
        <div className="flex-1 overflow-y-auto overscroll-contain px-4 sm:px-8 pb-8">
          {isLoading ? (
            <WeeklyReviewSkeleton />
          ) : (
            <ModuleStatePanel
              variant="error"
              icon={<WarningIcon className="w-9 h-9" />}
              title={t('review.loadFailed')}
              subtitle={t('review.loadFailedHint')}
              actionLabel={t('error.tryAgain')}
              onAction={() => { void refetch(); }}
            />
          )}
        </div>
      </div>
    );
  }

  const hasAttentionItems = review.overdue_count > 0 || review.frequently_deferred.length > 0 || review.stalled_lists.length > 0;
  const hasLookingAhead = upcomingNextWeek.length > 0 || nextWeekEvents.length > 0;
  const isEmpty = completedCount === 0 && !hasAttentionItems && !hasLookingAhead && review.someday_items.length === 0;

  return (
    <div className="h-full flex flex-col overflow-hidden">
      <title>{formatPageTitle(t('nav.review'))}</title>

      {/* Header */}
      <header className="px-4 sm:px-8 pt-1.5 pb-5 shrink-0">
        <p className="text-text-muted text-xs font-medium mb-1">{t('nav.review')}</p>
        <div className="flex items-baseline justify-between">
          <h2 className="text-text-primary text-2xl font-light">{t('review.title')}</h2>
          <Tooltip label={t('review.copyReview')}>
            <button
              type="button"
              onClick={() => { void handleCopyReview(); }}
              disabled={copying}
              className="text-text-muted text-xs hover:text-text-secondary transition-colors disabled:opacity-50 rounded-r-control focus-ring-soft"
            >
              {copying ? t('common.copying') : t('review.copyReview')}
            </button>
          </Tooltip>
        </div>
        <p className="text-text-muted text-xs mt-1">{dateRangeLabel}</p>
      </header>

      <div ref={scroll.ref} onScroll={scroll.onScroll} className="flex-1 overflow-y-auto overscroll-contain px-4 sm:px-8 pb-8 space-y-10">

        {/* ─── Section 1: Week at a Glance ─── */}
        <section>
          <div className="grid grid-cols-2 xl:grid-cols-4 gap-3">
            <StatCard
              label={t('review.completed')}
              value={completedCount}
              color="success"
              icon={<CheckIcon className="w-4 h-4" />}
              subtitle={
                totalFocusMinutes > 0
                  ? formatDurationCompact(totalFocusMinutes, t('common.hourShort'), t('common.min'), formatLocaleNumber)
                  : t('review.tasksCompleted')
              }
              trend={completedLastWeek > 0 ? { value: trendVsLastWeek, label: t('review.vsLastWeek') } : undefined}
            />
            <StatCard
              label={t('review.focusTime')}
              value={totalFocusMinutes}
              color="accent"
              icon={<ClockIcon className="w-4 h-4" />}
              unitSuffix={t('common.min')}
              subtitle={
                totalFocusMinutes > 60
                  ? formatDurationCompact(totalFocusMinutes, t('common.hourShort'), t('common.min'), formatLocaleNumber)
                  : undefined
              }
            />
            <StatCard
              label={t('review.habitsRate')}
              value={habitsCompletionRate ?? 0}
              color={
                habitsCompletionRate == null ? 'muted' :
                habitsCompletionRate >= 80 ? 'success' :
                habitsCompletionRate >= 50 ? 'warning' : 'danger'
              }
              icon={<TargetIcon className="w-4 h-4" />}
              unitSuffix="%"
              subtitle={habitsCompletionRate == null ? t('review.noHabits') : undefined}
            />
            <StatCard
              label={t('review.overdueItems')}
              value={review.overdue_count}
              color={review.overdue_count > 5 ? 'danger' : review.overdue_count > 0 ? 'warning' : 'success'}
              icon={<WarningIcon className="w-4 h-4" />}
              subtitle={review.overdue_count > 0 ? t('review.overdueAlert') : undefined}
            />
          </div>

          {/* Throughput bar */}
          {(completedCount > 0 || review.created_this_week > 0) && (
            <CompletionRateBar
              completed={completedCount}
              created={review.created_this_week}
              locale={locale}
              t={t}
            />
          )}
        </section>

        {/* ─── Section 2: Accomplishments ─── */}
        <ReviewSection
          title={t('review.accomplishments')}
          subtitle={
            completedCount > 0
              ? `${formatReviewCompletedTaskCountLabel(locale, completedCount, t)}${totalFocusMinutes > 0 ? ` · ${formatDurationCompact(totalFocusMinutes, t('common.hourShort'), t('common.min'), formatLocaleNumber)}` : ''}`
              : t('review.accomplishmentsSubtitle')
          }
          icon="checkmark"
          variant="success"
          collapsible
          defaultExpanded={completedCount > 0}
        >
          <AccomplishmentsSection
            completionsByDay={completionsByDay}
            totalCount={completedCount}
            onSelectTask={onSelectTask}
            t={t}
          />
        </ReviewSection>

        {/* ─── Section 3: Attention Needed ─── */}
        {hasAttentionItems && (
          <ReviewSection
            title={t('review.attentionNeeded')}
            subtitle={t('review.attentionSubtitle')}
            icon="warning"
            variant={review.overdue_count > 5 ? 'danger' : review.overdue_count > 0 ? 'warning' : 'default'}
            badge={review.overdue_count + review.frequently_deferred.length + review.stalled_lists.length}
          >
            <div className="space-y-6">
              {/* Overdue by severity */}
              {review.overdue_count > 0 && (
                <div>
                  <h3 className="text-xs font-semibold text-text-muted uppercase tracking-wider mb-2 ms-1">
                    {t('review.overdue')} ({formatNumber(locale, review.overdue_count)})
                  </h3>
                  <OverdueSeveritySection
                    groups={overdueBySeverity}
                    totalOverdue={review.overdue_count}
                    locale={locale}
                    onSelectTask={onSelectTask}
                    inlineActionByTaskId={inlineActionByTaskId}
                    onComplete={(task) => { void completeTask(task); }}
                    onCancel={(task) => { void cancelTask(task); }}
                    onReschedule={(task) => { void runDeferredIntervention(task, 'schedule_tomorrow'); }}
                    t={t}
                  />
                </div>
              )}

              {/* Stuck tasks (frequently deferred) */}
              {review.frequently_deferred.length > 0 && (
                <div>
                  <h3 className="text-xs font-semibold text-text-muted uppercase tracking-wider mb-2 ms-1">
                    {t('review.stuckTasks')}
                  </h3>
                  <p className="text-text-muted/70 text-xs mb-2 ms-1">{t('review.stuckHint')}</p>
                  <div className="space-y-1.5">
                    {review.frequently_deferred.map((task) => (
                      <DeferredTaskRow
                        key={task.id}
                        task={task}
                        locale={locale}
                        todayLabel={t('upcoming.today')}
                        tomorrowLabel={t('upcoming.tomorrow')}
                        yesterdayLabel={t('upcoming.yesterday')}
                        onOpenDetail={() => onSelectTask(task.id)}
                        busyAction={deferredActionByTaskId[task.id] ?? null}
                        scheduleLabel={t('review.deferScheduleTomorrow')}
                        scheduleBusyLabel={t('review.deferScheduling')}
                        rescopeLabel={t('review.deferRescope')}
                        rescopeBusyLabel={t('review.deferRescoping')}
                        archiveLabel={t('review.deferArchive')}
                        archiveBusyLabel={t('review.deferArchiving')}
                        onScheduleTomorrow={() => { void runDeferredIntervention(task, 'schedule_tomorrow'); }}
                        onRescope={() => { void runDeferredIntervention(task, 'retriage'); }}
                        onArchive={() => { void runDeferredIntervention(task, 'archive'); }}
                      />
                    ))}
                  </div>
                </div>
              )}

              {/* Inactive projects (was "stalled lists") */}
              {review.stalled_lists.length > 0 && (
                <div>
                  <h3 className="text-xs font-semibold text-text-muted uppercase tracking-wider mb-2 ms-1">
                    {t('review.inactiveProjects')}
                  </h3>
                  <p className="text-text-muted/70 text-xs mb-2 ms-1">{t('review.inactiveHint')}</p>
                  <div className="space-y-1.5">
                    {review.stalled_lists.map((stalledList) => (
                      <StalledListRow
                        key={stalledList.id}
                        stalledList={stalledList}
                        t={t}
                        locale={locale}
                        archiving={shelvingListId === stalledList.id}
                        onOpenList={onOpenList}
                        onArchive={() => { void shelveList(stalledList); }}
                      />
                    ))}
                  </div>
                </div>
              )}
            </div>
          </ReviewSection>
        )}

        {/* ─── Section 4: Looking Ahead ─── */}
        <ReviewSection
          title={t('review.lookingAhead')}
          subtitle={t('review.lookingAheadSubtitle')}
          icon="calendar"
          collapsible
          defaultExpanded={hasLookingAhead}
        >
          <LookingAheadSection
            upcomingTasks={upcomingNextWeek}
            events={nextWeekEvents}
            onSelectTask={onSelectTask}
            t={t}
            locale={locale}
          />
        </ReviewSection>

        {/* ─── Someday Items (optional tail section) ─── */}
        {review.someday_items.length > 0 && (
          <ReviewSection
            title={t('review.somedayItems')}
            subtitle={t('review.somedayHint')}
            icon="someday"
            collapsible
            defaultExpanded={false}
            badge={review.someday_items.length}
          >
            <div className="space-y-1">
              {review.someday_items.slice(0, 10).map((task) => (
                <div
                  key={task.id}
                  // the someday row sets `role="button"`
                  // + `tabIndex={0}` to expose itself as a keyboard target,
                  // but had no visible focus indicator — keyboard users
                  // could land on the row without seeing where focus
                  // landed. Add the canonical accent focus ring so
                  // `Tab` traversal is observable, matching every other
                  // interactive list row in the review.
                  className="flex items-center gap-3 px-3 py-2 bg-surface-2 border border-card rounded-r-control cursor-pointer hover:bg-surface-3/30 transition-colors focus-ring-soft"
                  onClick={() => onSelectTask(task.id)}
                  onKeyDown={(e) => {
                    // Audit a11y: WAI-ARIA requires role="button" to
                    // fire on both Enter AND Space. Space-only users
                    // (muscle memory from native buttons) previously
                    // got nothing — or worse, page scroll. Also
                    // preventDefault on Space so the page doesn't
                    // scroll behind the modal.
                    if (e.key === 'Enter' || e.key === ' ') {
                      e.preventDefault();
                      onSelectTask(task.id);
                    }
                  }}
                  role="button"
                  tabIndex={0}
                >
                  <span className="text-text-muted text-sm">{'~'}</span>
                  <span className="text-sm text-text-primary truncate flex-1">{task.title}</span>
                </div>
              ))}
              {review.someday_items.length > 10 && (
                <p className="text-text-muted text-xs pt-2">
                  + {formatNumber(locale, review.someday_items.length - 10)} {t('review.more')}
                </p>
              )}
            </div>
          </ReviewSection>
        )}

        {/* ─── Empty state ─── */}
        {isEmpty && (
          <ModuleStatePanel
            icon={<SparkleIcon className="w-9 h-9" />}
            title={t('review.allClear')}
            subtitle={t('review.allClearHint')}
            className="py-12"
          />
        )}
      </div>
    </div>
  );
}

function CompletionRateBar({ completed, created, locale, t }: {
  completed: number;
  created: number;
  locale: string;
  t: (key: import('@/lib/i18n').TranslationKey) => string;
}) {
  const total = Math.max(completed, created);
  if (total === 0) return null;

  const completedPct = Math.round((completed / total) * 100);
  const createdPct = Math.round((created / total) * 100);
  const isAhead = completed >= created;

  return (
    <div className="bg-surface-2 border border-card rounded-r-card px-4 py-3 mt-3">
      <div className="flex items-center justify-between text-xs text-text-muted mb-2">
        <span>{t('review.throughputRatio')}</span>
        <span className={isAhead ? 'text-success' : 'text-warning'}>
          {formatNumber(locale, completedPct)}%
        </span>
      </div>
      <div className="flex gap-1 h-2 rounded-full overflow-hidden bg-surface-3">
        {completed > 0 && (
          <div
            className="bg-[var(--success-tint-lg)] rounded-full transition-[width] duration-500"
            style={{ width: `${completedPct}%` }}
          />
        )}
        {created > completed && (
          <div
            className="bg-[var(--warning-tint-lg)] rounded-full transition-[width] duration-500"
            style={{ width: `${createdPct - completedPct}%` }}
          />
        )}
      </div>
      <div className="flex items-center justify-between text-xs text-text-muted/70 mt-1.5">
        <span className="flex items-center gap-1">
          <span className="inline-block w-2 h-2 rounded-full bg-[var(--success-tint-lg)]" />
          {t('review.completed')} ({formatNumber(locale, completed)})
        </span>
        <span className="flex items-center gap-1">
          <span className="inline-block w-2 h-2 rounded-full bg-[var(--warning-tint-lg)]" />
          {t('review.newTasks')} ({formatNumber(locale, created)})
        </span>
      </div>
    </div>
  );
}
