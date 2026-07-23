import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserCalendarSubscriptionSyncRuntimeDeps,
  startCalendarSubscriptionSyncRuntime,
} from '../../../app/src/lib/calendarSubscriptionSync.runtime';
import {
  createBrowserDayContextRolloverRuntimeDeps,
  startDayContextRolloverRuntime,
  shouldHandleDayContextVisibilityWake,
} from '../../../app/src/lib/dayContextProvider.runtime';
import { startVisibilityGatedIntervalRuntime } from '../../../app/src/lib/time/intervalHooks.runtime';
import { startExternalMutationSubscriptionRuntime } from '../../../app/src/lib/useExternalMutationSubscription.runtime';
import { startMainWindowDeepLinkSubscriptionRuntime } from '../../../app/src/app-shell/main-window/runtime/useMainWindowDeepLinkSubscription.runtime';
import type { DeepLinkTarget } from '../../../app/src/lib/ipc';

const repoRoot = process.cwd();

function createDeferredPromise<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

test('app lib timer logic defaults delegate browser timeout wiring to the shared timeout seam', () => {
  const timerLogicFiles = [
    'app/src/lib/useExternalMutationSubscription.logic.ts',
    'app/src/lib/useFontScale.logic.ts',
    'app/src/lib/useLongPress.logic.ts',
  ];

  for (const file of timerLogicFiles) {
    const source = fs.readFileSync(path.join(repoRoot, file), 'utf8');
    assert.match(source, /from '\.{1,2}\/browserTimeoutTimerApi';/);
    assert.doesNotMatch(source, /(?<!\.)\bsetTimeout\(/);
    assert.doesNotMatch(source, /(?<!\.)\bclearTimeout\(/);
  }
});

test('external mutation runtime runs catch-up once after both listeners settle even when one listener fails', async () => {
  const invalidations: string[] = [];
  const reported: string[] = [];

  const dispose = startExternalMutationSubscriptionRuntime({
    ownWindowLabel: 'main',
    invalidateExternalMutationQueries: () => {
      invalidations.push('catchup');
    },
    invalidateQueriesForEntity: (entity) => {
      invalidations.push(entity);
    },
    reportError: (scope) => {
      reported.push(scope);
    },
    listenMutationBroadcast: async () => () => {},
    listenDataChanged: async () => {
      throw new Error('data changed unavailable');
    },
  });

  await new Promise((resolve) => setTimeout(resolve, 0));
  dispose();

  assert.deepEqual(invalidations, ['catchup']);
  assert.deepEqual(reported, ['external.listen.dataChanged']);
});

test('external mutation runtime tears down late listener resolutions after cleanup and suppresses catch-up', async () => {
  const mutationListen = createDeferredPromise<() => void>();
  const dataChangedListen = createDeferredPromise<() => void>();
  let mutationUnlistenCalls = 0;
  let dataChangedUnlistenCalls = 0;
  let catchupCalls = 0;
  let coalescerClears = 0;

  const dispose = startExternalMutationSubscriptionRuntime({
    ownWindowLabel: 'main',
    invalidateExternalMutationQueries: () => {
      catchupCalls += 1;
    },
    invalidateQueriesForEntity: () => {},
    reportError: () => {},
    listenMutationBroadcast: async () => mutationListen.promise,
    listenDataChanged: async () => dataChangedListen.promise,
    createCoalescer: () => ({
      schedule() {},
      clear() {
        coalescerClears += 1;
      },
    }),
  });

  dispose();

  mutationListen.resolve(() => {
    mutationUnlistenCalls += 1;
  });
  dataChangedListen.resolve(() => {
    dataChangedUnlistenCalls += 1;
  });

  await new Promise((resolve) => setTimeout(resolve, 0));

  assert.equal(catchupCalls, 0);
  assert.equal(coalescerClears, 1);
  assert.equal(mutationUnlistenCalls, 1);
  assert.equal(dataChangedUnlistenCalls, 1);
});

test('main-window deep-link runtime drains pending links only after listener registration settles', async () => {
  const listenerRegistration = createDeferredPromise<() => void>();
  const applied: Array<DeepLinkTarget | null> = [];
  const consumed: string[] = [];
  const taskTarget: DeepLinkTarget = { route: 'task', task_id: 'task-1' };
  const todayTarget: DeepLinkTarget = { route: 'today', task_id: null };
  let openHandler: ((payload: DeepLinkTarget | null | undefined) => void) | undefined;

  const dispose = startMainWindowDeepLinkSubscriptionRuntime({
    applyDeepLinkTarget: (target) => {
      applied.push(target);
    },
    listenDeepLinkOpen: async (handler) => {
      openHandler = handler;
      return listenerRegistration.promise;
    },
    consumePendingDeepLink: async () => {
      consumed.push('consume');
      return consumed.length === 1 ? todayTarget : null;
    },
    acknowledgePendingDeepLink: async () => true,
    reportError: () => {},
  });

  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.deepEqual(consumed, []);

  listenerRegistration.resolve(() => {});
  await new Promise((resolve) => setTimeout(resolve, 0));
  await new Promise((resolve) => setTimeout(resolve, 0));

  openHandler?.(taskTarget);
  dispose();

  assert.deepEqual(consumed, ['consume', 'consume']);
  assert.deepEqual(applied, [todayTarget, taskTarget]);
});

test('main-window deep-link runtime ignores malformed event payloads without acknowledging them', async () => {
  const listenerRegistration = createDeferredPromise<() => void>();
  const applied: Array<DeepLinkTarget | null> = [];
  const acknowledged: DeepLinkTarget[] = [];
  const reports: string[] = [];
  let openHandler: ((payload: unknown) => void) | undefined;

  startMainWindowDeepLinkSubscriptionRuntime({
    applyDeepLinkTarget: (target) => {
      applied.push(target);
    },
    listenDeepLinkOpen: async (handler) => {
      openHandler = handler as (payload: unknown) => void;
      return listenerRegistration.promise;
    },
    consumePendingDeepLink: async () => null,
    acknowledgePendingDeepLink: async (payload) => {
      acknowledged.push(payload);
      return true;
    },
    reportError: (scope) => {
      reports.push(scope);
    },
  });

  listenerRegistration.resolve(() => {});
  await new Promise((resolve) => setTimeout(resolve, 0));

  openHandler?.({ route: 'task', task_id: 42 });

  assert.deepEqual(applied, []);
  assert.deepEqual(acknowledged, []);
  assert.deepEqual(reports, ['app.deepLink.invalidPayload']);
});

test('main-window deep-link runtime validates pending links before applying them', async () => {
  const listenerRegistration = createDeferredPromise<() => void>();
  const applied: Array<DeepLinkTarget | null> = [];
  const reports: string[] = [];
  const validTarget: DeepLinkTarget = { route: 'today', task_id: null };
  let consumeCalls = 0;

  startMainWindowDeepLinkSubscriptionRuntime({
    applyDeepLinkTarget: (target) => {
      applied.push(target);
    },
    listenDeepLinkOpen: async () => listenerRegistration.promise,
    consumePendingDeepLink: async () => {
      consumeCalls += 1;
      if (consumeCalls === 1) return { route: 'missing', task_id: null } as unknown as DeepLinkTarget;
      if (consumeCalls === 2) return validTarget;
      return null;
    },
    acknowledgePendingDeepLink: async () => true,
    reportError: (scope) => {
      reports.push(scope);
    },
  });

  listenerRegistration.resolve(() => {});
  await new Promise((resolve) => setTimeout(resolve, 0));
  await new Promise((resolve) => setTimeout(resolve, 0));

  assert.deepEqual(applied, [validTarget]);
  assert.deepEqual(reports, ['app.deepLink.invalidPayload']);
});

test('main-window deep-link runtime suppresses pending drain and unlistens late registration after cleanup', async () => {
  const listenerRegistration = createDeferredPromise<() => void>();
  let unlistenCalls = 0;
  let consumeCalls = 0;
  let applyCalls = 0;

  const dispose = startMainWindowDeepLinkSubscriptionRuntime({
    applyDeepLinkTarget: () => {
      applyCalls += 1;
    },
    listenDeepLinkOpen: async () => listenerRegistration.promise,
    consumePendingDeepLink: async () => {
      consumeCalls += 1;
      return { route: 'today', task_id: null };
    },
    acknowledgePendingDeepLink: async () => true,
    reportError: () => {},
  });

  dispose();
  listenerRegistration.resolve(() => {
    unlistenCalls += 1;
  });
  await new Promise((resolve) => setTimeout(resolve, 0));

  assert.equal(unlistenCalls, 1);
  assert.equal(consumeCalls, 0);
  assert.equal(applyCalls, 0);
});

test('calendar subscription sync runtime wires timers and wake-up listeners through the controller', () => {
  const calls: string[] = [];
  const timeouts: Array<{ callback: () => void; delayMs: number }> = [];
  const intervals: Array<{ callback: () => void; delayMs: number }> = [];
  const onlineHandlers = new Set<() => void>();
  const connectionHandlers = new Set<() => void>();

  const dispose = startCalendarSubscriptionSyncRuntime({
    controller: {
      async trySync() {
        calls.push('sync');
        return true;
      },
      async handleOnline() {
        calls.push('online');
        return true;
      },
      async handleConnectionChange() {
        calls.push('connection');
        return true;
      },
    },
    initialDelayMs: 10_000,
    intervalMs: 3_600_000,
    windowTarget: {
      addEventListener(type, handler) {
        if (type === 'online') onlineHandlers.add(handler as () => void);
      },
      removeEventListener(type, handler) {
        if (type === 'online') onlineHandlers.delete(handler as () => void);
      },
    } as unknown as Window,
    connectionTarget: {
      addEventListener(type, handler) {
        if (type === 'change') connectionHandlers.add(handler as () => void);
      },
      removeEventListener(type, handler) {
        if (type === 'change') connectionHandlers.delete(handler as () => void);
      },
    },
    setTimeout(callback, delayMs) {
      timeouts.push({ callback, delayMs: Number(delayMs) });
      return timeouts.length as unknown as ReturnType<typeof globalThis.setTimeout>;
    },
    clearTimeout() {},
    setInterval(callback, delayMs) {
      intervals.push({ callback, delayMs: Number(delayMs) });
      return intervals.length as unknown as ReturnType<typeof globalThis.setInterval>;
    },
    clearInterval() {},
  });

  assert.deepEqual(
    { timeout: timeouts[0]?.delayMs, interval: intervals[0]?.delayMs },
    { timeout: 10_000, interval: 3_600_000 },
  );
  assert.equal(onlineHandlers.size, 1);
  assert.equal(connectionHandlers.size, 1);

  timeouts[0]?.callback();
  intervals[0]?.callback();
  [...onlineHandlers][0]?.();
  [...connectionHandlers][0]?.();

  assert.deepEqual(calls, ['sync', 'sync', 'online', 'connection']);
  dispose();
});

test('calendar subscription sync runtime cleanup clears timers and unregisters optional listeners', () => {
  const clearedTimeouts: unknown[] = [];
  const clearedIntervals: unknown[] = [];
  const onlineHandlers = new Set<() => void>();

  const dispose = startCalendarSubscriptionSyncRuntime({
    controller: {
      async trySync() { return true; },
      async handleOnline() { return true; },
      async handleConnectionChange() { return true; },
    },
    initialDelayMs: 1_000,
    intervalMs: 2_000,
    windowTarget: {
      addEventListener(type, handler) {
        if (type === 'online') onlineHandlers.add(handler as () => void);
      },
      removeEventListener(type, handler) {
        if (type === 'online') onlineHandlers.delete(handler as () => void);
      },
    } as unknown as Window,
    connectionTarget: null,
    setTimeout() {
      return 'timeout-token' as unknown as ReturnType<typeof globalThis.setTimeout>;
    },
    clearTimeout(handle) {
      clearedTimeouts.push(handle);
    },
    setInterval() {
      return 'interval-token' as unknown as ReturnType<typeof globalThis.setInterval>;
    },
    clearInterval(handle) {
      clearedIntervals.push(handle);
    },
  });

  dispose();

  assert.deepEqual(clearedTimeouts, ['timeout-token']);
  assert.deepEqual(clearedIntervals, ['interval-token']);
  assert.equal(onlineHandlers.size, 0);
});

test('calendar subscription sync browser runtime deps own host wiring and tolerate missing hosts', () => {
  const originalWindow = globalThis.window;
  const originalNavigator = globalThis.navigator;
  const onlineHandlers = new Set<() => void>();
  const connectionHandlers = new Set<() => void>();
  const controller = {
    async trySync() { return true; },
    async handleOnline() { return true; },
    async handleConnectionChange() { return true; },
  };

  Object.defineProperty(globalThis, 'window', {
    configurable: true,
    value: {
      addEventListener(type: string, handler: () => void) {
        if (type === 'online') onlineHandlers.add(handler);
      },
      removeEventListener(type: string, handler: () => void) {
        if (type === 'online') onlineHandlers.delete(handler);
      },
    },
  });
  Object.defineProperty(globalThis, 'navigator', {
    configurable: true,
    value: {
      connection: {
        addEventListener(type: string, handler: () => void) {
          if (type === 'change') connectionHandlers.add(handler);
        },
        removeEventListener(type: string, handler: () => void) {
          if (type === 'change') connectionHandlers.delete(handler);
        },
      },
    },
  });

  try {
    const deps = createBrowserCalendarSubscriptionSyncRuntimeDeps({
      controller,
      initialDelayMs: 1,
      intervalMs: 2,
    });
    const dispose = startCalendarSubscriptionSyncRuntime(deps);
    assert.equal(onlineHandlers.size, 1);
    assert.equal(connectionHandlers.size, 1);
    dispose();
    assert.equal(onlineHandlers.size, 0);
    assert.equal(connectionHandlers.size, 0);

    Object.defineProperty(globalThis, 'window', {
      configurable: true,
      value: undefined,
    });
    Object.defineProperty(globalThis, 'navigator', {
      configurable: true,
      value: undefined,
    });

    assert.doesNotThrow(() => {
      startCalendarSubscriptionSyncRuntime(
        createBrowserCalendarSubscriptionSyncRuntimeDeps({
          controller,
          initialDelayMs: 1,
          intervalMs: 2,
        }),
      )();
    });
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

test('calendar subscription sync hook delegates browser runtime deps to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/calendarSubscriptionSync.ts'),
    'utf8',
  );

  assert.match(source, /createBrowserCalendarSubscriptionSyncRuntimeDeps/);
  assert.doesNotMatch(source, /\bnavigator\b/);
  assert.doesNotMatch(source, /windowTarget:\s*window/);
  assert.doesNotMatch(source, /connectionTarget:\s*getNavigatorConnection/);
  assert.doesNotMatch(source, /\bsetTimeout,/);
  assert.doesNotMatch(source, /\bclearTimeout,/);
  assert.doesNotMatch(source, /\bsetInterval,/);
  assert.doesNotMatch(source, /\bclearInterval,/);
});

test('calendar subscription sync runtime keeps timer wiring behind explicit deps', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/calendarSubscriptionSync.runtime.ts'),
    'utf8',
  );

  assert.doesNotMatch(source, /(?<!\.)\bsetTimeout\(/);
  assert.doesNotMatch(source, /(?<!\.)\bclearTimeout\(/);
  assert.doesNotMatch(source, /(?<!\.)\bsetInterval\(/);
  assert.doesNotMatch(source, /(?<!\.)\bclearInterval\(/);
  assert.match(source, /timerHost\.setTimeout\(/);
  assert.match(source, /timerHost\.clearTimeout\(/);
  assert.match(source, /timerHost\.setInterval\(/);
  assert.match(source, /timerHost\.clearInterval\(/);
});

test('visibility-gated interval runtime mounts, reacts to visibility changes, and removes its listener on cleanup', () => {
  const calls: string[] = [];
  const visibilityHandlers = new Set<() => void>();
  let visible = true;

  const dispose = startVisibilityGatedIntervalRuntime({
    intervalMs: 60_000,
    documentTarget: {
      addEventListener(type, handler) {
        if (type === 'visibilitychange') visibilityHandlers.add(handler as () => void);
      },
      removeEventListener(type, handler) {
        if (type === 'visibilitychange') visibilityHandlers.delete(handler as () => void);
      },
    } as unknown as Document,
    host: {
      isVisible: () => visible,
      runTick: () => {
        calls.push('tick');
      },
      setInterval: () => {
        calls.push('arm');
        return () => {
          calls.push('disarm');
        };
      },
    },
  });

  assert.deepEqual(calls, ['tick', 'arm']);
  visible = false;
  [...visibilityHandlers][0]?.();
  visible = true;
  [...visibilityHandlers][0]?.();
  dispose();

  assert.deepEqual(calls, ['tick', 'arm', 'disarm', 'tick', 'arm', 'disarm']);
  assert.equal(visibilityHandlers.size, 0);
});

test('day-context rollover runtime wakes only for visible visibility changes, always on focus, and removes listeners on cleanup', () => {
  const visibilityHandlers = new Set<() => void>();
  const focusHandlers = new Set<() => void>();
  const calls: string[] = [];
  let visibilityState: DocumentVisibilityState = 'hidden';
  let currentYmd = '2026-04-23';

  const dispose = startDayContextRolloverRuntime({
    host: {
      getCurrentYmd: () => currentYmd,
      getDelayMs: () => 10_000,
      onRollover: () => {
        calls.push('rollover');
      },
      setTimeout: () => {
        calls.push('arm');
        return () => {
          calls.push('disarm');
        };
      },
    },
    documentTarget: {
      get visibilityState() {
        return visibilityState;
      },
      addEventListener(type, handler) {
        if (type === 'visibilitychange') visibilityHandlers.add(handler as () => void);
      },
      removeEventListener(type, handler) {
        if (type === 'visibilitychange') visibilityHandlers.delete(handler as () => void);
      },
    } as unknown as Document,
    windowTarget: {
      addEventListener(type, handler) {
        if (type === 'focus') focusHandlers.add(handler as () => void);
      },
      removeEventListener(type, handler) {
        if (type === 'focus') focusHandlers.delete(handler as () => void);
      },
    } as unknown as Window,
  });

  assert.deepEqual(calls, ['arm']);

  visibilityState = 'hidden';
  [...visibilityHandlers][0]?.();
  currentYmd = '2026-04-24';
  visibilityState = 'visible';
  [...visibilityHandlers][0]?.();
  currentYmd = '2026-04-25';
  [...focusHandlers][0]?.();

  dispose();

  assert.equal(visibilityHandlers.size, 0);
  assert.equal(focusHandlers.size, 0);
  assert.deepEqual(calls, ['arm', 'rollover', 'disarm', 'arm', 'rollover', 'disarm', 'arm', 'disarm']);
});

test('day-context visibility wake only fires for visible documents', () => {
  assert.equal(shouldHandleDayContextVisibilityWake('visible'), true);
  assert.equal(shouldHandleDayContextVisibilityWake('hidden'), false);
  assert.equal(shouldHandleDayContextVisibilityWake(undefined), false);
});

test('day-context browser runtime deps own document and window host wiring', () => {
  const originalDocument = Object.getOwnPropertyDescriptor(globalThis, 'document');
  const originalWindow = Object.getOwnPropertyDescriptor(globalThis, 'window');
  const documentTarget = { visibilityState: 'visible' };
  const windowTarget = {};

  try {
    Object.defineProperty(globalThis, 'document', {
      configurable: true,
      value: documentTarget,
    });
    Object.defineProperty(globalThis, 'window', {
      configurable: true,
      value: windowTarget,
    });

    const deps = createBrowserDayContextRolloverRuntimeDeps({
      getCurrentYmd: () => '2026-04-24',
      getDelayMs: () => 1_000,
      onRollover: () => {},
    });

    assert.equal(deps.documentTarget, documentTarget);
    assert.equal(deps.windowTarget, windowTarget);
    assert.equal(typeof deps.host.setTimeout, 'function');
  } finally {
    if (originalDocument) {
      Object.defineProperty(globalThis, 'document', originalDocument);
    } else {
      Reflect.deleteProperty(globalThis, 'document');
    }

    if (originalWindow) {
      Object.defineProperty(globalThis, 'window', originalWindow);
    } else {
      Reflect.deleteProperty(globalThis, 'window');
    }
  }
});

test('configured day-context hook delegates overlay rollover wiring to the shared runtime', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/dayContext.ts'),
    'utf8',
  );
  const providerSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/DayContextProvider.tsx'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/dayContextProvider.runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserDayContextRolloverRuntimeDeps,[\s\S]*startDayContextRolloverRuntime,[\s\S]*\} from '\.\/dayContextProvider\.runtime';/,
  );
  assert.match(
    source,
    /return startDayContextRolloverRuntime\(createBrowserDayContextRolloverRuntimeDeps\(\{[\s\S]*getCurrentYmd:[\s\S]*getDelayMs:[\s\S]*onRollover:[\s\S]*\}\)\);/,
  );
  assert.doesNotMatch(source, /typeof document/);
  assert.doesNotMatch(source, /typeof window/);
  assert.doesNotMatch(source, /document\.addEventListener\('visibilitychange'/);
  assert.doesNotMatch(source, /window\.addEventListener\('focus'/);
  assert.doesNotMatch(source, /createMidnightRolloverController/);
  assert.doesNotMatch(source, /const timer = setTimeout\(/);
  assert.doesNotMatch(source, /react-hooks\/exhaustive-deps/);

  assert.match(
    providerSource,
    /import \{[\s\S]*createBrowserDayContextRolloverRuntimeDeps,[\s\S]*startDayContextRolloverRuntime,[\s\S]*\} from '\.\/dayContextProvider\.runtime';/,
  );
  assert.match(
    providerSource,
    /return startDayContextRolloverRuntime\(createBrowserDayContextRolloverRuntimeDeps\(\{[\s\S]*getCurrentYmd:[\s\S]*getDelayMs:[\s\S]*onRollover:[\s\S]*\}\)\);/,
  );
  assert.doesNotMatch(providerSource, /typeof document/);
  assert.doesNotMatch(providerSource, /typeof window/);
  assert.doesNotMatch(providerSource, /const timer = setTimeout\(/);
  assert.doesNotMatch(providerSource, /react-hooks\/exhaustive-deps/);

  assert.match(
    runtimeSource,
    /export function createBrowserDayContextRolloverRuntimeDeps\(/,
  );
  assert.match(
    runtimeSource,
    /const timer = globalThis\.setTimeout\(callback, delayMs\);/,
  );
  assert.match(
    runtimeSource,
    /globalThis\.clearTimeout\(timer as ReturnType<typeof globalThis\.setTimeout>\);/,
  );
});
