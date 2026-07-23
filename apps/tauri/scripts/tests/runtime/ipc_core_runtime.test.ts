import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildIpcMutationBroadcastPayload,
  invokeIpcRuntime,
  invokeWithAbortRuntime,
  resolveIpcMutationSourceWindow,
  runIpcMutationSideEffectsRuntime,
} from '../../../app/src/lib/ipc/core.runtime';

function createDeferredPromise<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

test('invokeWithAbortRuntime rejects immediately when the signal is already aborted', async () => {
  const controller = new AbortController();
  controller.abort();
  let invoked = false;

  await assert.rejects(
    invokeWithAbortRuntime({
      invoke: async () => {
        invoked = true;
        return 'never';
      },
      signal: controller.signal,
    }),
    (error: unknown) =>
      error instanceof DOMException
      && error.name === 'AbortError'
      && error.message === 'IPC call aborted before dispatch',
  );

  assert.equal(invoked, false);
});

test('invokeWithAbortRuntime rejects with AbortError when the signal aborts mid-flight', async () => {
  const deferred = createDeferredPromise<string>();
  const controller = new AbortController();

  const pending = invokeWithAbortRuntime({
    invoke: () => deferred.promise,
    signal: controller.signal,
  });
  controller.abort();

  await assert.rejects(
    pending,
    (error: unknown) =>
      error instanceof DOMException
      && error.name === 'AbortError'
      && error.message === 'IPC call aborted',
  );

  deferred.resolve('late');
});

test('invokeWithAbortRuntime preserves successful resolutions when no abort occurs', async () => {
  const result = await invokeWithAbortRuntime({
    invoke: async () => 'ok',
  });

  assert.equal(result, 'ok');
});

test('resolveIpcMutationSourceWindow fails closed outside Tauri contexts', () => {
  assert.equal(resolveIpcMutationSourceWindow(() => 'main'), 'main');
  assert.equal(
    resolveIpcMutationSourceWindow(() => {
      throw new Error('no webview');
    }),
    '',
  );
});

test('buildIpcMutationBroadcastPayload keeps command, source window, and injected timestamp stable', () => {
  assert.deepEqual(
    buildIpcMutationBroadcastPayload({
      command: 'complete_task',
      sourceWindow: 'main',
      nowIso: () => '2026-04-23T07:00:00.000Z',
    }),
    {
      command: 'complete_task',
      mutated_at: '2026-04-23T07:00:00.000Z',
      source_window: 'main',
    },
  );
});

test('runIpcMutationSideEffectsRuntime broadcasts mutations', async () => {
  const broadcasts: unknown[] = [];

  runIpcMutationSideEffectsRuntime({
    command: 'complete_task',
    broadcastMutation: async (payload) => {
      broadcasts.push(payload);
    },
    getCurrentWindowLabel: () => 'main',
    nowIso: () => '2026-04-23T07:00:00.000Z',
  });

  await new Promise((resolve) => setTimeout(resolve, 0));

  assert.deepEqual(broadcasts, [{
    command: 'complete_task',
    mutated_at: '2026-04-23T07:00:00.000Z',
    source_window: 'main',
  }]);
});

test('runIpcMutationSideEffectsRuntime ignores best-effort broadcast failures', async () => {
  runIpcMutationSideEffectsRuntime({
    command: 'complete_task',
    broadcastMutation: async () => {
      throw new Error('event permissions denied');
    },
    getCurrentWindowLabel: () => 'main',
  });

  await new Promise((resolve) => setTimeout(resolve, 0));
});

test('invokeIpcRuntime only runs mutation side effects after a successful invoke', async () => {
  const calls: string[] = [];

  await assert.rejects(
    invokeIpcRuntime({
      invoke: async () => {
        calls.push('invoke');
        throw new Error('boom');
      },
      runSideEffects: () => {
        calls.push('side-effects');
      },
    }),
    /boom/,
  );

  const result = await invokeIpcRuntime({
    invoke: async () => {
      calls.push('invoke-success');
      return 'ok';
    },
    runSideEffects: () => {
      calls.push('side-effects-success');
    },
  });

  assert.equal(result, 'ok');
  assert.deepEqual(calls, [
    'invoke',
    'invoke-success',
    'side-effects-success',
  ]);
});
