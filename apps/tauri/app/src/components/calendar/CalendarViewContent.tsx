import { lazy, Suspense, useCallback, useEffect, useState } from 'react';
import { useQuery } from '@tanstack/react-query';

import { formatCalendarDate } from '@/lib/dates/dateLocale';
import { formatPageTitle } from '@/lib/pageTitle';
import { useScrollRestore } from '@/lib/useScrollRestore';
import { useRuntimeProfile } from '@/lib/useRuntimeProfile';
import { useNetworkStatus } from '@/lib/useNetworkStatus';
import { shouldIgnoreShortcut } from '@/lib/shortcutGuard';
import { listCalendarSubscriptions } from '@/lib/ipc/calendar';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { STALE_DEFAULT } from '@/lib/query/timing';
import { DayPanel } from './day-panel';
import { MonthGrid } from './MonthGrid';
import { WeekGrid } from './WeekGrid';
import { ListFilterPills } from '../ui/ListFilterPills';
import { TagFilterPills } from '../ui/TagFilterPills';
import { WarningIcon } from '../ui/icons';
import { Button } from '../ui/Button';
import { ToggleChip } from '../ui/ToggleChip';
import ModuleStatePanel from '../ui/ModuleStatePanel';
import { TaskDetailSkeleton } from '../ui/SkeletonShimmer';
import { Tooltip } from '../ui/Tooltip';
import { Banner } from '../ui/Banner';
import ErrorBoundary from '../ErrorBoundary';
import { installCalendarViewShortcutRuntime } from './CalendarViewContent.runtime';
import { useCalendarTaskActions } from './useCalendarTaskActions';
import type { CalendarViewController } from './useCalendarViewController';

const TaskDetail = lazy(() => import('../TaskDetail'));

interface CalendarViewContentProps {
  controller: CalendarViewController;
}

