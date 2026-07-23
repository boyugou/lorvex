import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  buildTaskReminderActionType,
  normalizeNotificationActionPayload,
  resolveNotificationActionEffect,
} from '../../../app/src/lib/notifications/actions.logic';
import {
  __TEST_ONLY__,
  registerNotificationActions,
} from '../../../app/src/lib/notifications/actions';
import { createBrowserNotificationActionTimerHost } from '../../../app/src/lib/notifications/actions.runtime';

async function flushAsyncWork(rounds = 5): Promise<void> {
  for (let index = 0; index < rounds; index += 1) {
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
}

test.afterEach(() => {
  __TEST_ONLY__.resetForTests();
});

test('buildTaskReminderActionType uses the localized action labels', () => {
  const actionType = buildTaskReminderActionType((key) => `translated:${key}`);
  assert.deepEqual(actionType, {
    id: 'task-reminder',
    actions: [
      {
        id: 'complete',
        title: 'translated:notifications.actionComplete',
        foreground: false,
      },
      {
        id: 'snooze',
        title: 'translated:notifications.actionRemindLater',
        foreground: false,
      },
    ],
  });
});

test('resolveNotificationActionEffect returns complete and snooze effects and fails closed on malformed payloads', () => {
  assert.deepEqual(resolveNotificationActionEffect({
    actionTypeId: 'task-reminder',
    action: 'complete',
    extra: { taskId: 'task-1' },
  }), {
    type: 'complete',
    taskId: 'task-1',
  });

  assert.deepEqual(resolveNotificationActionEffect({
    actionTypeId: 'task-reminder',
    action: 'snooze',
    extra: { taskId: 'task-2' },
  }, Date.UTC(2026, 3, 22, 12, 0, 0)), {
    type: 'snooze',
    taskId: 'task-2',
    remindAtIso: '2026-04-22T13:00:00.000Z',
  });

  assert.equal(resolveNotificationActionEffect({ action: 'dismiss' }), null);
  assert.equal(resolveNotificationActionEffect({ action: 'complete', extra: {} }), null);
  assert.equal(resolveNotificationActionEffect({
    action: 'complete',
    extra: { taskId: 'task-4' },
  }), null);
  assert.equal(resolveNotificationActionEffect({
    actionTypeId: 'other-action-type',
    action: 'complete',
    extra: { taskId: 'task-3' },
  }), null);
  assert.equal(resolveNotificationActionEffect({
    actionTypeId: 'task-reminder',
    action: 'complete',
    extra: { taskId: 123 },
  }), null);
  assert.equal(resolveNotificationActionEffect({
    actionTypeId: 'task-reminder',
    action: 'complete',
    extra: { taskId: ' task-5 ' },
  }), null);
});

test('normalizeNotificationActionPayload accepts flat mocks and real nested plugin events while failing closed on malformed input', () => {
  assert.deepEqual(normalizeNotificationActionPayload({
    actionTypeId: 'task-reminder',
    action: 'complete',
    extra: { taskId: 'task-flat' },
  }), {
    actionTypeId: 'task-reminder',
    action: 'complete',
    extra: { taskId: 'task-flat' },
  });

  assert.deepEqual(normalizeNotificationActionPayload({
    actionId: 'snooze',
    notification: {
      actionTypeId: 'task-reminder',
      extra: { taskId: 'task-nested' },
    },
  }), {
    actionTypeId: 'task-reminder',
    action: 'snooze',
    extra: { taskId: 'task-nested' },
  });

  assert.deepEqual(normalizeNotificationActionPayload({
    action: 123,
    actionId: 'complete',
    actionTypeId: 'task-reminder',
    extra: { taskId: 'task-fallback' },
  }), {
    actionTypeId: 'task-reminder',
    action: 'complete',
    extra: { taskId: 'task-fallback' },
  });

  assert.deepEqual(normalizeNotificationActionPayload({
    actionId: 'snooze',
    actionTypeId: 'task-reminder',
    extra: { taskId: 'task-root-fallback' },
    notification: {
      actionTypeId: 42,
      extra: 'bad-extra',
    },
  }), {
    actionTypeId: 'task-reminder',
    action: 'snooze',
    extra: { taskId: 'task-root-fallback' },
  });

  assert.equal(normalizeNotificationActionPayload(null), null);
  assert.equal(normalizeNotificationActionPayload({
    actionId: 123,
    notification: {
      actionTypeId: 'task-reminder',
      extra: { taskId: 'task-invalid' },
    },
  }), null);
  assert.equal(normalizeNotificationActionPayload({
    actionTypeId: 'task-reminder',
    action: 'complete',
    extra: ['task-array'],
  }), null);
});

test('notification action payload parsing ignores accessors and inherited fields', () => {
  let accessed = 0;
  const hostileExtra = Object.defineProperty({}, 'taskId', {
    enumerable: true,
    get() {
      accessed += 1;
      return 'getter-task';
    },
  });
  const payload = Object.create({
    actionTypeId: 'task-reminder',
    action: 'complete',
  }) as Record<string, unknown>;

  Object.defineProperty(payload, 'notification', {
    enumerable: true,
    get() {
      accessed += 1;
      return {
        actionTypeId: 'task-reminder',
        extra: { taskId: 'getter-nested' },
      };
    },
  });
  Object.defineProperty(payload, 'action', {
    enumerable: true,
    get() {
      accessed += 1;
      return 'complete';
    },
  });
  Object.defineProperty(payload, 'extra', {
    enumerable: true,
    value: hostileExtra,
  });

  assert.equal(normalizeNotificationActionPayload(payload), null);
  assert.equal(resolveNotificationActionEffect({
    actionTypeId: 'task-reminder',
    action: 'complete',
    extra: hostileExtra,
  }), null);
  assert.equal(accessed, 0);
});

test('notification action payload normalizer narrows records through a predicate before returning them', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/notifications/actions.logic.ts'),
    'utf8',
  );

  assert.doesNotMatch(source, /return value as Record<string, unknown>/);
});

