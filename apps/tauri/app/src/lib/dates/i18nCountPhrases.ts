import {
  formatPluralTranslation,
  formatTranslation,
  hasLocaleTranslation,
  type PluralTranslationKeys,
  type TranslationKey,
} from '../../locales';

type Translator = (key: TranslationKey) => string;

const TASK_COUNT_KEYS = {
  zero: 'common.taskCount.zero',
  one: 'common.taskCount.one',
  two: 'common.taskCount.two',
  few: 'common.taskCount.few',
  many: 'common.taskCount.many',
  other: 'common.taskCount.other',
} satisfies PluralTranslationKeys;

const EVENT_COUNT_KEYS = {
  zero: 'calendar.eventCount.zero',
  one: 'calendar.eventCount.one',
  two: 'calendar.eventCount.two',
  few: 'calendar.eventCount.few',
  many: 'calendar.eventCount.many',
  other: 'calendar.eventCount.other',
} satisfies PluralTranslationKeys;

const OPEN_TASK_COUNT_KEYS = {
  zero: 'calendar.openTaskCount.zero',
  one: 'calendar.openTaskCount.one',
  two: 'calendar.openTaskCount.two',
  few: 'calendar.openTaskCount.few',
  many: 'calendar.openTaskCount.many',
  other: 'calendar.openTaskCount.other',
} satisfies PluralTranslationKeys;

const TODAY_TASK_COUNT_KEYS = {
  zero: 'today.todayTaskCount.zero',
  one: 'today.todayTaskCount.one',
  two: 'today.todayTaskCount.two',
  few: 'today.todayTaskCount.few',
  many: 'today.todayTaskCount.many',
  other: 'today.todayTaskCount.other',
} satisfies PluralTranslationKeys;

const OVERDUE_COUNT_KEYS = {
  zero: 'today.overdueCount.zero',
  one: 'today.overdueCount.one',
  two: 'today.overdueCount.two',
  few: 'today.overdueCount.few',
  many: 'today.overdueCount.many',
  other: 'today.overdueCount.other',
} satisfies PluralTranslationKeys;

const REVIEW_COMPLETED_COUNT_KEYS = {
  zero: 'review.completedTaskCount.zero',
  one: 'review.completedTaskCount.one',
  two: 'review.completedTaskCount.two',
  few: 'review.completedTaskCount.few',
  many: 'review.completedTaskCount.many',
  other: 'review.completedTaskCount.other',
} satisfies PluralTranslationKeys;

const REVIEW_TASK_COUNT_KEYS = {
  zero: 'review.taskCount.zero',
  one: 'review.taskCount.one',
  two: 'review.taskCount.two',
  few: 'review.taskCount.few',
  many: 'review.taskCount.many',
  other: 'review.taskCount.other',
} satisfies PluralTranslationKeys;

const STREAK_COUNT_KEYS = {
  zero: 'dailyReview.streakCount.zero',
  one: 'dailyReview.streakCount.one',
  two: 'dailyReview.streakCount.two',
  few: 'dailyReview.streakCount.few',
  many: 'dailyReview.streakCount.many',
  other: 'dailyReview.streakCount.other',
} satisfies PluralTranslationKeys;

const FOCUS_TASK_COUNT_KEYS = {
  zero: 'notifications.focusTaskCount.zero',
  one: 'notifications.focusTaskCount.one',
  two: 'notifications.focusTaskCount.two',
  few: 'notifications.focusTaskCount.few',
  many: 'notifications.focusTaskCount.many',
  other: 'notifications.focusTaskCount.other',
} satisfies PluralTranslationKeys;

const NOTIFICATION_OVERDUE_COUNT_KEYS = {
  zero: 'notifications.overdueTaskCount.zero',
  one: 'notifications.overdueTaskCount.one',
  two: 'notifications.overdueTaskCount.two',
  few: 'notifications.overdueTaskCount.few',
  many: 'notifications.overdueTaskCount.many',
  other: 'notifications.overdueTaskCount.other',
} satisfies PluralTranslationKeys;

