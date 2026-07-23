import assert from 'node:assert/strict';
import test from 'node:test';

import {
  installNotificationPermissionPromptRuntime,
  type NotificationPermissionPromptCancellationProbe,
  type NotificationPermissionPromptPlugin,
  type NotificationPermissionPromptRuntimeState,
} from '../../../app/src/lib/notifications/permissionPrompt.runtime';
import {
  getNotificationPermissionPromptDeviceState,
  setNotificationPermissionPromptDeviceState,
} from '../../../app/src/lib/notifications/permissionPrompt.persistence';

interface NotificationPermissionPromptHarnessOptions {
  confirmPrompt?: () => Promise<boolean>;
  enabled?: boolean;
  getPrompted?: () => Promise<boolean>;
  initialLaunched?: boolean;
  isPermissionGranted?: () => Promise<boolean>;
  loadNotificationPlugin?: () => Promise<NotificationPermissionPromptPlugin>;
  requestPermission?: () => Promise<'granted' | 'denied' | 'default' | string>;
  setGranted?: (
    granted: boolean,
    isCancelled: NotificationPermissionPromptCancellationProbe,
  ) => Promise<void>;
  setPrompted?: (
    prompted: boolean,
    isCancelled: NotificationPermissionPromptCancellationProbe,
  ) => Promise<void>;
}

async function flushNotificationPermissionPromptRuntime(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await new Promise((resolve) => setTimeout(resolve, 0));
}

function createNotificationPermissionPromptHarness(
  options: NotificationPermissionPromptHarnessOptions = {},
) {
  const calls: string[] = [];
  const errors: unknown[] = [];
  const grantedWrites: boolean[] = [];
  const promptedWrites: boolean[] = [];
  const state: NotificationPermissionPromptRuntimeState = {
    launched: options.initialLaunched ?? false,
  };
  let cacheRefreshes = 0;

  return {
    calls,
    errors,
    grantedWrites,
    promptedWrites,
    state,
    get cacheRefreshes() {
      return cacheRefreshes;
    },
    install: () => installNotificationPermissionPromptRuntime({
      confirmPrompt: options.confirmPrompt ?? (async () => {
        calls.push('confirm');
        return true;
      }),
      enabled: options.enabled ?? true,
      getPrompted: options.getPrompted ?? (async () => {
        calls.push('get-prompted');
        return false;
      }),
      loadNotificationPlugin: options.loadNotificationPlugin ?? (async () => {
        calls.push('load-plugin');
        return {
          isPermissionGranted: options.isPermissionGranted ?? (async () => {
            calls.push('is-granted');
            return false;
          }),
          requestPermission: options.requestPermission ?? (async () => {
            calls.push('request');
            return 'granted';
          }),
        };
      }),
      refreshNotificationPermissionCache: () => {
        cacheRefreshes += 1;
      },
      reportPromptError: (error) => {
        errors.push(error);
      },
      setGranted: options.setGranted ?? (async (granted, isCancelled) => {
        if (isCancelled()) return;
        grantedWrites.push(granted);
      }),
      setPrompted: options.setPrompted ?? (async (prompted, isCancelled) => {
        if (isCancelled()) return;
        promptedWrites.push(prompted);
      }),
      state,
    }),
  };
}

test('notification permission prompt runtime is inert while disabled', async () => {
  const harness = createNotificationPermissionPromptHarness({ enabled: false });

  harness.install();
  await flushNotificationPermissionPromptRuntime();

  assert.equal(harness.state.launched, false);
  assert.deepEqual(harness.calls, []);
  assert.deepEqual(harness.promptedWrites, []);
  assert.deepEqual(harness.grantedWrites, []);
});

test('notification permission prompt runtime suppresses duplicate launches', async () => {
  const harness = createNotificationPermissionPromptHarness({ initialLaunched: true });

  harness.install();
  await flushNotificationPermissionPromptRuntime();

  assert.equal(harness.state.launched, true);
  assert.deepEqual(harness.calls, []);
});

