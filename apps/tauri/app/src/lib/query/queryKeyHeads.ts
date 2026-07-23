// ---------------------------------------------------------------------------
// Canonical query key head constants
// ---------------------------------------------------------------------------
// Query key factories MUST reference these constants instead of raw string
// literals. This prevents typos and makes key usage grep-able.

export const QK = {
  overview: 'overview',
  lists: 'lists',
  list: 'list',
  preference: 'preference',
  currentFocus: 'current-focus',
  focusSchedule: 'focus-schedule',
  allTasks: 'all-tasks',
  task: 'task',
  taskAttribution: 'task-attribution',
  tasksBlockedBy: 'tasks-blocked-by',
  taskEventLinks: 'task-event-links',
  taskProviderEventLinks: 'task-provider-event-links',
  taskReminders: 'task-reminders',
  calendarEvent: 'calendar-event',
  calendarEvents: 'calendar-events',
  calendarTasks: 'calendar-tasks',
  calendarSubscriptions: 'calendar-subscriptions',
  todayEvents: 'today-events',
  todayPoolTasks: 'today-pool-tasks',
  todayOverdueTasks: 'today-overdue-tasks',
  somedayTasks: 'someday-tasks',
  recurringTasks: 'recurring-tasks',
  upcomingTasks: 'upcoming-tasks',
  upcomingEvents: 'upcoming-events',
  upcomingWeekTasks: 'upcoming-week-tasks',
  search: 'search',
  weeklyReview: 'weekly-review',
  weeklyReviewUpcoming: 'weekly-review-upcoming',
  weeklyReviewEvents: 'weekly-review-events',
  weeklyReviewHabits: 'weekly-review-habits',
  dailyReviews: 'daily-reviews',
  dailyReview: 'daily-review',
  dailyReviewEvents: 'daily-review-events',
  todaysHabits: 'todays-habits',
  habitsWithStats: 'habits-with-stats',
  habitReminderPolicies: 'habit-reminder-policies',
  aiMemory: 'ai-memory',
  aiChangelog: 'ai-changelog',
  memoryHistory: 'memory-history',
  deviceState: 'device-state',
  unseenErrorLogCount: 'unseen-error-log-count',
  setupStatus: 'setup-status',
  dashboardLayout: 'dashboard-layout',
  eventsUnifiedForLinkSearch: 'events-unified-for-link-search',
  allTags: 'all-tags',
  todayBootstrap: 'today-bootstrap',
  savedQueries: 'saved-queries',
  mcpServerStatus: 'mcp-server-status',
  syncStatus: 'sync-status',
  diagnostics: 'diagnostics',
  // App version comes from a one-shot Tauri IPC at mount time. Promoting it
  // to TanStack with `staleTime: Infinity` makes the IPC promise cancellable
  // on unmount and dedupes the call across re-renders / re-mounts.
  appVersion: 'app-version',
} as const;

export type QueryKeyHead = (typeof QK)[keyof typeof QK];
export const QUERY_KEY_HEADS = Object.freeze(Object.values(QK)) as readonly QueryKeyHead[];
export const QUERY_KEY_HEAD_SET = new Set<string>(QUERY_KEY_HEADS);

// Guard against query-key collisions at module-load time. Two entries in `QK`
// pointing at the same string silently merge their invalidation domains.
{
  const seen = new Map<string, string>();
  for (const [keyName, value] of Object.entries(QK)) {
    const prior = seen.get(value);
    if (prior !== undefined) {
      throw new Error(
        `QK collision: '${prior}' and '${keyName}' both map to "${value}". ` +
          'Query key heads must be unique — see app/src/lib/query/queryKeyHeads.ts.',
      );
    }
    seen.set(value, keyName);
  }
  if (seen.size !== QUERY_KEY_HEADS.length) {
    throw new Error(`QK internal: expected ${QUERY_KEY_HEADS.length} unique heads, got ${seen.size}`);
  }
}
