import { QK } from '../queryKeyHeads';

// ---------------------------------------------------------------------------
// Query key groups
// ---------------------------------------------------------------------------

export const TODAY_SURFACE_QUERY_KEY_HEADS = [
  QK.overview,
  QK.currentFocus,
  QK.focusSchedule,
  QK.todayEvents,
  QK.todayPoolTasks,
  QK.todayOverdueTasks,
  // the bootstrap query (`get_today_bootstrap`)
  // pre-loads every leaf head above into the cache via
  // `setQueryData` in `useMainWindowQueries`. Without listing
  // `todayBootstrap` itself in the broadcast set, an external write
  // would invalidate the leaves but leave the bootstrap snapshot
  // intact at its 60 s `refetchInterval`; the next bootstrap tick
  // would then re-seed the leaves with the pre-mutation data,
  // silently rolling back the user's view (and any optimistic
  // mutation cache write — see `useFocusReorderActions`). Adding
  // the bootstrap head here makes a peer/MCP write trigger a single
  // bootstrap refetch alongside leaf invalidations; `setQueryData`
  // does not itself invalidate, so the cycle terminates after one
  // refetch with no risk of an invalidation loop.
  QK.todayBootstrap,
] as const;

// Frequently refreshed global task listings shown across major surfaces.
export const TASK_INDEX_QUERY_KEY_HEADS = [
  QK.lists,
  QK.allTasks,
] as const;

// Shared broader task collection views used by maintenance-heavy mutation flows.
export const TASK_COLLECTION_QUERY_KEY_HEADS = [
  ...TASK_INDEX_QUERY_KEY_HEADS,
  QK.list,
  QK.somedayTasks,
  QK.recurringTasks,
  QK.upcomingTasks,
  QK.upcomingWeekTasks,
  QK.weeklyReview,
  QK.weeklyReviewUpcoming,
  QK.calendarTasks,
] as const;

export const TASK_DETAIL_QUERY_KEY_HEADS = [
  QK.task,
  QK.taskAttribution,
] as const;

export const DATA_IMPORT_QUERY_KEY_HEADS = [
  ...TODAY_SURFACE_QUERY_KEY_HEADS,
  ...TASK_COLLECTION_QUERY_KEY_HEADS,
  ...TASK_DETAIL_QUERY_KEY_HEADS,
  QK.dashboardLayout,
  QK.aiMemory,
  QK.preference,
  QK.calendarEvents,
  QK.dailyReviews,
  QK.todaysHabits,
  QK.habitsWithStats,
  QK.aiChangelog,
  QK.taskReminders,
  QK.habitReminderPolicies,
  QK.setupStatus,
] as const;

// Keep high-traffic key heads in one place to prevent drift (`search` vs `search-tasks`).
// QK.task and QK.weeklyReview* were missing here, so any
// mutation that went through invalidateTaskMutationQueries (e.g. the
// "Reschedule overdue" batch action in useDashboardSectionActions)
// left the task-detail panel and Weekly Review panel stale until
// unmount or broadcast round-trip.
export const TASK_MUTATION_QUERY_KEY_HEADS = [
  ...TASK_INDEX_QUERY_KEY_HEADS,
  QK.somedayTasks,
  QK.recurringTasks,
  QK.upcomingTasks,
  QK.upcomingWeekTasks,
  QK.calendarTasks,
  QK.search,
  QK.task,
  QK.taskAttribution,
  QK.weeklyReview,
  QK.weeklyReviewUpcoming,
] as const;

// Keys invalidated on every external mutation broadcast (MCP writes, sync).
// MCP tools can write tasks, lists, calendar events, AI memory, and changelog,
// so this set covers all entity views that could become stale.
export const EXTERNAL_MUTATION_QUERY_KEY_HEADS = [
  ...TODAY_SURFACE_QUERY_KEY_HEADS,
  ...TASK_COLLECTION_QUERY_KEY_HEADS,
  ...TASK_DETAIL_QUERY_KEY_HEADS,
  QK.calendarEvents,
  QK.calendarEvent,
  QK.calendarSubscriptions,
  QK.aiMemory,
  QK.aiChangelog,
  QK.taskReminders,
  QK.dailyReviews,
  QK.dailyReview,
  QK.todaysHabits,
  QK.habitsWithStats,
  QK.upcomingWeekTasks,
  QK.upcomingEvents,
  QK.taskEventLinks,
  QK.taskProviderEventLinks,
  QK.dashboardLayout,
  // the Weekly Review panels were entirely invisible to
  // external-mutation invalidation. Any MCP-side edit to a task, event,
  // or habit left the open Weekly Review view stale until the user
  // unmounted/remounted it. Add the three WR panel keys here + in the
  // per-entity maps below so every mutation type refreshes them.
  QK.weeklyReview,
  QK.weeklyReviewUpcoming,
  QK.weeklyReviewEvents,
  QK.weeklyReviewHabits,
  // task-detail event-link search caches ±7/+30-day
  // events with STALE_LONG and had no invalidation path. A sync-side
  // event create/delete left the popover showing events that no
  // longer existed (or missing fresh ones) until unmount.
  QK.eventsUnifiedForLinkSearch,
] as const;