test('notification permission prompt runtime skips plugin and writes when already prompted', async () => {
  const harness = createNotificationPermissionPromptHarness({
    getPrompted: async () => {
      harness.calls.push('get-prompted');
      return true;
    },
  });

  harness.install();
  await flushNotificationPermissionPromptRuntime();

  assert.equal(harness.state.launched, true);
  assert.deepEqual(harness.calls, ['get-prompted']);
  assert.deepEqual(harness.promptedWrites, []);
  assert.deepEqual(harness.grantedWrites, []);
});

test('notification permission prompt runtime persists already-granted OS state without prompting', async () => {
  const harness = createNotificationPermissionPromptHarness({
    isPermissionGranted: async () => {
      harness.calls.push('is-granted');
      return true;
    },
  });

  harness.install();
  await flushNotificationPermissionPromptRuntime();

  assert.deepEqual(harness.calls, ['get-prompted', 'load-plugin', 'is-granted']);
  assert.deepEqual(harness.promptedWrites, [true]);
  assert.deepEqual(harness.grantedWrites, [true]);
  assert.equal(harness.cacheRefreshes, 0);
});

test('notification permission prompt runtime keeps declined explainers separate from OS prompt state', async () => {
  const harness = createNotificationPermissionPromptHarness({
    confirmPrompt: async () => {
      harness.calls.push('confirm');
      return false;
    },
  });

  harness.install();
  await flushNotificationPermissionPromptRuntime();

  assert.deepEqual(harness.calls, ['get-prompted', 'load-plugin', 'is-granted', 'confirm']);
  assert.deepEqual(harness.promptedWrites, []);
  assert.deepEqual(harness.grantedWrites, []);
  assert.equal(harness.cacheRefreshes, 0);
});

test('notification permission prompt runtime requests OS permission after accepted explainer', async () => {
  const harness = createNotificationPermissionPromptHarness({
    requestPermission: async () => {
      harness.calls.push('request');
      return 'denied';
    },
  });

  harness.install();
  await flushNotificationPermissionPromptRuntime();

  assert.deepEqual(harness.calls, [
    'get-prompted',
    'load-plugin',
    'is-granted',
    'confirm',
    'request',
  ]);
  assert.deepEqual(harness.promptedWrites, [true]);
  assert.deepEqual(harness.grantedWrites, [false]);
  assert.equal(harness.cacheRefreshes, 1);
});

test('notification permission prompt runtime cleanup suppresses writes after pending confirm', async () => {
  let resolveConfirm: ((value: boolean) => void) | null = null;
  const harness = createNotificationPermissionPromptHarness({
    confirmPrompt: () => new Promise((resolve) => {
      harness.calls.push('confirm');
      resolveConfirm = resolve;
    }),
  });

  const handle = harness.install();
  await flushNotificationPermissionPromptRuntime();
  handle.dispose();
  resolveConfirm?.(true);
  await flushNotificationPermissionPromptRuntime();

  assert.deepEqual(harness.calls, ['get-prompted', 'load-plugin', 'is-granted', 'confirm']);
  assert.deepEqual(harness.promptedWrites, []);
  assert.deepEqual(harness.grantedWrites, []);
  assert.equal(harness.cacheRefreshes, 0);
});

test('notification permission prompt runtime suppresses late get-prompted failures after cleanup', async () => {
  const failure = new Error('late get-prompted failed');
  let rejectPrompted: ((error: unknown) => void) | null = null;
  const harness = createNotificationPermissionPromptHarness({
    getPrompted: () => new Promise((_resolve, reject) => {
      harness.calls.push('get-prompted');
      rejectPrompted = reject;
    }),
  });

  const handle = harness.install();
  handle.dispose();
  rejectPrompted?.(failure);
  await flushNotificationPermissionPromptRuntime();

  assert.deepEqual(harness.errors, []);
  assert.deepEqual(harness.calls, ['get-prompted']);
  assert.deepEqual(harness.promptedWrites, []);
  assert.deepEqual(harness.grantedWrites, []);
});