export function CalendarViewContent({ controller }: CalendarViewContentProps) {
  const runtimeProfile = useRuntimeProfile();
  const isMobile = runtimeProfile.runtimeClass === 'mobile';
  const scroll = useScrollRestore('calendar');
  const [autoShowAddEvent, setAutoShowAddEvent] = useState(false);
  const {
    allTags,
    clearTagFilter,
    eventsByDate,
    filterListId,
    goToNextMonth,
    goToNextWeek,
    goToPrevMonth,
    goToPrevWeek,
    goToToday,
    handleSelectDate,
    dayPanelExpanded,
    closeDayPanel,
    toggleDayPanel,
    hasCalendarError,
    invalidateAll,
    isCalendarLoading,
    lists,
    locale,
    month,
    monthLabel,
    refetchEvents,
    refetchTasks,
    selectedDate,
    selectedEvents,
    selectedTags,
    selectedTaskId,
    setFilterListId,
    selectedTasks,
    setSelectedTaskId,
    switchViewMode,
    t,
    tasksByDate,
    today,
    toggleTag,
    viewMode,
    weekLabel,
    weekStart,
    weekdayLabels,
    weekStartDay,
    year,
  } = controller;
  const { handleRescheduleTask, handleRescheduleTaskAt } = useCalendarTaskActions({ t });

  // first-launch offline path. On a fresh install the user
  // has zero calendar subscriptions, and the existing `emptyMonthHint`
  // tells them to "Connect your Mac / Windows calendar in Settings".
  // That instruction is a dead end when the user is offline — the
  // subscription dialog needs network to fetch the ICS feed. Detect the
  // combined "no subs AND offline" case and swap the copy so we\u2019re
  // not sending first-launch-offline users down a broken path.
  const { online } = useNetworkStatus();
  const { data: subscriptions = [] } = useQuery({
    queryKey: QUERY_KEYS.calendarSubscriptions(),
    queryFn: ({ signal }) => listCalendarSubscriptions(signal),
    staleTime: STALE_DEFAULT,
  });
  const hasNoSubscriptions = subscriptions.length === 0;
  const showOfflineEmptyState = hasNoSubscriptions && !online;
  const calendarContentLayoutClass =
    !isCalendarLoading && !hasCalendarError && (viewMode === 'month' || viewMode === 'week')
    ? 'min-h-0 flex flex-col'
    : 'overflow-y-auto overscroll-contain';

  // Keyboard shortcuts for calendar navigation
  useEffect(() => {
    return installCalendarViewShortcutRuntime({
      windowTarget: window,
      viewMode,
      shouldIgnoreShortcutTarget: shouldIgnoreShortcut,
      goToPrevMonth,
      goToPrevWeek,
      goToNextMonth,
      goToNextWeek,
      goToToday,
      switchViewMode,
    });
  }, [viewMode, goToPrevMonth, goToPrevWeek, goToNextMonth, goToNextWeek, goToToday, switchViewMode]);

  const handleNewEvent = useCallback(() => {
    // Select today to open the DayPanel, then signal it to auto-open the event form
    handleSelectDate(today);
    setAutoShowAddEvent(true);
  }, [handleSelectDate, today]);

  // Clear the auto-show flag once the DayPanel has consumed it
  const consumeAutoShowAddEvent = useCallback(() => {
    setAutoShowAddEvent(false);
  }, []);



  // Mobile and desktop now share a single `dayPanelExpanded` source
  // of truth in the controller — `handleSelectDate` flips it to
  // `true` for either path, so the prior mobile-only auto-expand
  // effect is no longer needed.

  return (
    <div className={`h-full flex overflow-hidden ${isMobile ? 'flex-col' : ''}`}>
      <title>{formatPageTitle(t('nav.calendar'))}</title>
      <div className={`flex flex-col overflow-hidden transition-[flex,min-width] duration-200 ${selectedTaskId ? 'flex-1 min-w-0' : 'flex-1'}`}>
        <header className={`shrink-0 ${isMobile ? 'px-4 pt-1.5 pb-3' : 'px-4 sm:px-8 pt-1.5 pb-5'}`}>
          <p className="text-text-muted text-xs font-medium mb-1">{t('calendar.title')}</p>
          <div className="flex items-center justify-between flex-wrap gap-2">
            <h2 className="text-text-primary text-2xl font-light">
              {viewMode === 'month' ? monthLabel : weekLabel}
            </h2>
            <div className="flex items-center gap-2 flex-wrap">
              <div className="flex items-center border border-surface-3 rounded-r-control overflow-hidden">
                <ToggleChip
                  size="sm"
                  variant="segmented"
                  onClick={() => switchViewMode('month')}
                  selected={viewMode === 'month'}
                  className="px-2.5"
                >
                  {t('calendar.month')}
                </ToggleChip>
                <ToggleChip
                  size="sm"
                  variant="segmented"
                  onClick={() => switchViewMode('week')}
                  selected={viewMode === 'week'}
                  className="px-2.5"
                >
                  {t('calendar.week')}
                </ToggleChip>
              </div>
              <button
                type="button"
                onClick={goToToday}
                className="text-xs text-text-muted hover:text-text-primary border border-surface-3 px-2.5 py-1 rounded-r-control transition-colors focus-ring-soft"
              >
                {t('calendar.today')}
              </button>
              <Tooltip label={t('calendar.previous')}>
                <button
                  type="button"
                  onClick={viewMode === 'month' ? goToPrevMonth : goToPrevWeek}
                  aria-label={t('calendar.previous')}
                  className="w-7 h-7 flex items-center justify-center rounded-r-control hover:bg-surface-3 text-text-muted hover:text-text-primary transition-colors focus-ring-soft"
                >
                  ‹
                </button>
              </Tooltip>
              <Tooltip label={t('calendar.next')}>
                <button
                  type="button"
                  onClick={viewMode === 'month' ? goToNextMonth : goToNextWeek}
                  aria-label={t('calendar.next')}
                  className="w-7 h-7 flex items-center justify-center rounded-r-control hover:bg-surface-3 text-text-muted hover:text-text-primary transition-colors focus-ring-soft"
                >
                  ›
                </button>
              </Tooltip>
              <Button variant="ghost" size="sm" onClick={handleNewEvent}>
                + {t('calendar.newEvent')}
              </Button>
            </div>
          </div>
          <div className="flex items-center gap-2 mt-3 flex-wrap">
            <ListFilterPills lists={lists} value={filterListId} onChange={setFilterListId} />
            <TagFilterPills tags={allTags} selected={selectedTags} onToggle={toggleTag} onClear={clearTagFilter} />
          </div>
        </header>

        <div ref={scroll.ref} onScroll={scroll.onScroll} className={`flex-1 ${isMobile ? 'px-4 pb-4' : 'px-4 sm:px-8 pb-8'} ${calendarContentLayoutClass}`}>
          {isCalendarLoading ? (
            <ModuleStatePanel variant="loading" />
          ) : hasCalendarError ? (
            <ModuleStatePanel
              variant="error"
              icon={<WarningIcon className="w-9 h-9" />}
              title={t('calendar.loadFailed')}
              subtitle={t('calendar.loadFailedHint')}
              actionLabel={t('common.retry')}
              onAction={() => {
                void refetchTasks();
                void refetchEvents();
              }}
            />
          ) : viewMode === 'month' ? (
            <div className="animate-[fade-in_0.15s_ease-out] flex-1 min-h-0 flex flex-col">
            {/* an empty month looked indistinguishable from
                a broken integration. Surface a compact hint above the
                grid when both tasksByDate and eventsByDate are empty
                for the visible range so a first-time user knows the
                two paths (connect native calendar, or set task due
                dates) that populate this view. Week and day views get
                their own inline hint via DayPanel's existing empty
                state — keeping this one scoped to the month grid so
                the hint doesn't fight the week-column layout. */}
            {Object.keys(tasksByDate).length === 0 && Object.keys(eventsByDate).length === 0 ? (
              showOfflineEmptyState ? (
                <Banner
                  tone="warning"
                  density="cozy"
                  className="mb-3"
                  icon={<OfflineCalendarIcon />}
                >
                  {t('calendar.offline.emptyState')}
                </Banner>
              ) : (
                <div
                  role="status"
                  className="mb-3 text-xs text-text-muted bg-surface-2/60 border border-card rounded-r-control px-3 py-2 leading-relaxed"
                >
                  {t('calendar.emptyMonthHint')}
                </div>
              )
            ) : null}
            <MonthGrid
              year={year}
              month={month}
              today={today}
              selectedDate={dayPanelExpanded ? selectedDate : null}
              tasksByDate={tasksByDate}
              eventsByDate={eventsByDate}
              weekdayLabels={weekdayLabels}
              weekStartDay={weekStartDay}
              locale={locale}
              t={t}
              onSelectDate={handleSelectDate}
              onSelectTask={setSelectedTaskId}
              onRescheduleTask={handleRescheduleTask}
            />
            </div>
          ) : (
            <div className="animate-[fade-in_0.15s_ease-out] flex-1 min-h-0 flex flex-col">
            <WeekGrid
              weekStart={weekStart}
              today={today}
              selectedDate={dayPanelExpanded ? selectedDate : null}
              tasksByDate={tasksByDate}
              eventsByDate={eventsByDate}
              weekdayLabels={weekdayLabels}
              locale={locale}
              t={t}
              onSelectDate={handleSelectDate}
              onSelectTask={setSelectedTaskId}
              onInvalidate={invalidateAll}
              onRescheduleTask={handleRescheduleTaskAt}
            />
            </div>
          )}
        </div>

      </div>

      {selectedDate && !selectedTaskId ? (
        isMobile ? (
          <div className="shrink-0 border-t border-surface-3">
            <button
              type="button"
              onClick={toggleDayPanel}
              className="w-full flex items-center justify-between px-4 py-2 text-xs text-text-muted hover:text-text-primary transition-colors"
            >
              <span className="font-medium">
                {formatCalendarDate(selectedDate, locale, {
                  weekday: 'short',
                  month: 'short',
                  day: 'numeric',
                })}
              </span>
              <span className={`transition-transform duration-200 ${dayPanelExpanded ? 'rotate-180' : ''}`}>
                ▾
              </span>
            </button>
            {dayPanelExpanded && (
              <DayPanel
                date={selectedDate}
                tasks={selectedTasks}
                events={selectedEvents}
                locale={locale}
                t={t}
                onSelectTask={setSelectedTaskId}
                onInvalidate={invalidateAll}
                autoShowAddEvent={autoShowAddEvent}
                onAutoShowAddEventConsumed={consumeAutoShowAddEvent}
                isMobile
              />
            )}
          </div>
        ) : (
          // Desktop: animate the panel's width so opening/closing
          // slides instead of pop-clipping. `dayPanelExpanded` is the
          // sole gate; `selectedDate` continues to drive grid
          // highlighting independent of panel visibility, which means
          // closing the panel preserves the selected-day accent.
          //
          // `inert` is the load-bearing a11y attribute: it removes
          // every descendant from the tab order AND from the
          // accessibility tree at once. Pairing `aria-hidden` with
          // `pointer-events-none` (the prior shape) blocks the mouse
          // but leaves focusable buttons (`×`, the list/timeline
          // toggle, the EventForm submit if it had been opened)
          // reachable via Tab, then strands focus on an invisible
          // 0-width control when the user dismisses the panel. With
          // `inert`, the browser handles both concerns natively.
          <div
            inert={!dayPanelExpanded}
            className={`shrink-0 overflow-hidden border-s border-card transition-[width,opacity] duration-200 ease-out ${
              dayPanelExpanded ? 'w-80 opacity-100' : 'w-0 opacity-0 border-s-0'
            }`}
          >
            <DayPanel
              date={selectedDate}
              tasks={selectedTasks}
              events={selectedEvents}
              locale={locale}
              t={t}
              onSelectTask={setSelectedTaskId}
              onInvalidate={invalidateAll}
              autoShowAddEvent={autoShowAddEvent}
              onAutoShowAddEventConsumed={consumeAutoShowAddEvent}
              onClose={closeDayPanel}
            />
          </div>
        )
      ) : null}

      {selectedTaskId ? (
        <div className={`shrink-0 border-surface-3 ${isMobile ? 'border-t' : 'w-80 border-s'}`}>
          {/* ErrorBoundary wraps Suspense so a chunk-load
              or async-after-suspend failure in the lazy TaskDetail
              chunk surfaces a retry affordance instead of stranding
              the user on a shimmer that never resolves. Reset keys
              ensure that selecting a different task (or clearing the
              selection) clears any prior error state. The fallback
              uses the shared TaskDetailSkeleton from #2505 so the
              loading silhouette matches the real content shape. */}
          <ErrorBoundary resetKeys={['calendar-task-detail', selectedTaskId]}>
            <Suspense fallback={<TaskDetailSkeleton />}>
              <TaskDetail
                key={selectedTaskId}
                taskId={selectedTaskId}
                onClose={() => setSelectedTaskId(null)}
                onSelectTask={setSelectedTaskId}
              />
            </Suspense>
          </ErrorBoundary>
        </div>
      ) : null}
    </div>
  );
}

// inline cloud-with-slash glyph for the offline-first-run
// empty state. Matches the visual vocabulary of the sidebar offline
// badge and the Welcome banner without pulling in an icon library.
function OfflineCalendarIcon() {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
      className="text-warning shrink-0 mt-0.5"
      aria-hidden="true"
    >
      <path d="M17.5 19H9a7 7 0 0 1-6.71-5" />
      <path d="M8.5 4.6A7 7 0 0 1 21 9v1a4 4 0 0 1 1.13 7.47" />
      <line x1="2" y1="2" x2="22" y2="22" />
    </svg>
  );
}
