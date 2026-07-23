import type { TranslationKey } from '@/locales';
import { isPlainRecord as isRecord } from '@/lib/objectGuards';

type Translator = (key: TranslationKey) => string;

interface NotificationActionPayload {
  actionTypeId?: string;
  action?: string | undefined;
  extra?: Record<string, unknown>;
}

export interface TaskReminderActionType {
  id: 'task-reminder';
  actions: [
    {
      id: 'complete';
      title: string;
      foreground: false;
    },
    {
      id: 'snooze';
      title: string;
      foreground: false;
    },
  ];
}

export function buildTaskReminderActionType(t: Translator): TaskReminderActionType {
  return {
    id: 'task-reminder',
    actions: [
      {
        id: 'complete',
        title: t('notifications.actionComplete'),
        foreground: false,
      },
      {
        id: 'snooze',
        title: t('notifications.actionRemindLater'),
        foreground: false,
      },
    ],
  };
}

type NotificationActionEffect =
  | {
    type: 'complete';
    taskId: string;
  }
  | {
    type: 'snooze';
    taskId: string;
    remindAtIso: string;
  };

function asRecord(value: unknown): Record<string, unknown> | null {
  return isRecord(value) ? value : null;
}

function readDataField(record: object, key: string): unknown {
  const descriptor = Object.getOwnPropertyDescriptor(record, key);
  return descriptor && 'value' in descriptor ? descriptor.value : undefined;
}

function isCanonicalNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim() !== '' && value === value.trim();
}

function firstString(...values: unknown[]): string | undefined {
  return values.find((value): value is string => typeof value === 'string');
}

function firstRecord(...values: unknown[]): Record<string, unknown> | undefined | null {
  let sawMalformedRecord = false;
  for (const value of values) {
    if (value === null || value === undefined) continue;
    const record = asRecord(value);
    if (record) return record;
    sawMalformedRecord = true;
  }
  return sawMalformedRecord ? null : undefined;
}

export function normalizeNotificationActionPayload(
  notification: unknown,
): NotificationActionPayload | null {
  const root = asRecord(notification);
  if (!root) return null;

  const nestedNotification = asRecord(readDataField(root, 'notification'));
  const actionTypeIdSource = firstString(
    nestedNotification ? readDataField(nestedNotification, 'actionTypeId') : undefined,
    readDataField(root, 'actionTypeId'),
  );
  const actionSource = firstString(
    readDataField(root, 'action'),
    readDataField(root, 'actionId'),
  );
  const extra = firstRecord(
    nestedNotification ? readDataField(nestedNotification, 'extra') : undefined,
    readDataField(root, 'extra'),
  );
  if (extra === null) return null;

  const normalized: NotificationActionPayload = {};
  if (typeof actionTypeIdSource === 'string') {
    normalized.actionTypeId = actionTypeIdSource;
  }
  if (typeof actionSource === 'string') {
    normalized.action = actionSource;
  }
  if (extra) {
    normalized.extra = extra;
  }

  return normalized.actionTypeId && normalized.action
    ? normalized
    : null;
}

export function resolveNotificationActionEffect(
  notification: NotificationActionPayload,
  nowMs = Date.now(),
): NotificationActionEffect | null {
  if (readDataField(notification, 'actionTypeId') !== 'task-reminder') {
    return null;
  }
  const extra = asRecord(readDataField(notification, 'extra'));
  const taskIdCandidate = extra ? readDataField(extra, 'taskId') : undefined;
  const taskId = isCanonicalNonEmptyString(taskIdCandidate)
    ? taskIdCandidate
    : null;
  const actionId = readDataField(notification, 'action');
  if (!taskId || !actionId) return null;

  switch (actionId) {
    case 'complete':
      return {
        type: 'complete',
        taskId,
      };
    case 'snooze': {
      const DEFAULT_SNOOZE_MINUTES = 60;
      return {
        type: 'snooze',
        taskId,
        remindAtIso: new Date(nowMs + DEFAULT_SNOOZE_MINUTES * 60 * 1000).toISOString(),
      };
    }
    default:
      return null;
  }
}
