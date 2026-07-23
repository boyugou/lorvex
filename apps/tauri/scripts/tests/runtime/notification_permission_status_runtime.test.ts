import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserNotificationPermissionStatusWatchHost,
  installNotificationPermissionStatusWatchRuntime,
  probeNotificationPermissionStatusRuntime,
  requestNotificationPermissionAgainRuntime,
} from '../../../app/src/lib/notifications/permissionStatus.runtime';

test('notification permission probe clears banner when notifications have never been prompted', async () => {
  const bannerStates: boolean[] = [];

  await probeNotificationPermissionStatusRuntime({
    getPersistedGranted: async () => {
      throw new Error('should not read persisted granted');
    },
    getPrompted: async () => false,
    loadNotificationPlugin: async () => {
      throw new Error('should not load plugin');
    },
    refreshNotificationPermissionCache: () => {},
    reportProbeError: () => {
      throw new Error('should not report');
    },
    reportRevokedWhileRunning: () => {
      throw new Error('should not report');
    },
    setPersistedGranted: async () => {
      throw new Error('should not write persisted granted');
    },
    setPromptedButDenied: (value) => {
      bannerStates.push(value);
    },
  });

  assert.deepEqual(bannerStates, [false]);
});

test('notification permission probe persists runtime revocations and surfaces the denied banner', async () => {
  const persistedWrites: boolean[] = [];
  const bannerStates: boolean[] = [];
  let revokedReports = 0;
  let refreshed = 0;

  await probeNotificationPermissionStatusRuntime({
    getPersistedGranted: async () => true,
    getPrompted: async () => true,
    loadNotificationPlugin: async () => ({
      isPermissionGranted: async () => false,
      requestPermission: async () => 'denied',
    }),
    refreshNotificationPermissionCache: () => {
      refreshed += 1;
    },
    reportProbeError: () => {
      throw new Error('should not report generic probe failure');
    },
    reportRevokedWhileRunning: () => {
      revokedReports += 1;
    },
    setPersistedGranted: async (granted) => {
      persistedWrites.push(granted);
    },
    setPromptedButDenied: (value) => {
      bannerStates.push(value);
    },
  });

  assert.equal(refreshed, 1);
  assert.deepEqual(persistedWrites, [false]);
  assert.deepEqual(bannerStates, [true]);
  assert.equal(revokedReports, 1);
});

test('notification permission probe reports failures fail-closed', async () => {
  const errors: unknown[] = [];

  await probeNotificationPermissionStatusRuntime({
    getPersistedGranted: async () => false,
    getPrompted: async () => {
      throw new Error('probe failed');
    },
    loadNotificationPlugin: async () => {
      throw new Error('should not load plugin');
    },
    refreshNotificationPermissionCache: () => {},
    reportProbeError: (error) => {
      errors.push(error);
    },
    reportRevokedWhileRunning: () => {
      throw new Error('should not report revoke');
    },
    setPersistedGranted: async () => {},
    setPromptedButDenied: () => {},
  });

  assert.equal(errors.length, 1);
});

test('notification permission re-request refreshes cache, persists the latest answer, and updates banner state', async () => {
  const persistedWrites: boolean[] = [];
  const bannerStates: boolean[] = [];
  let refreshed = 0;

  await requestNotificationPermissionAgainRuntime({
    loadNotificationPlugin: async () => ({
      isPermissionGranted: async () => false,
      requestPermission: async () => 'granted',
    }),
    refreshNotificationPermissionCache: () => {
      refreshed += 1;
    },
    reportRequestError: () => {
      throw new Error('should not report');
    },
    setPersistedGranted: async (granted) => {
      persistedWrites.push(granted);
    },
    setPromptedButDenied: (value) => {
      bannerStates.push(value);
    },
  });

  assert.equal(refreshed, 1);
  assert.deepEqual(persistedWrites, [true]);
  assert.deepEqual(bannerStates, [false]);
});

