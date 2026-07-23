import { getPreference } from '@/lib/ipc/settings';
import { completeTask } from '@/lib/ipc/tasks/mutations/lifecycle';
import { addTaskReminder } from '@/lib/ipc/tasks/mutations/reminders';
import { reportClientError } from '../errors/errorLogging';
import { PREF_LANGUAGE } from '../preferences/keys';
import { resolveNotificationLocale, translatorFor } from './preferences';
import {
  buildTaskReminderActionType,
  normalizeNotificationActionPayload,
  resolveNotificationActionEffect,
  type TaskReminderActionType,
} from './actions.logic';
import {
  createBrowserNotificationActionTimerHost,
  type NotificationActionTimerHost,
} from './actions.runtime';

interface NotificationPluginModule {
  onAction: (
    handler: (notification: unknown) => void,
  ) => Promise<{ unregister(): Promise<void> }>;
  registerActionTypes: (types: TaskReminderActionType[]) => Promise<void>;
}

interface NotificationActionDeps {
  addTaskReminder: typeof addTaskReminder;
  clearTimeout: NotificationActionTimerHost['clearTimeout'];
  completeTask: typeof completeTask;
  getPreference: typeof getPreference;
  importNotificationModule: () => Promise<NotificationPluginModule>;
  reportClientError: typeof reportClientError;
  resolveNotificationLocale: typeof resolveNotificationLocale;
  setTimeout: NotificationActionTimerHost['setTimeout'];
  translatorFor: typeof translatorFor;
}

const MAX_RETRY_ATTEMPTS = 3;
const RETRY_DELAY_MS = 5_000;

const runtimeDeps: NotificationActionDeps = {
  addTaskReminder,
  completeTask,
  getPreference,
  importNotificationModule: () => import('@tauri-apps/plugin-notification'),
  reportClientError,
  resolveNotificationLocale,
  translatorFor,
  ...createBrowserNotificationActionTimerHost(),
};

let deps: NotificationActionDeps = runtimeDeps;
let actionTypesRegistered = false;
let actionListenerRegistered = false;
let registrationPromise: Promise<void> | null = null;
let retryHandle: unknown | null = null;
let actionTypeRetryAttempts = 0;
let listenerRetryAttempts = 0;
let registeredActionTypeLocale: string | null = null;

function canAttemptRegistration(retryAttempts: number): boolean {
  return retryAttempts <= MAX_RETRY_ATTEMPTS;
}

function recordRegistrationFailure(
  retryAttempts: number,
): { nextRetryAttempts: number; shouldRetry: boolean } {
  if (retryAttempts < MAX_RETRY_ATTEMPTS) {
    return {
      nextRetryAttempts: retryAttempts + 1,
      shouldRetry: true,
    };
  }
  return {
    nextRetryAttempts: MAX_RETRY_ATTEMPTS + 1,
    shouldRetry: false,
  };
}

export async function registerNotificationActions(): Promise<void> {
  if (registrationPromise) return registrationPromise;
  registrationPromise = registerNotificationActionsInner().finally(() => {
    registrationPromise = null;
  });
  return registrationPromise;
}

async function handleNotificationAction(notification: unknown): Promise<void> {
  try {
    const normalizedNotification = normalizeNotificationActionPayload(notification);
    if (!normalizedNotification) return;

    const effect = resolveNotificationActionEffect(normalizedNotification);
    if (!effect) return;

    switch (effect.type) {
      case 'complete':
        await deps.completeTask(effect.taskId);
        break;
      case 'snooze':
        await deps.addTaskReminder(effect.taskId, effect.remindAtIso);
        break;
      default:
        return;
    }
  } catch (error) {
    deps.reportClientError(
      'notifications.handleAction',
      'Failed to handle notification action',
      error,
    );
  }
}