test('notification permission prompt runtime suppresses late permission request failures after cleanup', async () => {
  const failure = new Error('late permission request failed');
  let rejectRequest: ((error: unknown) => void) | null = null;
  const harness = createNotificationPermissionPromptHarness({
    requestPermission: () => new Promise((_resolve, reject) => {
      harness.calls.push('request');
      rejectRequest = reject;
    }),
  });

  const handle = harness.install();
  await flushNotificationPermissionPromptRuntime();
  handle.dispose();
  rejectRequest?.(failure);
  await flushNotificationPermissionPromptRuntime();

  assert.deepEqual(harness.errors, []);
  assert.deepEqual(harness.calls, [
    'get-prompted',
    'load-plugin',
    'is-granted',
    'confirm',
    'request',
  ]);
  assert.deepEqual(harness.promptedWrites, []);
  assert.deepEqual(harness.grantedWrites, []);
  assert.equal(harness.cacheRefreshes, 0);
});

test('notification permission prompt runtime suppresses OS probe after cleanup during plugin load', async () => {
  let resolvePlugin: ((plugin: NotificationPermissionPromptPlugin) => void) | null = null;
  const harness = createNotificationPermissionPromptHarness({
    loadNotificationPlugin: () => new Promise((resolve) => {
      harness.calls.push('load-plugin');
      resolvePlugin = resolve;
    }),
  });

  const handle = harness.install();
  await flushNotificationPermissionPromptRuntime();
  handle.dispose();
  resolvePlugin?.({
    isPermissionGranted: async () => {
      harness.calls.push('is-granted');
      return false;
    },
    requestPermission: async () => {
      harness.calls.push('request');
      return 'granted';
    },
  });
  await flushNotificationPermissionPromptRuntime();

  assert.deepEqual(harness.errors, []);
  assert.deepEqual(harness.calls, ['get-prompted', 'load-plugin']);
  assert.deepEqual(harness.promptedWrites, []);
  assert.deepEqual(harness.grantedWrites, []);
  assert.equal(harness.cacheRefreshes, 0);
});

test('notification permission prompt runtime suppresses cache refresh after cleanup during permission request', async () => {
  let resolveRequest: ((value: 'granted') => void) | null = null;
  const harness = createNotificationPermissionPromptHarness({
    requestPermission: () => new Promise((resolve) => {
      harness.calls.push('request');
      resolveRequest = resolve;
    }),
  });

  const handle = harness.install();
  await flushNotificationPermissionPromptRuntime();
  handle.dispose();
  resolveRequest?.('granted');
  await flushNotificationPermissionPromptRuntime();

  assert.deepEqual(harness.errors, []);
  assert.deepEqual(harness.calls, [
    'get-prompted',
    'load-plugin',
    'is-granted',
    'confirm',
    'request',
  ]);
  assert.deepEqual(harness.promptedWrites, []);
  assert.deepEqual(harness.grantedWrites, []);
  assert.equal(harness.cacheRefreshes, 0);
});

test('notification permission prompt runtime has no declined-prompt writes to abort after cleanup', async () => {
  const harness = createNotificationPermissionPromptHarness({
    confirmPrompt: async () => {
      harness.calls.push('confirm');
      return false;
    },
  });

  const handle = harness.install();
  await flushNotificationPermissionPromptRuntime();
  handle.dispose();
  await flushNotificationPermissionPromptRuntime();

  assert.deepEqual(harness.errors, []);
  assert.deepEqual(harness.calls, [
    'get-prompted',
    'load-plugin',
    'is-granted',
    'confirm',
  ]);
  assert.deepEqual(harness.promptedWrites, []);
  assert.deepEqual(harness.grantedWrites, []);
  assert.equal(harness.cacheRefreshes, 0);
});

test('notification permission prompt runtime aborts persist-result writes after cleanup', async () => {
  let releaseWrites: (() => void) | null = null;
  const pendingWrites = new Promise<void>((resolve) => {
    releaseWrites = resolve;
  });
  const harness = createNotificationPermissionPromptHarness({
    isPermissionGranted: async () => {
      harness.calls.push('is-granted');
      return true;
    },
    setGranted: async (granted, isCancelled) => {
      harness.calls.push('set-granted-start');
      await pendingWrites;
      if (isCancelled()) {
        harness.calls.push('set-granted-aborted');
        return;
      }
      harness.grantedWrites.push(granted);
    },
    setPrompted: async (prompted, isCancelled) => {
      harness.calls.push('set-prompted-start');
      await pendingWrites;
      if (isCancelled()) {
        harness.calls.push('set-prompted-aborted');
        return;
      }
      harness.promptedWrites.push(prompted);
    },
  });

  const handle = harness.install();
  await flushNotificationPermissionPromptRuntime();
  handle.dispose();
  releaseWrites?.();
  await flushNotificationPermissionPromptRuntime();

  assert.deepEqual(harness.errors, []);
  assert.deepEqual(harness.calls, [
    'get-prompted',
    'load-plugin',
    'is-granted',
    'set-prompted-start',
    'set-granted-start',
    'set-prompted-aborted',
    'set-granted-aborted',
  ]);
  assert.deepEqual(harness.promptedWrites, []);
  assert.deepEqual(harness.grantedWrites, []);
  assert.equal(harness.cacheRefreshes, 0);
});