test('notification permission re-request reports failures fail-closed', async () => {
  const errors: unknown[] = [];

  await requestNotificationPermissionAgainRuntime({
    loadNotificationPlugin: async () => {
      throw new Error('request failed');
    },
    refreshNotificationPermissionCache: () => {},
    reportRequestError: (error) => {
      errors.push(error);
    },
    setPersistedGranted: async () => {},
    setPromptedButDenied: () => {},
  });

  assert.equal(errors.length, 1);
});

test('notification permission status watcher mounts the initial probe, re-probes on focus and visibility, and tears down cleanly', async () => {
  const calls: string[] = [];
  const focusHandlers = new Set<() => void>();
  const visibilityHandlers = new Set<() => void>();

  const cleanup = installNotificationPermissionStatusWatchRuntime({
    addVisibilityListener: (handler) => {
      visibilityHandlers.add(handler);
      return () => {
        calls.push('remove-visibility');
        visibilityHandlers.delete(handler);
      };
    },
    addWindowFocusListener: (handler) => {
      focusHandlers.add(handler);
      return () => {
        calls.push('remove-focus');
        focusHandlers.delete(handler);
      };
    },
    enabled: true,
    probe: async () => {
      calls.push('probe');
    },
    reportWatchError: () => {
      throw new Error('should not report');
    },
  });

  await new Promise((resolve) => setTimeout(resolve, 0));
  focusHandlers.forEach((handler) => handler());
  visibilityHandlers.forEach((handler) => handler());
  await new Promise((resolve) => setTimeout(resolve, 0));

  cleanup();
  focusHandlers.forEach((handler) => handler());
  visibilityHandlers.forEach((handler) => handler());
  await new Promise((resolve) => setTimeout(resolve, 0));

  assert.deepEqual(calls, [
    'probe',
    'probe',
    'probe',
    'remove-focus',
    'remove-visibility',
  ]);
});

test('notification permission status watcher keeps the initial probe when optional hosts are unavailable', async () => {
  const calls: string[] = [];

  const cleanup = installNotificationPermissionStatusWatchRuntime({
    addVisibilityListener: null,
    addWindowFocusListener: null,
    enabled: true,
    probe: async () => {
      calls.push('probe');
    },
    reportWatchError: () => {
      throw new Error('should not report');
    },
  });

  await new Promise((resolve) => setTimeout(resolve, 0));
  cleanup();
  await new Promise((resolve) => setTimeout(resolve, 0));

  assert.deepEqual(calls, ['probe']);
});

test('notification permission status watcher reports rejected probes without unhandled rejections', async () => {
  const errors: unknown[] = [];
  const unhandledReasons: unknown[] = [];
  const onUnhandledRejection = (reason: unknown) => {
    unhandledReasons.push(reason);
  };

  process.once('unhandledRejection', onUnhandledRejection);
  try {
    const cleanup = installNotificationPermissionStatusWatchRuntime({
      addVisibilityListener: null,
      addWindowFocusListener: null,
      enabled: true,
      probe: async () => {
        throw new Error('watch probe failed');
      },
      reportWatchError: (error: unknown) => {
        errors.push(error);
      },
    });

    await new Promise((resolve) => setTimeout(resolve, 0));
    cleanup();
  } finally {
    process.removeListener('unhandledRejection', onUnhandledRejection);
  }

  assert.equal(unhandledReasons.length, 0);
  assert.equal(errors.length, 1);
  assert.match(String(errors[0]), /watch probe failed/);
});

test('notification permission status watcher reports synchronous probe throws', async () => {
  const errors: unknown[] = [];

  const cleanup = installNotificationPermissionStatusWatchRuntime({
    addVisibilityListener: null,
    addWindowFocusListener: null,
    enabled: true,
    probe: () => {
      throw new Error('sync watch probe failed');
    },
    reportWatchError: (error: unknown) => {
      errors.push(error);
    },
  });

  await new Promise((resolve) => setTimeout(resolve, 0));
  cleanup();

  assert.equal(errors.length, 1);
  assert.match(String(errors[0]), /sync watch probe failed/);
});