async function registerNotificationActionsInner(): Promise<void> {
  let shouldRetryActionTypes = false;
  let shouldRetryListener = false;
  try {
    const { registerActionTypes, onAction } = await deps.importNotificationModule();

    if (!actionListenerRegistered && canAttemptRegistration(listenerRetryAttempts)) {
      try {
        await onAction((notification) => {
          void handleNotificationAction(notification);
        });
        actionListenerRegistered = true;
        listenerRetryAttempts = 0;
      } catch {
        // `onAction` can fail transiently during startup or be unsupported on
        // some platforms. Retry a small bounded number of times so we recover
        // from races without leaving a permanent timer loop.
        const retryOutcome = recordRegistrationFailure(listenerRetryAttempts);
        shouldRetryListener = retryOutcome.shouldRetry;
        listenerRetryAttempts = retryOutcome.nextRetryAttempts;
      }
    }

    const locale = deps.resolveNotificationLocale(await deps.getPreference(PREF_LANGUAGE));
    const actionTypesCurrent = actionTypesRegistered && registeredActionTypeLocale === locale;

    if (!actionTypesCurrent && canAttemptRegistration(actionTypeRetryAttempts)) {
      try {
        const t = await deps.translatorFor(locale);
        await registerActionTypes([
          buildTaskReminderActionType(t),
        ]);
        actionTypesRegistered = true;
        actionTypeRetryAttempts = 0;
        registeredActionTypeLocale = locale;
      } catch {
        // registerActionTypes may not be available on some desktop builds and can
        // also fail transiently during startup. Retry a small bounded number of times,
        // then degrade gracefully without spinning forever.
        const retryOutcome = recordRegistrationFailure(actionTypeRetryAttempts);
        shouldRetryActionTypes = retryOutcome.shouldRetry;
        actionTypeRetryAttempts = retryOutcome.nextRetryAttempts;
      }
    }
  } catch (error) {
    deps.reportClientError(
      'notifications.registerActions',
      'Failed to initialize notification action registration',
      error,
    );
    if (!actionListenerRegistered && canAttemptRegistration(listenerRetryAttempts)) {
      const retryOutcome = recordRegistrationFailure(listenerRetryAttempts);
      shouldRetryListener = retryOutcome.shouldRetry;
      listenerRetryAttempts = retryOutcome.nextRetryAttempts;
    } else if (!actionListenerRegistered) {
      listenerRetryAttempts = MAX_RETRY_ATTEMPTS + 1;
    }
    if (!actionTypesRegistered && canAttemptRegistration(actionTypeRetryAttempts)) {
      const retryOutcome = recordRegistrationFailure(actionTypeRetryAttempts);
      shouldRetryActionTypes = retryOutcome.shouldRetry;
      actionTypeRetryAttempts = retryOutcome.nextRetryAttempts;
    } else if (!actionTypesRegistered) {
      actionTypeRetryAttempts = MAX_RETRY_ATTEMPTS + 1;
    }
  } finally {
    if (shouldRetryActionTypes || shouldRetryListener) {
      scheduleRetry();
    } else {
      clearScheduledRetry();
    }
  }
}

function clearScheduledRetry(): void {
  if (retryHandle === null) return;
  deps.clearTimeout(retryHandle);
  retryHandle = null;
}

function scheduleRetry(): void {
  if (retryHandle !== null) return;
  retryHandle = deps.setTimeout(() => {
    retryHandle = null;
    void registerNotificationActions();
  }, RETRY_DELAY_MS);
}

function resetRegistrationStateForTests(): void {
  clearScheduledRetry();
  actionTypesRegistered = false;
  actionListenerRegistered = false;
  registrationPromise = null;
  retryHandle = null;
  actionTypeRetryAttempts = 0;
  listenerRetryAttempts = 0;
  registeredActionTypeLocale = null;
}

export const __TEST_ONLY__ = {
  handleNotificationAction,
  setDepsForTests(overrides: Partial<NotificationActionDeps>): void {
    resetRegistrationStateForTests();
    deps = {
      ...runtimeDeps,
      ...overrides,
    };
  },
  resetForTests(): void {
    resetRegistrationStateForTests();
    deps = runtimeDeps;
  },
};
