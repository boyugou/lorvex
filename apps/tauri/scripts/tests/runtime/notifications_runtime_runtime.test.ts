import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserNotificationPermissionVisibilityRefreshHost,
  installNotificationPermissionVisibilityRefreshRuntime,
  refreshNotificationPermissionCacheState,
  sendNotificationRuntime,
  type NotificationPermissionCacheState,
  type NotificationPlugin,
} from '../../../app/src/lib/notifications/runtime.runtime';

test('notification permission cache refresh resets to unknown', () => {
  const cacheState: NotificationPermissionCacheState = { current: false };
  refreshNotificationPermissionCacheState(cacheState);
  assert.equal(cacheState.current, null);
});

test('notification permission visibility refresh only clears the cache when the document is visible', () => {
  const events: Array<() => void> = [];
  let refreshes = 0;
  let visibilityState: DocumentVisibilityState = 'hidden';

  installNotificationPermissionVisibilityRefreshRuntime({
    addVisibilityListener: (handler) => {
      events.push(handler);
    },
    getVisibilityState: () => visibilityState,
    refreshPermissionCache: () => {
      refreshes += 1;
    },
  });

  events[0]?.();
  visibilityState = 'visible';
  events[0]?.();

  assert.equal(refreshes, 1);
});

test('notification permission visibility refresh is a no-op without a visibility host', () => {
  let refreshes = 0;

  installNotificationPermissionVisibilityRefreshRuntime({
    addVisibilityListener: null,
    getVisibilityState: () => 'visible',
    refreshPermissionCache: () => {
      refreshes += 1;
    },
  });

  assert.equal(refreshes, 0);
});

test('browser notification permission visibility refresh host owns document listener and state reads', () => {
  const handlers: Array<() => void> = [];
  const originalDocument = globalThis.document;
  let visibilityState: DocumentVisibilityState = 'hidden';

  Object.defineProperty(globalThis, 'document', {
    configurable: true,
    value: {
      addEventListener: (event: string, handler: () => void) => {
        assert.equal(event, 'visibilitychange');
        handlers.push(handler);
      },
      get visibilityState() {
        return visibilityState;
      },
    },
  });

  try {
    const host = createBrowserNotificationPermissionVisibilityRefreshHost();
    host.addVisibilityListener?.(() => {});

    assert.equal(handlers.length, 1);
    assert.equal(host.getVisibilityState(), 'hidden');
    visibilityState = 'visible';
    assert.equal(host.getVisibilityState(), 'visible');
  } finally {
    Object.defineProperty(globalThis, 'document', {
      configurable: true,
      value: originalDocument,
    });
  }
});

test('notifications runtime delegates permission-cache visibility refresh through an optional document host seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/notifications/runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserNotificationPermissionVisibilityRefreshHost,[\s\S]*installNotificationPermissionVisibilityRefreshRuntime,[\s\S]*\} from '\.\/runtime\.runtime';/s,
  );
  assert.match(source, /const notificationPermissionVisibilityRefreshHost = createBrowserNotificationPermissionVisibilityRefreshHost\(\);/);
  assert.match(
    source,
    /installNotificationPermissionVisibilityRefreshRuntime\(\{[\s\S]*\.\.\.notificationPermissionVisibilityRefreshHost,[\s\S]*refreshPermissionCache: refreshNotificationPermissionCache,[\s\S]*\}\);/s,
  );
  assert.doesNotMatch(source, /document\.addEventListener\('visibilitychange'/);
  assert.doesNotMatch(source, /document\.visibilityState/);
});

test('sendNotificationRuntime short-circuits when permission was already denied in-session', async () => {
  const cacheState: NotificationPermissionCacheState = { current: false };
  let loaded = 0;

  const result = await sendNotificationRuntime({
    cacheState,
    getSoundEnabled: async () => true,
    isInQuietHours: async () => false,
    loadNotificationPlugin: async () => {
      loaded += 1;
      throw new Error('should not load');
    },
    options: { title: 'Hello' },
    reportDispatchError: () => {
      throw new Error('should not report');
    },
    reportPermissionDenied: () => {
      throw new Error('should not report');
    },
  });

  assert.equal(result, 'suppressed_permission');
  assert.equal(loaded, 0);
});

