import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  checkForUpdateCachedRuntime,
  createBrowserCheckForUpdateCachedRuntimeDeps,
  isBrowserUpdateCheckOffline,
  type UpdateCheckRuntimeState,
} from '../../../app/src/lib/checkForUpdateCached.runtime';

function createRuntimeHarness(overrides: Partial<{
  offline: boolean;
  version: string;
  now: number;
  storedRaw: string | null;
  getVersionError: Error;
  checkForUpdateResult: string | null;
  checkForUpdateDeferred: Promise<string | null>;
  writeThrows: Error;
}> = {}) {
  const state: UpdateCheckRuntimeState = { inflight: null };
  const calls = {
    getVersion: 0,
    checkForUpdate: 0,
    writes: [] as string[],
  };

  const deps = {
    appVersionFallback: 'unknown',
    isOffline: () => overrides.offline ?? false,
    now: () => overrides.now ?? 1_700_000_000_000,
    readStorage: () => overrides.storedRaw ?? null,
    ttlMs: 6 * 60 * 60 * 1000,
    getVersion: async () => {
      calls.getVersion += 1;
      if (overrides.getVersionError) throw overrides.getVersionError;
      return overrides.version ?? '1.0.0';
    },
    checkForUpdate: async () => {
      calls.checkForUpdate += 1;
      if (overrides.checkForUpdateDeferred) {
        return overrides.checkForUpdateDeferred;
      }
      if ('checkForUpdateResult' in overrides) {
        return overrides.checkForUpdateResult ?? null;
      }
      return '2.0.0';
    },
    setInflight: (inflight: Promise<string | null> | null) => {
      state.inflight = inflight;
    },
    getInflight: () => state.inflight,
    writeStorage: (value: string) => {
      if (overrides.writeThrows) throw overrides.writeThrows;
      calls.writes.push(value);
    },
  };

  return { calls, deps, state };
}

function createDeferredPromise<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

test('check-for-update runtime short-circuits while offline without touching version or IPC', async () => {
  const harness = createRuntimeHarness({ offline: true });

  const result = await checkForUpdateCachedRuntime(harness.deps);

  assert.equal(result, null);
  assert.equal(harness.calls.getVersion, 0);
  assert.equal(harness.calls.checkForUpdate, 0);
  assert.deepEqual(harness.calls.writes, []);
});

test('check-for-update runtime returns a fresh cache hit without invoking the updater IPC', async () => {
  const harness = createRuntimeHarness({
    storedRaw: JSON.stringify({
      version: '9.9.9',
      checkedAt: 1_700_000_000_000 - 1_000,
      appVersion: '1.0.0',
    }),
  });

  const result = await checkForUpdateCachedRuntime(harness.deps);

  assert.equal(result, '9.9.9');
  assert.equal(harness.calls.getVersion, 1);
  assert.equal(harness.calls.checkForUpdate, 0);
  assert.deepEqual(harness.calls.writes, []);
});

test('check-for-update runtime falls back to unknown app version when getVersion fails and still writes the cache', async () => {
  const harness = createRuntimeHarness({
    getVersionError: new Error('not tauri'),
    checkForUpdateResult: null,
  });

  const result = await checkForUpdateCachedRuntime(harness.deps);

  assert.equal(result, null);
  assert.equal(harness.calls.getVersion, 1);
  assert.equal(harness.calls.checkForUpdate, 1);
  assert.deepEqual(harness.calls.writes, [
    JSON.stringify({
      version: null,
      checkedAt: 1_700_000_000_000,
      appVersion: 'unknown',
    }),
  ]);
});

test('check-for-update runtime coalesces concurrent callers through the shared inflight promise', async () => {
  const deferred = createDeferredPromise<string | null>();
  const harness = createRuntimeHarness({
    checkForUpdateDeferred: deferred.promise,
  });

  const first = checkForUpdateCachedRuntime(harness.deps);
  const second = checkForUpdateCachedRuntime(harness.deps);

  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.equal(harness.calls.getVersion, 1, 'inflight dedupe now covers the version probe as well');
  assert.equal(harness.calls.checkForUpdate, 1);
  assert.ok(harness.state.inflight, 'shared inflight promise should be visible while pending');

  deferred.resolve('3.0.0');
  assert.equal(await first, '3.0.0');
  assert.equal(await second, '3.0.0');
  assert.equal(harness.state.inflight, null, 'inflight should clear after resolution');
  assert.deepEqual(harness.calls.writes, [
    JSON.stringify({
      version: '3.0.0',
      checkedAt: 1_700_000_000_000,
      appVersion: '1.0.0',
    }),
  ]);
});

test('check-for-update runtime treats storage write failures as non-fatal and still returns the update result', async () => {
  const harness = createRuntimeHarness({
    writeThrows: new Error('quota'),
    checkForUpdateResult: '4.0.0',
  });

  const result = await checkForUpdateCachedRuntime(harness.deps);

  assert.equal(result, '4.0.0');
  assert.equal(harness.calls.checkForUpdate, 1);
  assert.deepEqual(harness.calls.writes, []);
});

test('check-for-update browser runtime deps own offline and storage host wiring', async () => {
  const originalNavigator = Object.getOwnPropertyDescriptor(globalThis, 'navigator');
  const originalLocalStorage = Object.getOwnPropertyDescriptor(globalThis, 'localStorage');
  const values = new Map<string, string>();
  const state: UpdateCheckRuntimeState = { inflight: null };

  Object.defineProperty(globalThis, 'navigator', {
    configurable: true,
    value: { onLine: false },
  });
  assert.equal(isBrowserUpdateCheckOffline(), true);

  Object.defineProperty(globalThis, 'navigator', {
    configurable: true,
    value: undefined,
  });
  assert.equal(isBrowserUpdateCheckOffline(), false);

  Object.defineProperty(globalThis, 'localStorage', {
    configurable: true,
    value: {
      getItem: (key: string) => values.get(key) ?? null,
      setItem: (key: string, value: string) => {
        values.set(key, value);
      },
    },
  });

  try {
    const deps = createBrowserCheckForUpdateCachedRuntimeDeps({
      appVersionFallback: 'unknown',
      cacheKey: 'lorvex.test.update-cache',
      checkForUpdate: async () => '7.0.0',
      getInflight: () => state.inflight,
      getVersion: async () => '1.0.0',
      now: () => 1_700_000_000_000,
      setInflight: (nextInflight) => {
        state.inflight = nextInflight;
      },
      ttlMs: 6 * 60 * 60 * 1000,
    });

    assert.equal(await checkForUpdateCachedRuntime(deps), '7.0.0');
    assert.equal(
      values.get('lorvex.test.update-cache'),
      JSON.stringify({
        version: '7.0.0',
        checkedAt: 1_700_000_000_000,
        appVersion: '1.0.0',
      }),
    );
  } finally {
    if (originalNavigator) {
      Object.defineProperty(globalThis, 'navigator', originalNavigator);
    } else {
      Reflect.deleteProperty(globalThis, 'navigator');
    }
    if (originalLocalStorage) {
      Object.defineProperty(globalThis, 'localStorage', originalLocalStorage);
    } else {
      Reflect.deleteProperty(globalThis, 'localStorage');
    }
  }
});

test('check-for-update facade delegates browser host wiring to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/checkForUpdateCached.ts'),
    'utf8',
  );

  assert.match(source, /createBrowserCheckForUpdateCachedRuntimeDeps/);
  assert.doesNotMatch(source, /\bnavigator\b/);
  assert.doesNotMatch(source, /\blocalStorage\b/);
  assert.doesNotMatch(source, /\bglobalThis\b/);
});