test('registerNotificationActions retries a failed listener registration instead of permanently latching success', async () => {
  const registeredTypes: unknown[][] = [];
  const listenerCallbacks: Array<(notification: unknown) => void> = [];
  const completedTaskIds: string[] = [];
  const retryCallbacks: Array<() => void> = [];
  let listenerAttempts = 0;

  __TEST_ONLY__.setDepsForTests({
    addTaskReminder: async () => {
      throw new Error('unexpected snooze');
    },
    completeTask: async (taskId) => {
      completedTaskIds.push(taskId);
      return {} as never;
    },
    getPreference: async () => '"en"',
    importNotificationModule: async () => ({
      registerActionTypes: async (types) => {
        registeredTypes.push(types);
      },
      onAction: async (callback) => {
        listenerAttempts += 1;
        if (listenerAttempts === 1) {
          throw new Error('transient listener failure');
        }
        listenerCallbacks.push(callback);
        return {
          unregister: async () => {},
        };
      },
    }),
    reportClientError: () => {},
    resolveNotificationLocale: () => 'en',
    setTimeout: (callback) => {
      retryCallbacks.push(callback);
      return callback;
    },
    translatorFor: async () => (key) => key,
  });

  await registerNotificationActions();
  assert.equal(retryCallbacks.length, 1, 'a failed listener install should schedule one retry');

  retryCallbacks[0]?.();
  await flushAsyncWork();

  assert.equal(listenerAttempts, 2, 'listener registration should retry after a transient failure');
  assert.equal(registeredTypes.length, 1, 'action type registration should not rerun after succeeding once');
  assert.equal(listenerCallbacks.length, 1, 'listener should be installed once after recovery');

  await listenerCallbacks[0]?.({
    actionTypeId: 'task-reminder',
    action: 'complete',
    extra: { taskId: 'task-42' },
  });

  assert.deepEqual(completedTaskIds, ['task-42']);
});

test('registerNotificationActions becomes idempotent after the listener is installed', async () => {
  let registerActionTypeCalls = 0;
  let listenerCalls = 0;
  let scheduledRetries = 0;

  __TEST_ONLY__.setDepsForTests({
    getPreference: async () => '"en"',
    importNotificationModule: async () => ({
      registerActionTypes: async () => {
        registerActionTypeCalls += 1;
      },
      onAction: async () => {
        listenerCalls += 1;
        return {
          unregister: async () => {},
        };
      },
    }),
    reportClientError: () => {},
    resolveNotificationLocale: () => 'en',
    setTimeout: () => {
      scheduledRetries += 1;
      return scheduledRetries;
    },
    translatorFor: async () => (key) => key,
  });

  await registerNotificationActions();
  await registerNotificationActions();

  assert.equal(registerActionTypeCalls, 1);
  assert.equal(listenerCalls, 1);
  assert.equal(scheduledRetries, 0, 'successful registration should not leave a retry armed');
});