const DUE_SOON_COUNT_KEYS = {
  zero: 'notifications.dueSoonTaskCount.zero',
  one: 'notifications.dueSoonTaskCount.one',
  two: 'notifications.dueSoonTaskCount.two',
  few: 'notifications.dueSoonTaskCount.few',
  many: 'notifications.dueSoonTaskCount.many',
  other: 'notifications.dueSoonTaskCount.other',
} satisfies PluralTranslationKeys;

const LIST_OPEN_TASK_COUNT_KEYS = {
  zero: 'list.openTaskCount.zero',
  one: 'list.openTaskCount.one',
  two: 'list.openTaskCount.two',
  few: 'list.openTaskCount.few',
  many: 'list.openTaskCount.many',
  other: 'list.openTaskCount.other',
} satisfies PluralTranslationKeys;

const LIST_RECENTLY_COMPLETED_TASK_COUNT_KEYS = {
  zero: 'list.recentlyCompletedTaskCount.zero',
  one: 'list.recentlyCompletedTaskCount.one',
  two: 'list.recentlyCompletedTaskCount.two',
  few: 'list.recentlyCompletedTaskCount.few',
  many: 'list.recentlyCompletedTaskCount.many',
  other: 'list.recentlyCompletedTaskCount.other',
} satisfies PluralTranslationKeys;

const DEPENDENCY_BLOCKED_TASK_COUNT_KEYS = {
  zero: 'deps.blockedTaskCount.zero',
  one: 'deps.blockedTaskCount.one',
  two: 'deps.blockedTaskCount.two',
  few: 'deps.blockedTaskCount.few',
  many: 'deps.blockedTaskCount.many',
  other: 'deps.blockedTaskCount.other',
} satisfies PluralTranslationKeys;

const DEPENDENCY_READY_TASK_COUNT_KEYS = {
  zero: 'deps.readyTaskCount.zero',
  one: 'deps.readyTaskCount.one',
  two: 'deps.readyTaskCount.two',
  few: 'deps.readyTaskCount.few',
  many: 'deps.readyTaskCount.many',
  other: 'deps.readyTaskCount.other',
} satisfies PluralTranslationKeys;

const DEPENDENCY_CYCLIC_TASK_COUNT_KEYS = {
  zero: 'deps.cyclicTaskCount.zero',
  one: 'deps.cyclicTaskCount.one',
  two: 'deps.cyclicTaskCount.two',
  few: 'deps.cyclicTaskCount.few',
  many: 'deps.cyclicTaskCount.many',
  other: 'deps.cyclicTaskCount.other',
} satisfies PluralTranslationKeys;

const DEPENDENCY_WITH_DEPS_TASK_COUNT_KEYS = {
  zero: 'deps.tasksWithDepsCount.zero',
  one: 'deps.tasksWithDepsCount.one',
  two: 'deps.tasksWithDepsCount.two',
  few: 'deps.tasksWithDepsCount.few',
  many: 'deps.tasksWithDepsCount.many',
  other: 'deps.tasksWithDepsCount.other',
} satisfies PluralTranslationKeys;

const POPOVER_TASKS_IN_PLAN_COUNT_KEYS = {
  zero: 'popover.tasksInPlanCount.zero',
  one: 'popover.tasksInPlanCount.one',
  two: 'popover.tasksInPlanCount.two',
  few: 'popover.tasksInPlanCount.few',
  many: 'popover.tasksInPlanCount.many',
  other: 'popover.tasksInPlanCount.other',
} satisfies PluralTranslationKeys;

const SELECTED_TASK_COUNT_KEYS = {
  zero: 'allTasks.selectedTaskCount.zero',
  one: 'allTasks.selectedTaskCount.one',
  two: 'allTasks.selectedTaskCount.two',
  few: 'allTasks.selectedTaskCount.few',
  many: 'allTasks.selectedTaskCount.many',
  other: 'allTasks.selectedTaskCount.other',
} satisfies PluralTranslationKeys;