// invalidateTodayTaskIndexQueries = today-surface + task-index
export const TODAY_TASK_INDEX_QUERY_KEY_HEADS = [
  ...TODAY_SURFACE_QUERY_KEY_HEADS,
  ...TASK_INDEX_QUERY_KEY_HEADS,
] as const;

export const CALENDAR_MUTATION_QUERY_KEY_HEADS = [
  QK.calendarEvents,
  QK.calendarEvent,
  QK.todayEvents,
  QK.dailyReviewEvents,
  QK.upcomingEvents,
  QK.calendarTasks,
  QK.weeklyReview,
  QK.weeklyReviewEvents,
  QK.taskEventLinks,
  QK.taskProviderEventLinks,
  QK.eventsUnifiedForLinkSearch,
] as const;

export const CALENDAR_SUBSCRIPTION_QUERY_KEY_HEADS = [
  QK.calendarSubscriptions,
  ...CALENDAR_MUTATION_QUERY_KEY_HEADS,
] as const;

export const CALENDAR_VIEW_QUERY_KEY_HEADS = [
  QK.calendarTasks,
  QK.calendarEvents,
  ...TODAY_SURFACE_QUERY_KEY_HEADS,
] as const;

export const FOCUS_SCHEDULE_QUERY_KEY_HEADS = [
  QK.focusSchedule,
] as const;

export const PLANNING_FOCUS_QUERY_KEY_HEADS = [
  QK.focusSchedule,
  QK.currentFocus,
  QK.overview,
] as const;

export const TASK_STATUS_CHANGE_QUERY_KEY_HEADS = [
  ...TODAY_SURFACE_QUERY_KEY_HEADS,
  QK.allTasks,
  QK.somedayTasks,
  QK.list,
  QK.task,
  QK.taskAttribution,
  QK.upcomingTasks,
  QK.upcomingWeekTasks,
  QK.calendarTasks,
  QK.weeklyReview,
  QK.weeklyReviewUpcoming,
  QK.search,
  QK.tasksBlockedBy,
] as const;

// Pre-built set for focus-mode task writes (today-surface + task detail + all-tasks + someday + review)
export const FOCUS_TASK_QUERY_KEY_HEADS = [
  ...TODAY_SURFACE_QUERY_KEY_HEADS,
  QK.allTasks,
  QK.somedayTasks,
  QK.weeklyReview,
] as const;

export const TASK_DEPENDENCY_QUERY_KEY_HEADS = [
  QK.allTasks,
  QK.task,
  QK.tasksBlockedBy,
] as const;

export const TASK_DEPENDENCY_WRITE_QUERY_KEY_HEADS = [
  ...TASK_DEPENDENCY_QUERY_KEY_HEADS,
  ...TASK_DETAIL_QUERY_KEY_HEADS,
  ...TODAY_SURFACE_QUERY_KEY_HEADS,
] as const;

export const TASK_DETAIL_WRITE_EXTRA_QUERY_KEY_HEADS = [
  QK.task,
  QK.taskAttribution,
  QK.calendarTasks,
  QK.somedayTasks,
  QK.weeklyReview,
  QK.dashboardLayout,
] as const;

// `invalidateHabitQueries` already covered habit-with-stats,
// today's habits, and Weekly Review's habit panel. Co-locate the set
// here so future habit views drift through the registry instead of
// the helper body.
export const HABIT_WRITE_QUERY_KEY_HEADS = [
  QK.habitsWithStats,
  QK.todaysHabits,
  QK.weeklyReview,
  QK.weeklyReviewHabits,
] as const;

// Daily review write — the helper added the entire today-surface set
// after #2x discovered the local save left the TodayView review-
// complete chip stale until the data-changed broadcast caught up.
export const DAILY_REVIEW_WRITE_QUERY_KEY_HEADS = [
  QK.dailyReviews,
  QK.dailyReview,
  ...TODAY_SURFACE_QUERY_KEY_HEADS,
] as const;
