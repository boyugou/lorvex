import { reminderNotificationKey } from './taskKey';

export type NotificationSendResult =
  | 'sent'
  | 'suppressed_permission'
  | 'suppressed_quiet_hours'
  | 'failed';

export function isQuietHoursWindow(
  nowMinutes: number,
  startMinutes: number,
  endMinutes: number,
): boolean {
  if (startMinutes === endMinutes) return false;
  if (startMinutes < endMinutes) {
    return nowMinutes >= startMinutes && nowMinutes < endMinutes;
  }
  return nowMinutes >= startMinutes || nowMinutes < endMinutes;
}

export function shouldFireDailyScheduledNotification(args: {
  lastFired: string;
  today: string;
  nowMinutes: number;
  targetMinutes: number;
}): boolean {
  return args.lastFired !== args.today && args.nowMinutes >= args.targetMinutes;
}

export function shouldFireWeeklyScheduledNotification(args: {
  lastFired: string;
  today: string;
  nowMinutes: number;
  targetMinutes: number;
  todayDayName: string;
  targetDayName: string;
}): boolean {
  return shouldFireDailyScheduledNotification(args)
    && args.todayDayName === args.targetDayName;
}

export function shouldMuteTaskNotification(
  listId: string | null | undefined,
  mutedListIds: ReadonlySet<string>,
): boolean {
  return typeof listId === 'string' && listId.length > 0 && mutedListIds.has(listId);
}

interface ReminderNotificationEntryLike {
  task: {
    list_id: string | null;
  };
  reminder: {
    id: string;
    reminder_at: string;
  };
}

export function selectReminderEntriesToNotify<T extends ReminderNotificationEntryLike>(
  entries: readonly T[],
  mutedListIds: ReadonlySet<string>,
  notifiedKeys: ReadonlySet<string>,
): T[] {
  return entries
    .filter(({ task }) => !shouldMuteTaskNotification(task.list_id, mutedListIds))
    .filter(({ reminder }) => !notifiedKeys.has(reminderNotificationKey(reminder)));
}

interface ReminderBadgeTaskLike {
  task: {
    list_id: string | null;
  };
}

export function countReminderBadgeEntries<T extends ReminderBadgeTaskLike>(
  entries: readonly T[],
  mutedListIds: ReadonlySet<string>,
): number {
  return entries.filter(({ task }) => !shouldMuteTaskNotification(task.list_id, mutedListIds)).length;
}