test('registerNotificationActions refreshes action types when the locale changes without reinstalling the listener', async () => {
  const registeredTitles: string[][] = [];
  let listenerCalls = 0;
  let currentPreference = 'en';

  __TEST_ONLY__.setDepsForTests({
    getPreference: async () => currentPreference,
    importNotificationModule: async () => ({
      registerActionTypes: async (types) => {
        registeredTitles.push(types[0]?.actions.map((action) => action.title) ?? []);
      },
      onAction: async () => {
        listenerCalls += 1;
        return {
          unregister: async () => {},
        };
      },
    }),
    reportClientError: () => {},
    resolveNotificationLocale: (value) => value,
    translatorFor: async (locale) => (key) => `${locale}:${key}`,
  });

  await registerNotificationActions();
  currentPreference = 'zh';
  await registerNotificationActions();

  assert.deepEqual(registeredTitles, [
    ['en:notifications.actionComplete', 'en:notifications.actionRemindLater'],
    ['zh:notifications.actionComplete', 'zh:notifications.actionRemindLater'],
  ]);
  assert.equal(listenerCalls, 1, 'listener should stay installed while only action labels refresh');
});

test('registerNotificationActions keeps the listener installed when locale loading fails and retries only action-type setup later', async () => {
  const retryCallbacks: Array<() => void> = [];
  const listenerCallbacks: Array<(notification: unknown) => void> = [];
  const reminderCalls: Array<{ taskId: string; remindAtIso: string }> = [];
  let translatorCalls = 0;
  let listenerCalls = 0;
  let registerActionTypeCalls = 0;

  __TEST_ONLY__.setDepsForTests({
    addTaskReminder: async (taskId, remindAtIso) => {
      reminderCalls.push({ taskId, remindAtIso });
      return {} as never;
    },
    getPreference: async () => 'en',
    importNotificationModule: async () => ({
      registerActionTypes: async () => {
        registerActionTypeCalls += 1;
      },
      onAction: async (callback) => {
        listenerCalls += 1;
        listenerCallbacks.push(callback);
        return {
          unregister: async () => {},
        };
      },
    }),
    reportClientError: () => {},
    resolveNotificationLocale: (value) => value,
    setTimeout: (callback) => {
      retryCallbacks.push(callback);
      return callback;
    },
    translatorFor: async () => {
      translatorCalls += 1;
      if (translatorCalls === 1) {
        throw new Error('transient locale load failure');
      }
      return (key) => key;
    },
  });

  await registerNotificationActions();
  assert.equal(listenerCalls, 1, 'listener registration should not depend on translation loading');
  assert.equal(registerActionTypeCalls, 0, 'action types should not register until translation loading succeeds');
  assert.equal(retryCallbacks.length, 1, 'translation failure should schedule an action-type retry');

  await listenerCallbacks[0]?.({
    actionId: 'snooze',
    notification: {
      actionTypeId: 'task-reminder',
      extra: { taskId: 'task-live-listener' },
    },
  });
  assert.equal(reminderCalls.length, 1, 'the installed listener should remain live even while action-type setup retries');
  assert.equal(reminderCalls[0]?.taskId, 'task-live-listener');

  retryCallbacks[0]?.();
  await flushAsyncWork();

  assert.equal(listenerCalls, 1, 'listener should not be re-installed during action-type recovery');
  assert.equal(registerActionTypeCalls, 1, 'action types should recover on the later retry');
});

test('registerNotificationActions resets the action-type retry budget after recovery so a later locale refresh gets a full retry window', async () => {
  let currentPreference = 'en';
  const retryCallbacks: Array<() => void> = [];
  const registeredLocales: string[] = [];
  let registerActionTypeCalls = 0;

  __TEST_ONLY__.setDepsForTests({
    getPreference: async () => currentPreference,
    importNotificationModule: async () => ({
      registerActionTypes: async () => {
        registerActionTypeCalls += 1;
        if (registerActionTypeCalls === 1) {
          throw new Error('transient english failure');
        }
        if (currentPreference === 'zh' && registerActionTypeCalls < 6) {
          throw new Error('transient chinese failure');
        }
        registeredLocales.push(currentPreference);
      },
      onAction: async () => ({
        unregister: async () => {},
      }),
    }),
    reportClientError: () => {},
    resolveNotificationLocale: (value) => value,
    setTimeout: (callback) => {
      retryCallbacks.push(callback);
      return callback;
    },
    translatorFor: async (locale) => (key) => `${locale}:${key}`,
  });

  await registerNotificationActions();
  retryCallbacks.shift()?.();
  await flushAsyncWork();

  currentPreference = 'zh';
  await registerNotificationActions();
  retryCallbacks.shift()?.();
  await flushAsyncWork();
  retryCallbacks.shift()?.();
  await flushAsyncWork();
  retryCallbacks.shift()?.();
  await flushAsyncWork();

  assert.deepEqual(registeredLocales, ['en', 'zh']);
  assert.equal(registerActionTypeCalls, 6, 'a recovered locale should not consume the full retry budget for the next locale refresh');
});