export function formatTaskCountLabel(locale: string, count: number, t: Translator): string {
  return formatPluralTranslation(locale, count, TASK_COUNT_KEYS, {}, {
    fallback: (formattedCount) => `${formattedCount} ${count === 1 ? t('common.task') : t('common.tasks')}`,
  });
}

export function formatReviewTaskCountLabel(locale: string, count: number, t: Translator): string {
  return formatPluralTranslation(locale, count, REVIEW_TASK_COUNT_KEYS, {}, {
    fallback: (formattedCount) => `${formattedCount} ${count === 1 ? t('review.task') : t('review.tasks')}`,
  });
}

export function formatEventCountLabel(locale: string, count: number, t: Translator): string {
  return formatPluralTranslation(locale, count, EVENT_COUNT_KEYS, {}, {
    fallback: (formattedCount) => `${formattedCount} ${count === 1 ? t('calendar.event') : t('calendar.events')}`,
  });
}

export function formatOpenTaskCountLabel(locale: string, count: number, t: Translator): string {
  return formatPluralTranslation(locale, count, OPEN_TASK_COUNT_KEYS, {}, {
    fallback: () => formatTaskCountLabel(locale, count, t),
  });
}

export function formatTodayTaskCountLabel(locale: string, count: number, _t: Translator): string {
  return formatPluralTranslation(locale, count, TODAY_TASK_COUNT_KEYS);
}

export function formatOverdueTaskCountLabel(locale: string, count: number, t: Translator): string {
  return formatPluralTranslation(locale, count, OVERDUE_COUNT_KEYS, {}, {
    fallback: count !== 1 && hasLocaleTranslation(locale, 'today.overdueTasksLabel')
      ? (formattedCount) => `${formattedCount} ${t('today.overdueTasksLabel')}`
      : () => formatPluralTranslation(locale, count, NOTIFICATION_OVERDUE_COUNT_KEYS),
  });
}

export function formatReviewCompletedTaskCountLabel(locale: string, count: number, t: Translator): string {
  return formatPluralTranslation(locale, count, REVIEW_COMPLETED_COUNT_KEYS, {}, {
    fallback: () => `${t('review.completed')} · ${formatReviewTaskCountLabel(locale, count, t)}`,
  });
}

export function formatDailyReviewStreakCountLabel(locale: string, count: number, t: Translator): string {
  return formatPluralTranslation(locale, count, STREAK_COUNT_KEYS, {}, {
    fallback: (formattedCount) => `${formattedCount} ${count === 1 ? t('dailyReview.streakDay') : t('dailyReview.streakDays')}`,
  });
}

export function formatNotificationFocusTaskCountLabel(locale: string, count: number, _t: Translator): string {
  return formatPluralTranslation(locale, count, FOCUS_TASK_COUNT_KEYS);
}

export function formatNotificationOverdueTaskCountLabel(locale: string, count: number, t: Translator): string {
  return formatPluralTranslation(locale, count, NOTIFICATION_OVERDUE_COUNT_KEYS, {}, {
    fallback: count !== 1 && hasLocaleTranslation(locale, 'today.overdueTasksLabel')
      ? (formattedCount) => `${formattedCount} ${t('today.overdueTasksLabel')}`
      : undefined,
  });
}

export function formatNotificationDueSoonTaskCountLabel(locale: string, count: number, _t: Translator): string {
  return formatPluralTranslation(locale, count, DUE_SOON_COUNT_KEYS);
}

export function formatListOpenTaskCountLabel(locale: string, count: number, _t: Translator): string {
  return formatPluralTranslation(locale, count, LIST_OPEN_TASK_COUNT_KEYS);
}

export function formatListRecentlyCompletedTaskCountLabel(locale: string, count: number, _t: Translator): string {
  return formatPluralTranslation(locale, count, LIST_RECENTLY_COMPLETED_TASK_COUNT_KEYS);
}

