import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserNetworkStatusRuntimeDeps,
  installNetworkStatusRuntime,
  readBrowserNetworkOnlineStatus,
  readNormalizedOnlineStatus,
  reduceNetworkStatus,
  type NetworkStatusEvent,
} from '../../../app/src/lib/useNetworkStatus.runtime';

test('network status runtime normalizes malformed navigator.onLine values fail-open', () => {
  assert.equal(readNormalizedOnlineStatus(true), true);
  assert.equal(readNormalizedOnlineStatus(false), false);
  assert.equal(readNormalizedOnlineStatus(undefined), true);
  assert.equal(readNormalizedOnlineStatus('offline'), true);
  assert.equal(readNormalizedOnlineStatus(null), true);
});

test('network status runtime installs online/offline listeners, syncs initial state, and cleans up', () => {
  const events: NetworkStatusEvent[] = [];
  const windowListeners = new Map<'online' | 'offline', () => void>();

  const cleanup = installNetworkStatusRuntime({
    addWindowListener: (type, listener) => {
      windowListeners.set(type, listener);
      return () => {
        windowListeners.delete(type);
      };
    },
    dispatch: (event) => {
      events.push(event);
    },
    readOnline: () => false,
  });

  assert.deepEqual(events, [{ type: 'sync', online: false }]);

  windowListeners.get('online')?.();
  windowListeners.get('offline')?.();
  assert.deepEqual(events, [
    { type: 'sync', online: false },
    { type: 'online' },
    { type: 'offline' },
  ]);

  cleanup();
  assert.equal(windowListeners.size, 0);
});

test('network status runtime still performs the initial sync without a window listener host', () => {
  const events: NetworkStatusEvent[] = [];

  const cleanup = installNetworkStatusRuntime({
    addWindowListener: null,
    dispatch: (event) => {
      events.push(event);
    },
    readOnline: () => false,
  });

  assert.deepEqual(events, [{ type: 'sync', online: false }]);
  cleanup();
});

test('network status runtime re-reads online state from connection change via modern listener API', () => {
  const events: NetworkStatusEvent[] = [];
  let changeListener: (() => void) | undefined;
  let online = true;

  const cleanup = installNetworkStatusRuntime({
    addWindowListener: () => () => {},
    connection: {
      addEventListener: (_type, listener) => {
        changeListener = listener;
      },
      removeEventListener: (_type, listener) => {
        if (changeListener === listener) {
          changeListener = undefined;
        }
      },
    },
    dispatch: (event) => {
      events.push(event);
    },
    readOnline: () => online,
  });

  assert.deepEqual(events, [{ type: 'sync', online: true }]);

  online = false;
  changeListener?.();
  assert.deepEqual(events, [
    { type: 'sync', online: true },
    { type: 'sync', online: false },
  ]);

  cleanup();
  assert.equal(changeListener, undefined);
});

test('network status runtime ignores legacy connection addListener/removeListener-only wiring', () => {
  const events: NetworkStatusEvent[] = [];
  let changeListener: (() => void) | undefined;

  const cleanup = installNetworkStatusRuntime({
    addWindowListener: () => () => {},
    connection: {
      addListener: (listener) => {
        changeListener = listener;
      },
      removeListener: (listener) => {
        if (changeListener === listener) {
          changeListener = undefined;
        }
      },
    },
    dispatch: (event) => {
      events.push(event);
    },
    readOnline: () => true,
  });

  changeListener?.();

  assert.deepEqual(events, [{ type: 'sync', online: true }]);

  cleanup();
  assert.equal(changeListener, undefined);
});

test('network status runtime ignores connection objects without a removable listener contract', () => {
  const events: NetworkStatusEvent[] = [];
  let addCalls = 0;

  const cleanup = installNetworkStatusRuntime({
    addWindowListener: () => () => {},
    connection: {
      addEventListener: () => {
        addCalls += 1;
      },
    },
    dispatch: (event) => {
      events.push(event);
    },
    readOnline: () => true,
  });

  assert.equal(addCalls, 0);
  assert.deepEqual(events, [{ type: 'sync', online: true }]);
  cleanup();
});

test('network status browser runtime owns host online reads and listener wiring', () => {
  const originalWindow = globalThis.window;
  const originalNavigator = globalThis.navigator;
  const listeners = new Map<string, () => void>();
  const connectionListeners = new Map<string, () => void>();
  const events: NetworkStatusEvent[] = [];

  Object.defineProperty(globalThis, 'window', {
    configurable: true,
    value: {
      addEventListener: (type: string, listener: () => void) => {
        listeners.set(type, listener);
      },
      removeEventListener: (type: string, listener: () => void) => {
        if (listeners.get(type) === listener) {
          listeners.delete(type);
        }
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
          if (connectionListeners.get(type) === listener) {
            connectionListeners.delete(type);
          }
        },
      },
    },
  });

  try {
    assert.equal(readBrowserNetworkOnlineStatus(), false);
    const deps = createBrowserNetworkStatusRuntimeDeps((event) => {
      events.push(event);
    });
    const cleanup = installNetworkStatusRuntime(deps);

    assert.deepEqual(events, [{ type: 'sync', online: false }]);
    assert.equal(listeners.has('online'), true);
    assert.equal(listeners.has('offline'), true);
    assert.equal(connectionListeners.has('change'), true);

    cleanup();
    assert.equal(listeners.size, 0);
    assert.equal(connectionListeners.size, 0);
  } finally {
    Object.defineProperty(globalThis, 'window', {
      configurable: true,
      value: originalWindow,
    });
    Object.defineProperty(globalThis, 'navigator', {
      configurable: true,
      value: originalNavigator,
    });
  }
});

test('network status browser runtime fails open without browser hosts', () => {
  const originalWindow = globalThis.window;
  const originalNavigator = globalThis.navigator;
  const events: NetworkStatusEvent[] = [];

  Object.defineProperty(globalThis, 'window', {
    configurable: true,
    value: undefined,
  });
  Object.defineProperty(globalThis, 'navigator', {
    configurable: true,
    value: undefined,
  });

  try {
    assert.equal(readBrowserNetworkOnlineStatus(), true);
    const cleanup = installNetworkStatusRuntime(
      createBrowserNetworkStatusRuntimeDeps((event) => {
        events.push(event);
      }),
    );

    assert.deepEqual(events, [{ type: 'sync', online: true }]);
    cleanup();
  } finally {
    Object.defineProperty(globalThis, 'window', {
      configurable: true,
      value: originalWindow,
    });
    Object.defineProperty(globalThis, 'navigator', {
      configurable: true,
      value: originalNavigator,
    });
  }
});

test('network status hook delegates reducer and browser wiring to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/useNetworkStatus.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserNetworkStatusRuntimeDeps,[\s\S]*installNetworkStatusRuntime,[\s\S]*readBrowserNetworkOnlineStatus,[\s\S]*reduceNetworkStatus,[\s\S]*\} from '\.\/useNetworkStatus\.runtime';/s,
  );
  assert.match(
    source,
    /return installNetworkStatusRuntime\(\s*createBrowserNetworkStatusRuntimeDeps\(\(event\) => \{[\s\S]*reduceNetworkStatus\(\{ online: current \}, event\)\.online/s,
  );
  assert.doesNotMatch(source, /\bwindow\b/);
  assert.doesNotMatch(source, /\bnavigator\b/);
  assert.doesNotMatch(source, /export function reduceNetworkStatus/);
  assert.equal(reduceNetworkStatus({ online: true }, { type: 'sync', online: false }).online, false);
});