test('registerNotificationActions retries action-type registration after a transient failure even when the listener already succeeded', async () => {
  let registerActionTypeCalls = 0;
  let listenerCalls = 0;
  const retryCallbacks: Array<() => void> = [];

  __TEST_ONLY__.setDepsForTests({
    getPreference: async () => '"en"',
    importNotificationModule: async () => ({
      registerActionTypes: async () => {
        registerActionTypeCalls += 1;
        if (registerActionTypeCalls === 1) {
          throw new Error('transient action-type failure');
        }
      },
      onAction: async () => {
        listenerCalls += 1;
        return {
          unregister: async () => {},
        };
      },
    }),
    reportClientError: () => {},
    resolveNotificationLocale: () => 'en',
    setTimeout: (callback) => {
      retryCallbacks.push(callback);
      return callback;
    },
    translatorFor: async () => (key) => key,
  });

  await registerNotificationActions();
  assert.equal(retryCallbacks.length, 1, 'action-type failure should schedule a bounded retry');

  retryCallbacks[0]?.();
  await flushAsyncWork();

  assert.equal(registerActionTypeCalls, 2, 'action-type registration should retry and recover');
  assert.equal(listenerCalls, 1, 'listener should not be re-installed once already active');
});

test('registerNotificationActions clears an already-armed retry when a later manual registration succeeds', async () => {
  const retryCallbacks: Array<() => void> = [];
  const clearedHandles: unknown[] = [];
  let listenerCalls = 0;

  __TEST_ONLY__.setDepsForTests({
    clearTimeout: (handle) => {
      clearedHandles.push(handle);
    },
    getPreference: async () => '"en"',
    importNotificationModule: async () => ({
      registerActionTypes: async () => {},
      onAction: async () => {
        listenerCalls += 1;
        if (listenerCalls === 1) {
          throw new Error('transient listener failure');
        }
        return {
          unregister: async () => {},
        };
      },
    }),
    reportClientError: () => {},
    resolveNotificationLocale: () => 'en',
    setTimeout: (callback) => {
      retryCallbacks.push(callback);
      return callback;
    },
    translatorFor: async () => (key) => key,
  });

  await registerNotificationActions();
  assert.equal(retryCallbacks.length, 1, 'first failure should arm one retry');

  await registerNotificationActions();

  assert.equal(listenerCalls, 2, 'manual foreground retry should re-attempt listener registration');
  assert.deepEqual(clearedHandles, [retryCallbacks[0]], 'successful recovery should clear the stale retry timer');
});

test('registerNotificationActions caps repeated listener retries for permanently unsupported platforms', async () => {
  let listenerCalls = 0;
  const retryCallbacks: Array<() => void> = [];

  __TEST_ONLY__.setDepsForTests({
    getPreference: async () => '"en"',
    importNotificationModule: async () => ({
      registerActionTypes: async () => {},
      onAction: async () => {
        listenerCalls += 1;
        throw new Error('unsupported on desktop');
      },
    }),
    reportClientError: () => {},
    resolveNotificationLocale: () => 'en',
    setTimeout: (callback) => {
      retryCallbacks.push(callback);
      return callback;
    },
    translatorFor: async () => (key) => key,
  });

  await registerNotificationActions();
  assert.equal(retryCallbacks.length, 1);

  retryCallbacks[0]?.();
  await flushAsyncWork();
  retryCallbacks[1]?.();
  await flushAsyncWork();
  retryCallbacks[2]?.();
  await flushAsyncWork();

  assert.equal(listenerCalls, 4, 'initial attempt plus three bounded retries should run');
  assert.equal(retryCallbacks.length, 3, 'permanent unsupported failures should stop re-arming retries after the cap');
});