test('sendNotificationRuntime suppresses notifications during quiet hours before loading the plugin', async () => {
  const cacheState: NotificationPermissionCacheState = { current: null };
  let loaded = 0;

  const result = await sendNotificationRuntime({
    cacheState,
    getSoundEnabled: async () => true,
    isInQuietHours: async () => true,
    loadNotificationPlugin: async () => {
      loaded += 1;
      throw new Error('should not load');
    },
    options: { title: 'Hello' },
    reportDispatchError: () => {
      throw new Error('should not report');
    },
    reportPermissionDenied: () => {
      throw new Error('should not report');
    },
  });

  assert.equal(result, 'suppressed_quiet_hours');
  assert.equal(loaded, 0);
  assert.equal(cacheState.current, null);
});

test('sendNotificationRuntime probes permission once, sends with silent=false by default, and caches granted state', async () => {
  const cacheState: NotificationPermissionCacheState = { current: null };
  const sent: Array<{ title: string; silent: boolean }> = [];
  let permissionChecks = 0;
  const plugin: NotificationPlugin = {
    isPermissionGranted: async () => {
      permissionChecks += 1;
      return true;
    },
    sendNotification: (options) => {
      sent.push({ title: options.title, silent: options.silent });
    },
  };

  const result = await sendNotificationRuntime({
    cacheState,
    getSoundEnabled: async () => true,
    isInQuietHours: async () => false,
    loadNotificationPlugin: async () => plugin,
    options: { title: 'Hello' },
    reportDispatchError: () => {
      throw new Error('should not report');
    },
    reportPermissionDenied: () => {
      throw new Error('should not report');
    },
  });

  assert.equal(result, 'sent');
  assert.equal(permissionChecks, 1);
  assert.equal(cacheState.current, true);
  assert.deepEqual(sent, [{ title: 'Hello', silent: false }]);
});

test('sendNotificationRuntime re-probes permission after a send failure, suppresses later attempts, and only reports the denial once', async () => {
  const cacheState: NotificationPermissionCacheState = { current: null };
  const deniedReports: unknown[] = [];
  let loadCount = 0;
  let permissionChecks = 0;
  const plugin: NotificationPlugin = {
    isPermissionGranted: async () => {
      permissionChecks += 1;
      return permissionChecks === 1;
    },
    sendNotification: () => {
      throw new Error('denied');
    },
  };

  const deps = {
    cacheState,
    getSoundEnabled: async () => true,
    isInQuietHours: async () => false,
    loadNotificationPlugin: async () => {
      loadCount += 1;
      return plugin;
    },
    options: { title: 'Hello' },
    reportDispatchError: () => {
      throw new Error('should not report generic failure');
    },
    reportPermissionDenied: (error: unknown) => {
      deniedReports.push(error);
    },
  } satisfies Parameters<typeof sendNotificationRuntime>[0];

  const first = await sendNotificationRuntime(deps);
  const second = await sendNotificationRuntime(deps);

  assert.equal(first, 'suppressed_permission');
  assert.equal(second, 'suppressed_permission');
  assert.equal(cacheState.current, false);
  assert.equal(loadCount, 2);
  assert.equal(permissionChecks, 2);
  assert.equal(deniedReports.length, 1);
});

test('sendNotificationRuntime falls back to generic dispatch reporting when permission re-probe also fails', async () => {
  const cacheState: NotificationPermissionCacheState = { current: null };
  const reports: unknown[] = [];
  const plugin: NotificationPlugin = {
    isPermissionGranted: async () => {
      throw new Error('probe failed');
    },
    sendNotification: () => {
      throw new Error('dispatch failed');
    },
  };

  const result = await sendNotificationRuntime({
    cacheState,
    getSoundEnabled: async () => false,
    isInQuietHours: async () => false,
    loadNotificationPlugin: async () => plugin,
    options: { title: 'Hello' },
    reportDispatchError: (error) => {
      reports.push(error);
    },
    reportPermissionDenied: () => {
      throw new Error('should not report denial');
    },
  });

  assert.equal(result, 'failed');
  assert.equal(reports.length, 1);
});
