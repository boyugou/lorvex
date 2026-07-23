import { useCallback, useMemo, useState, type MouseEvent as ReactMouseEvent } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { useBulkActions } from '@/lib/tasks/useBulkActions';
import { usePreference } from '@/lib/query/usePreference';
import { invalidateAllQueries } from '@/lib/query/queryKeys';
import { STALE_LONG } from '@/lib/query/timing';
import { PREF_AI_BRIEFING_ENABLED } from '@/lib/preferences/keys';
import { formatPageTitle } from '@/lib/pageTitle';
import { useScrollRestore } from '@/lib/useScrollRestore';
import { useTaskListActions } from '@/lib/tasks/useTaskListActions';
import { useTaskListKeyboard } from '@/lib/tasks/useTaskListKeyboard';
import { useTaskSelection, type BulkAction } from '@/lib/tasks/useTaskSelection';
import { useI18n } from '@/lib/i18n';
import { PullToRefresh } from '../ui/PullToRefresh';
import { TodayEventsSection, useCollapsedSections } from './sections';
import { TodayFocusTopSection, TodayNonFocusSections } from './TodayDashboardSections';
import { TodayViewBulkBar } from './TodayViewBulkBar';
import { getSectionTaskIds } from './getSectionTaskIds';
import { TodayHeader } from './TodayHeader';
import { ErrorBanner } from './ErrorBanner';
import { TodayPoolSection } from './TodayPoolSection';
import { WelcomeView } from './WelcomeView';
import { AllClearView } from './AllClearView';
import { PickerOverlays } from '../ui/PickerOverlays';
import type { TodayViewContentProps } from './types';
import { TodayViewSkeleton } from '../ui/SkeletonShimmer';
import { KeyboardHintBar } from '../ui/KeyboardHintBar';
import type { Task } from '@/lib/ipc/tasks/models';
import {
  createBrowserTodayViewRefreshDelayTimerHost,
  mergeCanonicalOverdueSection,
  waitForTodayViewPullToRefreshFeedback,
} from './TodayViewContent.runtime';

const todayViewRefreshDelayTimerHost = createBrowserTodayViewRefreshDelayTimerHost();

