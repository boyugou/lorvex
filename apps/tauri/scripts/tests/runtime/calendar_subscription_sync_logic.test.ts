import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createCalendarSubscriptionSyncController,
  SUBSCRIPTION_SYNC_MIN_GAP_MS,
} from '../../../app/src/lib/calendarSubscriptionSync.logic';

function createDeferredPromise<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

test('calendar subscription sync skips offline attempts without mutating state', async () => {
  let syncCalls = 0;
  let reportedErrors = 0;
  const controller = createCalendarSubscriptionSyncController({
    isOnline: () => false,
    now: () => 1_000,
    performSync: async () => { syncCalls += 1; },
    reportError: () => { reportedErrors += 1; },
  });

  assert.equal(await controller.trySync(), false);
  assert.equal(syncCalls, 0);
  assert.equal(reportedErrors, 0);
  assert.equal(controller.getLastAttemptAt(), null);
  assert.equal(controller.isSyncing(), false);
});

test('calendar subscription sync blocks overlapping runs and clears syncing after completion', async () => {
  let now = 5_000;
  let syncCalls = 0;
  const deferred = createDeferredPromise<void>();
  const controller = createCalendarSubscriptionSyncController({
    isOnline: () => true,
    now: () => now,
    performSync: async () => {
      syncCalls += 1;
      await deferred.promise;
    },
    reportError: () => {},
  });

  const firstAttempt = controller.trySync();
  assert.equal(controller.isSyncing(), true);
  assert.equal(await controller.trySync(), false);
  assert.equal(syncCalls, 1);

  deferred.resolve();
  assert.equal(await firstAttempt, true);
  assert.equal(controller.isSyncing(), false);

  now += SUBSCRIPTION_SYNC_MIN_GAP_MS + 1;
  assert.equal(await controller.trySync(), true);
  assert.equal(syncCalls, 2);
});

test('calendar subscription sync enforces the minimum retry gap', async () => {
  let now = 10_000;
  let syncCalls = 0;
  const controller = createCalendarSubscriptionSyncController({
    isOnline: () => true,
    now: () => now,
    performSync: async () => { syncCalls += 1; },
    reportError: () => {},
  });

  assert.equal(await controller.trySync(), true);
  assert.equal(syncCalls, 1);
  assert.equal(controller.getLastAttemptAt(), 10_000);

  now += SUBSCRIPTION_SYNC_MIN_GAP_MS - 1;
  assert.equal(await controller.trySync(), false);
  assert.equal(syncCalls, 1);

  now += 1;
  assert.equal(await controller.trySync(), true);
  assert.equal(syncCalls, 2);
});

test('calendar subscription sync reports sync failures and still clears syncing state', async () => {
  const errors: unknown[] = [];
  const failure = new Error('boom');
  const controller = createCalendarSubscriptionSyncController({
    isOnline: () => true,
    now: () => 15_000,
    performSync: async () => { throw failure; },
    reportError: (error) => { errors.push(error); },
  });

  assert.equal(await controller.trySync(), true);
  assert.equal(controller.isSyncing(), false);
  assert.deepEqual(errors, [failure]);
});

test('calendar subscription sync connection-change handler ignores offline states and reuses trySync when online', async () => {
  let online = false;
  let syncCalls = 0;
  const controller = createCalendarSubscriptionSyncController({
    isOnline: () => online,
    now: () => 30_000,
    performSync: async () => { syncCalls += 1; },
    reportError: () => {},
  });

  assert.equal(await controller.handleConnectionChange(), false);
  assert.equal(syncCalls, 0);

  online = true;
  assert.equal(await controller.handleConnectionChange(), true);
  assert.equal(syncCalls, 1);
});

test('calendar subscription sync online handler reuses trySync directly', async () => {
  let syncCalls = 0;
  const controller = createCalendarSubscriptionSyncController({
    isOnline: () => true,
    now: () => 35_000,
    performSync: async () => { syncCalls += 1; },
    reportError: () => {},
  });

  assert.equal(await controller.handleOnline(), true);
  assert.equal(syncCalls, 1);
});