test('notification permission prompt persistence restores previous state after cleanup wins post-dispatch', async () => {
  let cancelled = false;
  let releaseWrite: (() => void) | null = null;
  const pendingWrite = new Promise<void>((resolve) => {
    releaseWrite = resolve;
  });
  const calls: string[] = [];
  const deviceState = new Map<string, string | null>([
    ['notification_permission_prompted', 'false'],
  ]);

  const writePromise = setNotificationPermissionPromptDeviceState({
    getDeviceState: async (key) => {
      calls.push(`get:${key}`);
      return deviceState.get(key) ?? null;
    },
    setDeviceState: async (key, value) => {
      calls.push(`set-start:${key}:${String(value)}`);
      await pendingWrite;
      deviceState.set(key, value === null ? null : JSON.stringify(value));
      calls.push(`set-end:${key}:${String(value)}`);
    },
  }, 'notification_permission_prompted', true, () => cancelled);

  await flushNotificationPermissionPromptRuntime();
  cancelled = true;
  releaseWrite?.();
  await writePromise;

  assert.deepEqual(calls, [
    'get:notification_permission_prompted',
    'set-start:notification_permission_prompted:true',
    'set-end:notification_permission_prompted:true',
    'set-start:notification_permission_prompted:false',
    'set-end:notification_permission_prompted:false',
  ]);
  assert.equal(deviceState.get('notification_permission_prompted'), 'false');
});

test('notification permission prompt persistence restores missing previous state after cleanup wins post-dispatch', async () => {
  let cancelled = false;
  let releaseWrite: (() => void) | null = null;
  const pendingWrite = new Promise<void>((resolve) => {
    releaseWrite = resolve;
  });
  const calls: string[] = [];
  const deviceState = new Map<string, string | null>();

  const writePromise = setNotificationPermissionPromptDeviceState({
    getDeviceState: async (key) => {
      calls.push(`get:${key}`);
      return deviceState.get(key) ?? null;
    },
    setDeviceState: async (key, value) => {
      calls.push(`set-start:${key}:${String(value)}`);
      await pendingWrite;
      deviceState.set(key, value === null ? null : JSON.stringify(value));
      calls.push(`set-end:${key}:${String(value)}`);
    },
  }, 'notification_permission_granted', true, () => cancelled);

  await flushNotificationPermissionPromptRuntime();
  cancelled = true;
  releaseWrite?.();
  await writePromise;

  assert.deepEqual(calls, [
    'get:notification_permission_granted',
    'set-start:notification_permission_granted:true',
    'set-end:notification_permission_granted:true',
    'set-start:notification_permission_granted:null',
    'set-end:notification_permission_granted:null',
  ]);
  assert.equal(deviceState.get('notification_permission_granted'), null);
});