export default function TodayViewContent({
  todayPoolTasks,
  greeting,
  hasPlanTasks,
  hasRecoverableTodayError,
  isAiLayout,
  isFirstRun,
  isTodayLoading,
  onNavigate,
  onSelectTask,
  onAddTask,
  overdueTasks,
  overview,
  plan,
  refetchFailedTodayQueries,
  focusSchedule,
  sections,
  somedayTasks,
  stats,
  t,
  today,
  todayIso,
  todayEvents,
  upcomingWeekTasks,
}: TodayViewContentProps): React.JSX.Element {
  const queryClient = useQueryClient();
  // pull `format` from the I18n hook directly because
  // TodayViewContentProps only carries `t`, but the selection-collapsed
  // toast needs the {count} interpolation that `format` provides.
  const { format: formatI18n } = useI18n();

  const handlePullToRefresh = useCallback(async () => {
    invalidateAllQueries(queryClient);
    // Give queries a moment to start refetching so the user sees fresh data
    await waitForTodayViewPullToRefreshFeedback({
      timerHost: todayViewRefreshDelayTimerHost,
    });
  }, [queryClient]);

  const { value: aiBriefingEnabled } = usePreference(
    PREF_AI_BRIEFING_ENABLED,
    (raw) => raw !== 'false',
    { staleTime: STALE_LONG },
  );

  const scroll = useScrollRestore('today-view');

  const focusSection = useMemo(
    () => sections.find((s) => s.type === 'focus'),
    [sections],
  );
  const nonFocusSections = useMemo(
    () => sections.filter((s) => s.type !== 'focus'),
    [sections],
  );
  const renderedNonFocusSections = useMemo(
    () => mergeCanonicalOverdueSection(nonFocusSections, overdueTasks.length),
    [nonFocusSections, overdueTasks.length],
  );

  // Collapse state — shared with DashboardSectionRenderer
  const collapsedSet = useCollapsedSections();

  // Flatten all visible task IDs in render order for keyboard navigation.
  // Skip tasks from collapsed sections so arrow keys don't land on hidden items.
  // Deduplicate IDs so keyboard navigation doesn't "stick" on a task that
  // appears in multiple sections (e.g., todayPoolTasks + overdue_alert).
  const allTaskIds = useMemo(() => {
    const seen = new Set<string>();
    const ids: string[] = [];
    const push = (id: string) => { if (!seen.has(id)) { seen.add(id); ids.push(id); } };
    if (focusSection && !collapsedSet.has(focusSection.type)) {
      for (const id of getSectionTaskIds(focusSection, plan, overview, overdueTasks, todayPoolTasks, somedayTasks, upcomingWeekTasks, todayIso)) push(id);
    }
    for (const task of todayPoolTasks) push(task.id);
    for (const section of renderedNonFocusSections) {
      if (collapsedSet.has(section.type)) continue;
      for (const id of getSectionTaskIds(section, plan, overview, overdueTasks, todayPoolTasks, somedayTasks, upcomingWeekTasks, todayIso)) push(id);
    }
    return ids;
  }, [focusSection, todayPoolTasks, renderedNonFocusSections, plan, overview, overdueTasks, somedayTasks, upcomingWeekTasks, todayIso, collapsedSet]);

  // Collect all reachable tasks (deduped by ID) for keyboard action lookup
  const allTasks = useMemo(() => {
    const seen = new Set<string>();
    const result: Task[] = [];
    const push = (task: Task) => {
      if (seen.has(task.id)) return;
      seen.add(task.id);
      result.push(task);
    };
    for (const task of todayPoolTasks) push(task);
    if (plan) for (const task of plan.tasks) push(task);
    if (overview) {
      for (const task of overview.top_by_priority ?? []) push(task);
      for (const task of overview.recently_completed ?? []) push(task);
    }
    for (const task of overdueTasks) push(task);
    for (const task of somedayTasks) push(task);
    for (const task of upcomingWeekTasks) push(task);
    return result;
  }, [todayPoolTasks, plan, overview, overdueTasks, somedayTasks, upcomingWeekTasks]);

  // --- Multi-select: selectable tasks exclude focus (drag-and-drop) and recently_completed ---
  const dayContext = useConfiguredDayContext();
  const selectableTaskIds = useMemo(() => {
    const ids = new Set<string>();
    // Today pool tasks
    for (const task of todayPoolTasks) ids.add(task.id);
    // Non-focus dashboard sections (overdue, priority, someday, upcoming)
    for (const section of renderedNonFocusSections) {
      if (section.type === 'recently_completed') continue;
      const sectionIds = getSectionTaskIds(section, plan, overview, overdueTasks, todayPoolTasks, somedayTasks, upcomingWeekTasks, todayIso);
      for (const id of sectionIds) ids.add(id);
    }
    return ids;
  }, [todayPoolTasks, renderedNonFocusSections, plan, overview, overdueTasks, somedayTasks, upcomingWeekTasks, todayIso]);

  const [bulkAction, setBulkAction] = useState<BulkAction>(null);
  const {
    selectionMode,
    selectedIds,
    selectAll,
    invertSelection,
    toggleTaskSelected,
    setSelectionModeEnabled,
    setSelectedIds,
    clearSelection,
    handleClickWithModifiers,
    handleKeyboardExtend,
  } = useTaskSelection(selectableTaskIds, bulkAction, {
    // localized "selection collapsed" toast strings.
    onSelectionCollapsedMessage: (count) =>
      formatI18n('allTasks.selectionCollapsed', { count: String(count) }),
    onSelectionCollapsedUndoLabel: () => t('allTasks.selectionCollapsedRestore'),
  });
  const bulk = useBulkActions({
    tasks: allTasks.filter((task) => selectableTaskIds.has(task.id)),
    selectedIds,
    setSelectedIds,
    deferDateYmd: dayContext.tomorrowYmd,
    externalBulkAction: bulkAction,
    externalSetBulkAction: setBulkAction,
  });

  const onExtendSelection = useCallback(
    (direction: 'up' | 'down', focusedId: string | null) =>
      handleKeyboardExtend(direction, allTaskIds, focusedId),
    [handleKeyboardExtend, allTaskIds],
  );
  const onClickWithModifiers = useCallback(
    (id: string, event: ReactMouseEvent<HTMLButtonElement>) =>
      handleClickWithModifiers(id, event, allTaskIds, null),
    [handleClickWithModifiers, allTaskIds],
  );

  const baseActions = useTaskListActions(allTasks);
  const actions = {
    ...baseActions,
    onToggleSelected: toggleTaskSelected,
    setSelectionModeEnabled,
    selectionModeActive: selectionMode,
    onExtendSelection,
    onSelectAll: selectAll,
    onClearSelection: clearSelection,
    hasSelection: selectedIds.size > 0,
  };
  const keyboard = useTaskListKeyboard({
    taskIds: allTaskIds,
    onSelect: onSelectTask,
    actions,
    disabled: isTodayLoading,
  });

  const showEmptyState =
    !isTodayLoading &&
    !hasPlanTasks &&
    overview != null &&
    (!overview.top_by_priority || overview.top_by_priority.length === 0) &&
    sections.length === 0 &&
    renderedNonFocusSections.length === 0 &&
    !hasRecoverableTodayError;

  return (
    <>
      <title>{formatPageTitle(t('nav.today'))}</title>

      <TodayHeader
        greeting={greeting}
        today={today}
        isAiLayout={isAiLayout}
        stats={stats}
        todayPoolTasks={todayPoolTasks}
        overdueTasks={overdueTasks}
        plan={plan}
        todayEvents={todayEvents}
        t={t}
        hasSelectableTasks={selectableTaskIds.size > 0}
        selectionMode={selectionMode}
        bulkBusy={bulk.bulkAction !== null}
        onToggleSelectionMode={() => setSelectionModeEnabled(!selectionMode)}
        onSelectTask={onSelectTask}
      />

      {selectionMode && (
        <TodayViewBulkBar
          selectedCount={bulk.selectedCount}
          bulkAction={bulk.bulkAction}
          onSelectAll={selectAll}
          onInvertSelection={invertSelection}
          onClearSelection={() => setSelectedIds(new Set())}
          onComplete={() => void bulk.handleBulkComplete()}
          onDefer={() => void bulk.handleBulkDefer()}
          onCancel={() => void bulk.handleBulkCancel()}
          onMove={(listId) => void bulk.handleBulkMove(listId)}
          onFocus={() => void bulk.handleBulkFocus().then(() => setSelectionModeEnabled(false))}
        />
      )}

      <PullToRefresh onRefresh={handlePullToRefresh}>
        <div ref={scroll.ref} onScroll={scroll.onScroll} className="flex-1 overflow-y-auto overscroll-contain px-4 sm:px-8 pb-8 space-y-6">
          {hasRecoverableTodayError && (
            <ErrorBanner t={t} onRetry={refetchFailedTodayQueries} />
          )}

          {focusSection && (
            <TodayFocusTopSection
              focusSection={focusSection}
              plan={plan}
              overview={overview}
              focusSchedule={focusSchedule}
              somedayTasks={somedayTasks}
              upcomingWeekTasks={upcomingWeekTasks}
              overdueTasks={overdueTasks}
              todayPoolTasks={todayPoolTasks}
              onSelectTask={onSelectTask}
              focusedTaskId={keyboard.focusedId}
              aiBriefingEnabled={aiBriefingEnabled}
            />
          )}

          {todayPoolTasks.length > 0 && (
            <TodayPoolSection
              tasks={todayPoolTasks}
              focusedTaskId={keyboard.focusedId}
              onSelectTask={onSelectTask}
              t={t}
              selectionMode={selectionMode}
              selectedIds={selectedIds}
              bulkBusy={bulk.bulkAction !== null}
              onToggleSelected={toggleTaskSelected}
              onClickWithModifiers={onClickWithModifiers}
            />
          )}

          {todayEvents.length > 0 && <TodayEventsSection events={todayEvents} />}

          <TodayNonFocusSections
            sections={renderedNonFocusSections}
            plan={plan}
            overview={overview}
            focusSchedule={focusSchedule}
            somedayTasks={somedayTasks}
            upcomingWeekTasks={upcomingWeekTasks}
            overdueTasks={overdueTasks}
            todayPoolTasks={todayPoolTasks}
            onSelectTask={onSelectTask}
            focusedTaskId={keyboard.focusedId}
            aiBriefingEnabled={aiBriefingEnabled}
            selectionMode={selectionMode}
            selectedIds={selectedIds}
            bulkBusy={bulk.bulkAction !== null}
            onToggleSelected={toggleTaskSelected}
            onClickWithModifiers={onClickWithModifiers}
          />

          {isTodayLoading
            && !focusSection
            && todayPoolTasks.length === 0
            && todayEvents.length === 0
            && renderedNonFocusSections.length === 0
            && <TodayViewSkeleton />}

          {showEmptyState && (
            isFirstRun
              ? <WelcomeView onNavigate={onNavigate} t={t} />
              : <AllClearView onNavigate={onNavigate} onAddTask={onAddTask} t={t} />
          )}
          <KeyboardHintBar visible={keyboard.showKeyboardHints} />
        </div>
      </PullToRefresh>

      <PickerOverlays
        tasks={allTasks}
        movePickerTaskId={baseActions.movePickerTaskId}
        closeMovePickerAction={baseActions.closeMovePickerAction}
        recurrencePickerTaskId={baseActions.recurrencePickerTaskId}
        closeRecurrencePickerAction={baseActions.closeRecurrencePickerAction}
        dueDatePickerTaskId={baseActions.dueDatePickerTaskId}
        closeDueDatePickerAction={baseActions.closeDueDatePickerAction}
        durationPickerTaskId={baseActions.durationPickerTaskId}
        closeDurationPickerAction={baseActions.closeDurationPickerAction}
      />
    </>
  );
}
