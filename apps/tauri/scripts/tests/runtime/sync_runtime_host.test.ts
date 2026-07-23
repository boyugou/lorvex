import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  type BackgroundSyncPendingWait,
  createBackgroundSyncBrowserHost,
  createBrowserBackgroundSyncBrowserHost,
} from '../../../app/src/lib/sync/runtime.host';

test('background sync browser host guards optional browser globals and cleans up listeners', async () => {
  const windowListeners = new Map<string, () => void>();
  const documentListeners = new Map<string, () => void>();
  const connectionListeners = new Map<string, () => void>();
  const clearedTimeouts: unknown[] = [];
  const scheduledTimeouts: Array<{ callback: () => void; delayMs: number }> = [];
  let nextHandle = 0;
  const pendingWaits = new Set<BackgroundSyncPendingWait>();

  const host = createBackgroundSyncBrowserHost({
    windowTarget: {
      addEventListener: (type, listener) => {
        windowListeners.set(type, listener as () => void);
      },
      removeEventListener: (type, listener) => {
        if (windowListeners.get(type) === listener) {
          windowListeners.delete(type);
        }
      },
    },
    documentTarget: {
      visibilityState: 'hidden',
      addEventListener: (type, listener) => {
        documentListeners.set(type, listener as () => void);
      },
      removeEventListener: (type, listener) => {
        if (documentListeners.get(type) === listener) {
          documentListeners.delete(type);
        }
      },
    },
    navigatorState: { onLine: false },
    connectionTarget: {
      addEventListener: (type, listener) => {
        connectionListeners.set(type, listener);
      },
      removeEventListener: (type, listener) => {
        if (connectionListeners.get(type) === listener) {
          connectionListeners.delete(type);
        }
      },
    },
    timerHost: {
      setTimeout: (callback, delayMs) => {
        scheduledTimeouts.push({ callback, delayMs: Number(delayMs) });
        nextHandle += 1;
        return nextHandle as ReturnType<typeof globalThis.setTimeout>;
      },
      clearTimeout: (handle) => {
        clearedTimeouts.push(handle);
      },
    },
  });

  assert.equal(host.isOnline(), false);
  assert.equal(host.isVisible(), false);

  const removeFocus = host.addWindowListener('focus', () => {});
  const removeVisibility = host.addVisibilityListener(() => {});
  const removeConnection = host.addConnectionChangeListener(() => {});
  assert.equal(windowListeners.size, 1);
  assert.equal(documentListeners.size, 1);
  assert.equal(connectionListeners.size, 1);

  const cancelCadence = host.setTimeout(() => {}, 5_000);
  assert.equal(scheduledTimeouts[0]?.delayMs, 5_000);
  cancelCadence();
  assert.deepEqual(clearedTimeouts, [1]);

  const waitPromise = host.wait(2_000, () => false, pendingWaits);
  assert.equal(pendingWaits.size, 1);
  scheduledTimeouts[1]?.callback();
  await waitPromise;
  assert.equal(pendingWaits.size, 0);

  const clearedWaitPromise = host.wait(1_500, () => false, pendingWaits);
  host.clearPendingWaits(pendingWaits);
  assert.deepEqual(clearedTimeouts, [1, 3]);
  assert.equal(pendingWaits.size, 0);
  await Promise.race([
    clearedWaitPromise,
    Promise.resolve().then(() => {
      throw new Error('cleared wait did not resolve synchronously');
    }),
  ]);

  removeConnection();
  removeVisibility();
  removeFocus();
  assert.equal(connectionListeners.size, 0);
  assert.equal(documentListeners.size, 0);
  assert.equal(windowListeners.size, 0);
});