test('notification permission prompt persistence serializes newer writes after stale rollback', async () => {
  let cancelled = false;
  let releaseFirstWrite: (() => void) | null = null;
  const pendingFirstWrite = new Promise<void>((resolve) => {
    releaseFirstWrite = resolve;
  });
  const calls: string[] = [];
  const deviceState = new Map<string, string | null>([
    ['notification_permission_granted', 'false'],
  ]);
  let firstBooleanWriteStarted = false;

  const store = {
    getDeviceState: async (key: string) => {
      calls.push(`get:${String(deviceState.get(key))}`);
      return deviceState.get(key) ?? null;
    },
    setDeviceState: async (key: string, value: unknown) => {
      calls.push(`set-start:${String(value)}`);
      if (value === true && !firstBooleanWriteStarted) {
        firstBooleanWriteStarted = true;
        await pendingFirstWrite;
      }
      deviceState.set(key, value === null ? null : JSON.stringify(value));
      calls.push(`set-end:${String(value)}`);
    },
  };

  const staleWrite = setNotificationPermissionPromptDeviceState(
    store,
    'notification_permission_granted',
    true,
    () => cancelled,
  );
  await flushNotificationPermissionPromptRuntime();
  cancelled = true;

  const newerWrite = setNotificationPermissionPromptDeviceState(
    store,
    'notification_permission_granted',
    true,
    () => false,
  );
  await flushNotificationPermissionPromptRuntime();
  releaseFirstWrite?.();
  await Promise.all([staleWrite, newerWrite]);

  assert.deepEqual(calls, [
    'get:false',
    'set-start:true',
    'set-end:true',
    'set-start:false',
    'set-end:false',
    'get:false',
    'set-start:true',
    'set-end:true',
  ]);
  assert.equal(deviceState.get('notification_permission_granted'), 'true');
});

test('notification permission prompt persistence waits for stale rollback before reading', async () => {
  let cancelled = false;
  let releaseDispatchedWrite: (() => void) | null = null;
  const dispatchedWrite = new Promise<void>((resolve) => {
    releaseDispatchedWrite = resolve;
  });
  let releaseBackendReturn: (() => void) | null = null;
  const pendingBackendReturn = new Promise<void>((resolve) => {
    releaseBackendReturn = resolve;
  });
  const calls: string[] = [];
  const deviceState = new Map<string, string | null>([
    ['notification_permission_prompted', 'false'],
  ]);
  let firstBooleanWriteStarted = false;

  const store = {
    getDeviceState: async (key: string) => {
      calls.push(`get:${String(deviceState.get(key))}`);
      return deviceState.get(key) ?? null;
    },
    setDeviceState: async (key: string, value: unknown) => {
      calls.push(`set-start:${String(value)}`);
      if (value === true && !firstBooleanWriteStarted) {
        firstBooleanWriteStarted = true;
        deviceState.set(key, JSON.stringify(value));
        calls.push(`set-end:${String(value)}`);
        releaseDispatchedWrite?.();
        await pendingBackendReturn;
        return;
      }
      deviceState.set(key, value === null ? null : JSON.stringify(value));
      calls.push(`set-end:${String(value)}`);
    },
  };

  const staleWrite = setNotificationPermissionPromptDeviceState(
    store,
    'notification_permission_prompted',
    true,
    () => cancelled,
  );
  await dispatchedWrite;
  cancelled = true;

  const stableRead = getNotificationPermissionPromptDeviceState(
    store,
    'notification_permission_prompted',
  );
  await flushNotificationPermissionPromptRuntime();
  assert.deepEqual(calls, [
    'get:false',
    'set-start:true',
    'set-end:true',
  ]);

  releaseBackendReturn?.();
  const readValue = await stableRead;
  await staleWrite;

  assert.deepEqual(calls, [
    'get:false',
    'set-start:true',
    'set-end:true',
    'set-start:false',
    'set-end:false',
    'get:false',
  ]);
  assert.equal(readValue, 'false');
  assert.equal(deviceState.get('notification_permission_prompted'), 'false');
});

test('notification permission prompt runtime reports probe and request failures fail-closed', async () => {
  const probeFailure = new Error('probe failed');
  const probeHarness = createNotificationPermissionPromptHarness({
    getPrompted: async () => {
      throw probeFailure;
    },
  });

  probeHarness.install();
  await flushNotificationPermissionPromptRuntime();

  const requestFailure = new Error('request failed');
  const requestHarness = createNotificationPermissionPromptHarness({
    requestPermission: async () => {
      throw requestFailure;
    },
  });

  requestHarness.install();
  await flushNotificationPermissionPromptRuntime();

  assert.deepEqual(probeHarness.errors, [probeFailure]);
  assert.deepEqual(requestHarness.errors, [requestFailure]);
  assert.equal(probeHarness.state.launched, true);
  assert.equal(requestHarness.state.launched, true);
});