test('notification permission status watcher suppresses probes when cleaned up before the deferred start', async () => {
  const calls: string[] = [];

  const cleanup = installNotificationPermissionStatusWatchRuntime({
    addVisibilityListener: null,
    addWindowFocusListener: null,
    enabled: true,
    probe: async () => {
      calls.push('probe');
    },
    reportWatchError: () => {
      throw new Error('should not report');
    },
  });

  cleanup();
  await new Promise((resolve) => setTimeout(resolve, 0));

  assert.deepEqual(calls, []);
});

test('notification permission status watcher suppresses rejected probes after cleanup', async () => {
  const errors: unknown[] = [];
  let rejectProbe: ((error: Error) => void) | null = null;

  const cleanup = installNotificationPermissionStatusWatchRuntime({
    addVisibilityListener: null,
    addWindowFocusListener: null,
    enabled: true,
    probe: async () => new Promise<void>((_resolve, reject) => {
      rejectProbe = reject;
    }),
    reportWatchError: (error: unknown) => {
      errors.push(error);
    },
  });

  await new Promise((resolve) => setTimeout(resolve, 0));
  cleanup();
  rejectProbe?.(new Error('late watch probe failed'));
  await new Promise((resolve) => setTimeout(resolve, 0));

  assert.deepEqual(errors, []);
});

test('browser notification permission status watch host owns foreground listener wiring and cleanup', () => {
  const visibilityHandlers = new Set<() => void>();
  const focusHandlers = new Set<() => void>();
  const originalDocument = globalThis.document;
  const originalWindow = globalThis.window;

  Object.defineProperty(globalThis, 'document', {
    configurable: true,
    value: {
      addEventListener: (event: string, handler: () => void) => {
        assert.equal(event, 'visibilitychange');
        visibilityHandlers.add(handler);
      },
      removeEventListener: (event: string, handler: () => void) => {
        assert.equal(event, 'visibilitychange');
        visibilityHandlers.delete(handler);
      },
    },
  });
  Object.defineProperty(globalThis, 'window', {
    configurable: true,
    value: {
      addEventListener: (event: string, handler: () => void) => {
        assert.equal(event, 'focus');
        focusHandlers.add(handler);
      },
      removeEventListener: (event: string, handler: () => void) => {
        assert.equal(event, 'focus');
        focusHandlers.delete(handler);
      },
    },
  });

  try {
    const host = createBrowserNotificationPermissionStatusWatchHost();
    let runs = 0;
    const removeVisibility = host.addVisibilityListener?.(() => {
      runs += 1;
    });
    const removeFocus = host.addWindowFocusListener?.(() => {
      runs += 1;
    });

    assert.equal(visibilityHandlers.size, 1);
    assert.equal(focusHandlers.size, 1);
    visibilityHandlers.forEach((handler) => handler());
    focusHandlers.forEach((handler) => handler());
    assert.equal(runs, 2);

    removeVisibility?.();
    removeFocus?.();
    assert.equal(visibilityHandlers.size, 0);
    assert.equal(focusHandlers.size, 0);
  } finally {
    Object.defineProperty(globalThis, 'document', {
      configurable: true,
      value: originalDocument,
    });
    Object.defineProperty(globalThis, 'window', {
      configurable: true,
      value: originalWindow,
    });
  }
});

test('notification permission hook delegates optional foreground listeners through runtime seams', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/notifications/usePollingNotifications.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserNotificationPermissionStatusWatchHost,[\s\S]*installNotificationPermissionStatusWatchRuntime,[\s\S]*\} from '\.\/permissionStatus\.runtime';/s,
  );
  assert.match(source, /const notificationPermissionStatusWatchHost = createBrowserNotificationPermissionStatusWatchHost\(\);/);
  assert.match(
    source,
    /return installNotificationPermissionStatusWatchRuntime\(\{[\s\S]*enabled,[\s\S]*probe,[\s\S]*\.\.\.notificationPermissionStatusWatchHost,[\s\S]*\}\);/s,
  );
  assert.doesNotMatch(source, /document\.addEventListener\('visibilitychange'/);
  assert.doesNotMatch(source, /window\.addEventListener\('focus'/);
});