test('registerNotificationActions caps repeated action-type retries for permanently unsupported platforms even when the listener succeeds', async () => {
  let registerActionTypeCalls = 0;
  let listenerCalls = 0;
  const retryCallbacks: Array<() => void> = [];

  __TEST_ONLY__.setDepsForTests({
    getPreference: async () => '"en"',
    importNotificationModule: async () => ({
      registerActionTypes: async () => {
        registerActionTypeCalls += 1;
        throw new Error('unsupported on this platform');
      },
      onAction: async () => {
        listenerCalls += 1;
        return {
          unregister: async () => {},
        };
      },
    }),
    reportClientError: () => {},
    resolveNotificationLocale: () => 'en',
    setTimeout: (callback) => {
      retryCallbacks.push(callback);
      return callback;
    },
    translatorFor: async () => (key) => key,
  });

  await registerNotificationActions();
  assert.equal(retryCallbacks.length, 1);

  retryCallbacks[0]?.();
  await flushAsyncWork();
  retryCallbacks[1]?.();
  await flushAsyncWork();
  retryCallbacks[2]?.();
  await flushAsyncWork();

  assert.equal(registerActionTypeCalls, 4, 'initial attempt plus three bounded retries should run');
  assert.equal(listenerCalls, 1, 'listener should install only once while action-type retries continue independently');
  assert.equal(retryCallbacks.length, 3, 'permanent action-type failure should stop re-arming retries after the cap');
});

test('notification action handler snoozes by creating a one-hour reminder and ignores malformed payloads', async () => {
  const reminderCalls: Array<{ taskId: string; remindAtIso: string }> = [];
  const completedTaskIds: string[] = [];

  __TEST_ONLY__.setDepsForTests({
    addTaskReminder: async (taskId, remindAtIso) => {
      reminderCalls.push({ taskId, remindAtIso });
      return {} as never;
    },
    completeTask: async (taskId) => {
      completedTaskIds.push(taskId);
      return {} as never;
    },
    reportClientError: () => {},
  });

  const originalNow = Date.now;
  Date.now = () => Date.UTC(2026, 3, 22, 15, 30, 0);
  try {
    await __TEST_ONLY__.handleNotificationAction({
      actionId: 'snooze',
      notification: {
        actionTypeId: 'task-reminder',
        extra: { taskId: 'task-7' },
      },
    });
    await __TEST_ONLY__.handleNotificationAction({
      actionTypeId: 'task-reminder',
      action: 'complete',
      extra: { taskId: 'task-8' },
    });
    await __TEST_ONLY__.handleNotificationAction({
      actionTypeId: 'other-action-type',
      action: 'complete',
      extra: { taskId: 'task-ignored' },
    });
    await __TEST_ONLY__.handleNotificationAction({
      actionTypeId: 'task-reminder',
      action: 'complete',
      extra: { taskId: 42 },
    });
    await __TEST_ONLY__.handleNotificationAction({
      action: 'complete',
      extra: { taskId: 'task-missing-action-type' },
    });
    await __TEST_ONLY__.handleNotificationAction({
      action: 'complete',
      extra: {},
    });
  } finally {
    Date.now = originalNow;
  }

  assert.deepEqual(reminderCalls, [
    {
      taskId: 'task-7',
      remindAtIso: '2026-04-22T16:30:00.000Z',
    },
  ]);
  assert.deepEqual(completedTaskIds, ['task-8']);
});

test('notification action runtime owns the browser retry timer host wiring', () => {
  const actionsSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/notifications/actions.ts'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/notifications/actions.runtime.ts'),
    'utf8',
  );
  const host = createBrowserNotificationActionTimerHost();

  assert.equal(typeof host.setTimeout, 'function');
  assert.equal(typeof host.clearTimeout, 'function');
  assert.match(actionsSource, /from '\.\/actions\.runtime';/);
  assert.match(actionsSource, /\.\.\.createBrowserNotificationActionTimerHost\(\),/);
  assert.doesNotMatch(actionsSource, /globalThis\./);
  assert.match(runtimeSource, /export function createBrowserNotificationActionTimerHost\(\): NotificationActionTimerHost/);
  assert.match(runtimeSource, /globalThis\.clearTimeout\(handle as ReturnType<typeof globalThis\.setTimeout>\);/);
  assert.match(runtimeSource, /setTimeout: \(callback, delayMs\) => globalThis\.setTimeout\(callback, delayMs\),/);
});
