import { QK, type QueryKeyHead } from './queryKeyHeads';
import type { DeviceStateKey } from '../preferences/keys';

export const QUERY_KEYS = {
  head: (head: QueryKeyHead) => [head] as const,
  overview: () => [QK.overview] as const,
  lists: () => [QK.lists] as const,
  list: (listId: string) => [QK.list, listId] as const,
  preference: (key: string) => [QK.preference, key] as const,
  preferenceRoot: () => [QK.preference] as const,
  currentFocus: () => [QK.currentFocus] as const,
  focusSchedule: () => [QK.focusSchedule] as const,
  allTasks: (showCompleted: boolean, showCancelled: boolean) =>
    [QK.allTasks, showCompleted, showCancelled] as const,
  task: (taskId: string) => [QK.task, taskId] as const,
  taskAttribution: (taskId: string) => [QK.taskAttribution, taskId] as const,
  tasksBlockedBy: (taskId: string) => [QK.tasksBlockedBy, taskId] as const,
  taskEventLinks: (taskId: string) => [QK.taskEventLinks, taskId] as const,
  taskProviderEventLinks: (taskId: string) => [QK.taskProviderEventLinks, taskId] as const,
  taskReminders: (taskId: string) => [QK.taskReminders, taskId] as const,
  calendarEvent: (eventId: string) => [QK.calendarEvent, eventId] as const,
  calendarEvents: (from: string, to: string) => [QK.calendarEvents, from, to] as const,
  calendarTasks: (from: string, to: string) => [QK.calendarTasks, from, to] as const,
  calendarSubscriptions: () => [QK.calendarSubscriptions] as const,
  todayEvents: (todayYmd: string) => [QK.todayEvents, todayYmd] as const,
  todayPoolTasks: () => [QK.todayPoolTasks] as const,
  todayOverdueTasks: () => [QK.todayOverdueTasks] as const,
  somedayTasks: () => [QK.somedayTasks] as const,
  recurringTasks: () => [QK.recurringTasks] as const,
  upcomingTasks: (todayYmd: string, days: number) => [QK.upcomingTasks, todayYmd, days] as const,
  upcomingEvents: (from: string, to: string) => [QK.upcomingEvents, from, to] as const,
  upcomingWeekTasks: (todayYmd: string, days: number) => [QK.upcomingWeekTasks, todayYmd, days] as const,
  search: (query: string) => [QK.search, query] as const,
  weeklyReview: (todayYmd?: string) =>
    todayYmd === undefined ? [QK.weeklyReview] as const : [QK.weeklyReview, todayYmd] as const,
  weeklyReviewUpcoming: (startYmd?: string, endYmd?: string) =>
    startYmd === undefined || endYmd === undefined
      ? [QK.weeklyReviewUpcoming] as const
      : [QK.weeklyReviewUpcoming, startYmd, endYmd] as const,
  weeklyReviewEvents: (startYmd: string, endYmd: string) => [QK.weeklyReviewEvents, startYmd, endYmd] as const,
  weeklyReviewHabits: (todayYmd: string) => [QK.weeklyReviewHabits, todayYmd] as const,
  dailyReviews: () => [QK.dailyReviews] as const,
  dailyReview: (todayYmd: string) => [QK.dailyReview, todayYmd] as const,
  dailyReviewEvents: (todayYmd: string) => [QK.dailyReviewEvents, todayYmd] as const,
  todaysHabits: (todayYmd: string) => [QK.todaysHabits, todayYmd] as const,
  habitsWithStats: (todayYmd: string) => [QK.habitsWithStats, todayYmd] as const,
  habitReminderPolicies: () => [QK.habitReminderPolicies] as const,
  aiMemory: () => [QK.aiMemory] as const,
  aiChangelog: (entryLimit?: number) =>
    entryLimit === undefined ? [QK.aiChangelog] as const : [QK.aiChangelog, entryLimit] as const,
  taskAiChangelog: (taskId: string, limit: number) => [QK.aiChangelog, 'task', taskId, limit] as const,
  memoryHistory: (memoryKey?: string) =>
    memoryKey === undefined ? [QK.memoryHistory] as const : [QK.memoryHistory, memoryKey] as const,
  deviceState: (key: DeviceStateKey) => [QK.deviceState, key] as const,
  unseenErrorLogCount: () => [QK.unseenErrorLogCount] as const,
  setupStatus: () => [QK.setupStatus] as const,
  dashboardLayout: () => [QK.dashboardLayout] as const,
  eventsUnifiedForLinkSearch: (from: string, to: string) => [QK.eventsUnifiedForLinkSearch, from, to] as const,
  allTags: () => [QK.allTags] as const,
  todayBootstrap: () => [QK.todayBootstrap] as const,
  savedQueries: (viewType?: string) =>
    viewType === undefined ? [QK.savedQueries] as const : [QK.savedQueries, viewType] as const,
  mcpServerStatus: () => [QK.mcpServerStatus] as const,
  syncStatus: (scope: string) => [QK.syncStatus, scope] as const,
  diagnosticsDeviceIds: () => [QK.diagnostics, 'device-ids'] as const,
  diagnosticsConflictLog: (timeWindow: string, sourceDeviceId: string | null) =>
    [QK.diagnostics, 'conflict-log', timeWindow, sourceDeviceId ?? 'all-devices'] as const,
  appVersion: () => [QK.appVersion] as const,
} as const;