export function formatDependencyBlockedTaskCountLabel(locale: string, count: number, _t: Translator): string {
  return formatPluralTranslation(locale, count, DEPENDENCY_BLOCKED_TASK_COUNT_KEYS);
}

export function formatDependencyReadyTaskCountLabel(locale: string, count: number, _t: Translator): string {
  return formatPluralTranslation(locale, count, DEPENDENCY_READY_TASK_COUNT_KEYS);
}

export function formatDependencyCyclicTaskCountLabel(locale: string, count: number, _t: Translator): string {
  return formatPluralTranslation(locale, count, DEPENDENCY_CYCLIC_TASK_COUNT_KEYS);
}

export function formatDependencyTasksWithDepsCountLabel(locale: string, count: number, _t: Translator): string {
  return formatPluralTranslation(locale, count, DEPENDENCY_WITH_DEPS_TASK_COUNT_KEYS);
}

export function formatPopoverTasksInPlanCountLabel(locale: string, count: number, _t: Translator): string {
  return formatPluralTranslation(locale, count, POPOVER_TASKS_IN_PLAN_COUNT_KEYS);
}

export function formatSelectedTaskCountLabel(locale: string, count: number, _t: Translator): string {
  return formatPluralTranslation(locale, count, SELECTED_TASK_COUNT_KEYS);
}

export function formatCalendarDayPanelSummary(
  locale: string,
  eventCount: number,
  openTaskCount: number,
  t: Translator,
): string {
  const eventCountLabel = formatEventCountLabel(locale, eventCount, t);
  const openTaskCountLabel = formatOpenTaskCountLabel(locale, openTaskCount, t);
  const fallback = `${eventCountLabel}, ${openTaskCountLabel}`;
  if (!hasLocaleTranslation(locale, 'calendar.dayPanelSummary')) return fallback;
  return formatTranslation(locale, 'calendar.dayPanelSummary', { eventCountLabel, openTaskCountLabel });
}

export function formatBulkCompletedMessage(locale: string, count: number, t: Translator): string {
  const countLabel = formatTaskCountLabel(locale, count, t);
  if (!hasLocaleTranslation(locale, 'allTasks.bulkCompletedCount')) {
    return `${t('allTasks.bulkCompleted')} ${countLabel}`;
  }
  return formatTranslation(locale, 'allTasks.bulkCompletedCount', { countLabel });
}

export function formatBulkDeferredMessage(locale: string, count: number, t: Translator): string {
  const countLabel = formatTaskCountLabel(locale, count, t);
  if (!hasLocaleTranslation(locale, 'allTasks.bulkDeferredCount')) {
    return `${t('allTasks.bulkDeferred')} ${countLabel}`;
  }
  return formatTranslation(locale, 'allTasks.bulkDeferredCount', { countLabel });
}

export function formatBulkCancelledMessage(locale: string, count: number, t: Translator): string {
  const countLabel = formatTaskCountLabel(locale, count, t);
  if (!hasLocaleTranslation(locale, 'allTasks.bulkCancelledCount')) {
    return `${t('allTasks.bulkCancelled')} ${countLabel}`;
  }
  return formatTranslation(locale, 'allTasks.bulkCancelledCount', { countLabel });
}

export function formatBulkMovedMessage(locale: string, count: number, t: Translator): string {
  const countLabel = formatTaskCountLabel(locale, count, t);
  if (!hasLocaleTranslation(locale, 'allTasks.bulkMovedCount')) {
    return `${t('allTasks.bulkMoved')} ${countLabel}`;
  }
  return formatTranslation(locale, 'allTasks.bulkMovedCount', { countLabel });
}

export function formatBulkFocusedMessage(locale: string, count: number, t: Translator): string {
  const countLabel = formatTaskCountLabel(locale, count, t);
  if (!hasLocaleTranslation(locale, 'allTasks.bulkFocusedCount')) {
    return `${t('allTasks.bulkFocused')} ${countLabel}`;
  }
  return formatTranslation(locale, 'allTasks.bulkFocusedCount', { countLabel });
}
