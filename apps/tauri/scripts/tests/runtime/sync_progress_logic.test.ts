import assert from 'node:assert/strict';
import test from 'node:test';

import {
  IDLE_SYNC_PROGRESS_STATE,
  normalizeSyncProgressPayload,
  reduceSyncProgress,
  startSyncProgressSubscription,
  SYNC_PROGRESS_EVENT,
  type SyncProgressPayload,
} from '../../../app/src/lib/sync/useSyncProgress.logic';

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

test('normalizeSyncProgressPayload accepts only canonical sync progress payloads', () => {
  assert.deepEqual(
    normalizeSyncProgressPayload({
      phase: 'pull',
      current: 3,
      total: 5,
      cycle_id: 'cycle-a',
    }),
    {
      phase: 'pull',
      current: 3,
      total: 5,
      cycle_id: 'cycle-a',
    },
  );

  assert.equal(normalizeSyncProgressPayload(null), null);
  assert.equal(normalizeSyncProgressPayload({ phase: 'bogus', current: 0, total: 0, cycle_id: 'x' }), null);
  assert.equal(normalizeSyncProgressPayload({ phase: 'push', current: '1', total: 0, cycle_id: 'x' }), null);
  assert.equal(normalizeSyncProgressPayload({ phase: 'push', current: 1, total: 0, cycle_id: '   ' }), null);
  assert.equal(normalizeSyncProgressPayload({ phase: 'push', current: -1, total: 0, cycle_id: 'x' }), null);
  assert.equal(normalizeSyncProgressPayload({ phase: 'push', current: 2, total: 1, cycle_id: 'x' }), null);
  assert.equal(normalizeSyncProgressPayload({
    phase: 'push',
    current: 0,
    total: 1,
    cycle_id: 'x',
    debug: true,
  }), null);
  assert.equal(normalizeSyncProgressPayload([
    'push',
    0,
    1,
    'x',
  ]), null);
});

test('reduceSyncProgress still ignores stale cycles and clears only on active idle', () => {
  const active = reduceSyncProgress(IDLE_SYNC_PROGRESS_STATE, {
    phase: 'push',
    current: 2,
    total: 10,
    cycle_id: 'cycle-a',
  });
  const stale = reduceSyncProgress(active, {
    phase: 'pull',
    current: 9,
    total: 10,
    cycle_id: 'cycle-b',
  });
  assert.deepEqual(stale, active);

  const ignoredIdle = reduceSyncProgress(active, {
    phase: 'idle',
    current: 0,
    total: 0,
    cycle_id: 'cycle-b',
  });
  assert.deepEqual(ignoredIdle, active);

  const activeIdle = reduceSyncProgress(active, {
    phase: 'idle',
    current: 0,
    total: 0,
    cycle_id: 'cycle-a',
  });
  assert.deepEqual(activeIdle, IDLE_SYNC_PROGRESS_STATE);
});

test('startSyncProgressSubscription ignores invalid payloads and late stale listeners', async () => {
  const registrations: string[] = [];
  const stateTransitions: SyncProgressPayload[] = [];
  let state = IDLE_SYNC_PROGRESS_STATE;
  let handler: ((event: { payload: SyncProgressPayload }) => void) | null = null;
  let unlistenCalled = 0;

  const stop = startSyncProgressSubscription({
    listen: async (event, nextHandler) => {
      registrations.push(event);
      handler = nextHandler;
      return () => {
        unlistenCalled += 1;
      };
    },
    setState: (updater) => {
      state = updater(state);
      if (state.cycleId) {
        stateTransitions.push({
          phase: state.phase,
          current: state.current,
          total: state.total,
          cycle_id: state.cycleId,
        });
      }
    },
    reportError: () => {
      throw new Error('unexpected error report');
    },
  });

  assert.deepEqual(registrations, [SYNC_PROGRESS_EVENT]);
  assert.ok(handler, 'expected listen handler');
  handler?.({ payload: { phase: 'push', current: 1, total: 3, cycle_id: 'cycle-a' } });
  handler?.({ payload: { phase: 'bogus', current: 2, total: 3, cycle_id: 'cycle-a' } as unknown as SyncProgressPayload });
  handler?.({ payload: { phase: 'pull', current: 2, total: 3, cycle_id: '' } as unknown as SyncProgressPayload });

  assert.deepEqual(stateTransitions, [
    { phase: 'push', current: 1, total: 3, cycle_id: 'cycle-a' },
  ]);
  assert.equal(unlistenCalled, 0);
  stop();
  await Promise.resolve();
  assert.equal(unlistenCalled, 1);
});

test('startSyncProgressSubscription reports listen failures and disposes listeners that resolve after teardown', async () => {
  const listenFailure = new Error('boom');
  const reported: unknown[] = [];
  const lateListener = deferred<() => void>();
  let lateUnlistenCalled = 0;

  startSyncProgressSubscription({
    listen: async () => {
      throw listenFailure;
    },
    setState: () => {},
    reportError: (error) => {
      reported.push(error);
    },
  });
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(reported.length, 1);
  assert.equal(reported[0], listenFailure);

  const stop = startSyncProgressSubscription({
    listen: () => lateListener.promise,
    setState: () => {},
    reportError: () => {
      throw new Error('unexpected error report');
    },
  });
  stop();
  lateListener.resolve(() => {
    lateUnlistenCalled += 1;
  });
  await Promise.resolve();
  assert.equal(lateUnlistenCalled, 1);
});