test('background sync browser host fails open without browser globals', async () => {
  const pendingWaits = new Set<BackgroundSyncPendingWait>();
  const scheduledCallbacks: Array<() => void> = [];
  const host = createBackgroundSyncBrowserHost({
    timerHost: {
      setTimeout: (callback) => {
        scheduledCallbacks.push(callback);
        return 1 as ReturnType<typeof globalThis.setTimeout>;
      },
      clearTimeout: () => {},
    },
  });

  assert.equal(host.isOnline(), true);
  assert.equal(host.isVisible(), true);
  host.addWindowListener('online', () => {})();
  host.addVisibilityListener(() => {})();
  host.addConnectionChangeListener(() => {})();
  const waitPromise = host.wait(0, () => false, pendingWaits);
  scheduledCallbacks[0]?.();
  await waitPromise;
  assert.equal(pendingWaits.size, 0);
});

test('browser background sync host owns default browser global wiring', () => {
  const windowListeners = new Map<string, () => void>();
  const documentListeners = new Map<string, () => void>();
  const connectionListeners = new Map<string, () => void>();
  const originalWindow = globalThis.window;
  const originalDocument = globalThis.document;
  const originalNavigator = globalThis.navigator;

  Object.defineProperty(globalThis, 'window', {
    configurable: true,
    value: {
      addEventListener: (type: string, listener: () => void) => {
        windowListeners.set(type, listener);
      },
      removeEventListener: (type: string, listener: () => void) => {
        if (windowListeners.get(type) === listener) windowListeners.delete(type);
      },
    },
  });
  Object.defineProperty(globalThis, 'document', {
    configurable: true,
    value: {
      visibilityState: 'visible',
      addEventListener: (type: string, listener: () => void) => {
        documentListeners.set(type, listener);
      },
      removeEventListener: (type: string, listener: () => void) => {
        if (documentListeners.get(type) === listener) documentListeners.delete(type);
      },
    },
  });
  Object.defineProperty(globalThis, 'navigator', {
    configurable: true,
    value: {
      onLine: false,
      connection: {
        addEventListener: (type: string, listener: () => void) => {
          connectionListeners.set(type, listener);
        },
        removeEventListener: (type: string, listener: () => void) => {
          if (connectionListeners.get(type) === listener) connectionListeners.delete(type);
        },
      },
    },
  });

  try {
    const host = createBrowserBackgroundSyncBrowserHost();

    assert.equal(host.isOnline(), false);
    assert.equal(host.isVisible(), true);
    const removeFocus = host.addWindowListener('focus', () => {});
    const removeVisibility = host.addVisibilityListener(() => {});
    const removeConnection = host.addConnectionChangeListener(() => {});
    const cancel = host.setTimeout(() => {}, 10);

    assert.equal(windowListeners.size, 1);
    assert.equal(documentListeners.size, 1);
    assert.equal(connectionListeners.size, 1);

    cancel();
    removeConnection();
    removeVisibility();
    removeFocus();
    assert.equal(windowListeners.size, 0);
    assert.equal(documentListeners.size, 0);
    assert.equal(connectionListeners.size, 0);
  } finally {
    Object.defineProperty(globalThis, 'window', { configurable: true, value: originalWindow });
    Object.defineProperty(globalThis, 'document', { configurable: true, value: originalDocument });
    Object.defineProperty(globalThis, 'navigator', { configurable: true, value: originalNavigator });
  }
});

test('background sync hook delegates browser host wiring to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/sync/runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{ createBrowserBackgroundSyncBrowserHost \} from '\.\/runtime\.host';/,
  );
  assert.match(
    source,
    /const browserHost = createBrowserBackgroundSyncBrowserHost\(\);/,
  );
  assert.match(
    source,
    /const removeFocusListener = browserHost\.addWindowListener\('focus', onWindowFocus\);[\s\S]*const removeConnectionListener = browserHost\.addConnectionChangeListener\(onConnectionChange\);/s,
  );
  assert.doesNotMatch(source, /window\.addEventListener\('/);
  assert.doesNotMatch(source, /document\.addEventListener\('/);
  assert.doesNotMatch(source, /window\.setTimeout\(/);
  assert.doesNotMatch(source, /window\.clearTimeout\(/);
  assert.doesNotMatch(source, /navigator\.onLine/);
  assert.doesNotMatch(source, /typeof window|typeof document|typeof navigator|globalThis/);
});
