import { describe, expect, test } from 'vitest';

import { createEntityInvalidationCoalescer, type TimerApi } from './useExternalMutationSubscription.logic';
import {
  startExternalMutationSubscriptionRuntime,
  type RuntimeUnlisten,
} from './useExternalMutationSubscription.runtime';

type MutationPayload = { source_window?: string };
type DataChangedPayload = { entity?: string };

function deferredUnlisten(): {
  promise: Promise<RuntimeUnlisten>;
  reject: (error: unknown) => void;
  resolve: (unlisten: RuntimeUnlisten) => void;
} {
  let reject!: (error: unknown) => void;
  let resolve!: (unlisten: RuntimeUnlisten) => void;
  const promise = new Promise<RuntimeUnlisten>((resolver, rejecter) => {
    resolve = resolver;
    reject = rejecter;
  });
  return { promise, reject, resolve };
}

async function flushMicrotasks(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
}

function createManualTimerApi(): TimerApi & {
  drainQueuedCallbacks(): Array<() => void>;
  flush(): void;
  pendingCount(): number;
} {
  let nextId = 0;
  const pending = new Map<number, () => void>();

  return {
    clear(handle) {
      pending.delete(handle as number);
    },
    drainQueuedCallbacks() {
      const callbacks = [...pending.values()];
      pending.clear();
      return callbacks;
    },
    flush() {
      const callbacks = [...pending.values()];
      pending.clear();
      for (const callback of callbacks) callback();
    },
    pendingCount() {
      return pending.size;
    },
    schedule(callback) {
      const id = nextId;
      nextId += 1;
      pending.set(id, callback);
      return id;
    },
  };
}

function createHarness(options?: {
  ownWindowLabel?: string;
  useRealCoalescer?: boolean;
}) {
  let mutationHandler: ((payload: MutationPayload) => void) | null = null;
  let dataChangedHandler: ((payload: DataChangedPayload) => void) | null = null;
  const mutationListener = deferredUnlisten();
  const dataChangedListener = deferredUnlisten();
  const calls: string[] = [];
  const errors: Array<{ error: unknown; message: string; scope: string }> = [];
  const timerApi = createManualTimerApi();
  let coalescerCleared = 0;

  const dispose = startExternalMutationSubscriptionRuntime({
    ownWindowLabel: options?.ownWindowLabel ?? 'main',
    invalidateExternalMutationQueries: () => calls.push('external'),
    invalidateQueriesForEntity: (entity) => calls.push(`entity:${entity}`),
    reportError: (scope, message, error) => errors.push({ error, message, scope }),
    listenMutationBroadcast: (handler) => {
      mutationHandler = handler;
      return mutationListener.promise;
    },
    listenDataChanged: (handler) => {
      dataChangedHandler = handler;
      return dataChangedListener.promise;
    },
    createCoalescer: options?.useRealCoalescer
      ? (invalidateEntity) => createEntityInvalidationCoalescer(invalidateEntity, 50, timerApi)
      : (invalidateEntity) => ({
          clear: () => {
            coalescerCleared += 1;
          },
          schedule: (entity) => invalidateEntity(entity),
        }),
  });

  return {
    calls,
    dataChangedListener,
    dispose,
    drainTimerCallbacks: () => timerApi.drainQueuedCallbacks(),
    errors,
    flushTimers: () => timerApi.flush(),
    get coalescerCleared() {
      return coalescerCleared;
    },
    get pendingTimers() {
      return timerApi.pendingCount();
    },
    mutationListener,
    resolveDataChanged: (label: string) => {
      dataChangedListener.resolve(() => calls.push(`unlisten:${label}`));
    },
    resolveMutation: (label: string) => {
      mutationListener.resolve(() => calls.push(`unlisten:${label}`));
    },
    sendDataChanged: (payload: DataChangedPayload) => {
      if (!dataChangedHandler) throw new Error('data-changed handler not registered');
      dataChangedHandler(payload);
    },
    sendMutation: (payload: MutationPayload) => {
      if (!mutationHandler) throw new Error('mutation handler not registered');
      mutationHandler(payload);
    },
  };
}

describe('startExternalMutationSubscriptionRuntime', () => {
  test('runs one catch-up invalidation after both async listeners settle', async () => {
    const runtime = createHarness();

    runtime.resolveMutation('mutation');
    await flushMicrotasks();
    expect(runtime.calls).toEqual([]);

    runtime.resolveDataChanged('data');
    await flushMicrotasks();
    await flushMicrotasks();

    expect(runtime.calls).toEqual(['external']);
  });

  test('reports listener registration failures and still runs catch-up once both listeners settle', async () => {
    const runtime = createHarness();
    const failure = new Error('listen failed');

    runtime.mutationListener.reject(failure);
    runtime.resolveDataChanged('data');
    await flushMicrotasks();
    await flushMicrotasks();

    expect(runtime.errors).toEqual([
      {
        error: failure,
        message: 'Failed to subscribe to mutation broadcasts',
        scope: 'external.listen.mutationBroadcast',
      },
    ]);
    expect(runtime.calls).toEqual(['external']);
  });

  test('suppresses self-originated mutation broadcasts while invalidating external broadcasts', async () => {
    const runtime = createHarness({ ownWindowLabel: 'main' });
    runtime.resolveMutation('mutation');
    runtime.resolveDataChanged('data');
    await flushMicrotasks();
    runtime.calls.length = 0;

    runtime.sendMutation({ source_window: 'main' });
    runtime.sendMutation({ source_window: 'other' });
    runtime.sendMutation({});

    expect(runtime.calls).toEqual(['external', 'external']);
  });

  test('coalesces data-changed invalidations per entity and ignores entity-less payloads', async () => {
    const runtime = createHarness({ useRealCoalescer: true });
    runtime.resolveMutation('mutation');
    runtime.resolveDataChanged('data');
    await flushMicrotasks();
    runtime.calls.length = 0;

    runtime.sendDataChanged({ entity: 'task' });
    runtime.sendDataChanged({});
    runtime.sendDataChanged({ entity: 'task' });
    runtime.sendDataChanged({ entity: 'list' });

    expect(runtime.pendingTimers).toBe(2);
    expect(runtime.calls).toEqual([]);

    runtime.flushTimers();

    expect(runtime.calls).toEqual(['entity:task', 'entity:list']);
  });

  test('cleanup after registration unlistens both listeners and clears pending coalesced work', async () => {
    const runtime = createHarness({ useRealCoalescer: true });
    runtime.resolveMutation('mutation');
    runtime.resolveDataChanged('data');
    await flushMicrotasks();
    runtime.calls.length = 0;
    runtime.sendDataChanged({ entity: 'task' });

    runtime.dispose();
    runtime.dispose();
    runtime.flushTimers();

    expect(runtime.calls).toEqual(['unlisten:mutation', 'unlisten:data']);
    expect(runtime.pendingTimers).toBe(0);
  });

  test('cleanup before listener promises resolve performs late unlisten without catch-up', async () => {
    const runtime = createHarness();

    runtime.dispose();
    runtime.resolveMutation('mutation');
    runtime.resolveDataChanged('data');
    await flushMicrotasks();
    await flushMicrotasks();

    expect(runtime.calls).toEqual(['unlisten:mutation', 'unlisten:data']);
    expect(runtime.coalescerCleared).toBe(1);
  });

  test('ignores queued listener callbacks after dispose', async () => {
    const runtime = createHarness({ useRealCoalescer: true });
    runtime.resolveMutation('mutation');
    runtime.resolveDataChanged('data');
    await flushMicrotasks();
    runtime.calls.length = 0;

    runtime.dispose();
    runtime.sendMutation({ source_window: 'other' });
    runtime.sendDataChanged({ entity: 'task' });
    runtime.flushTimers();

    expect(runtime.calls).toEqual(['unlisten:mutation', 'unlisten:data']);
  });

  test('ignores already-queued coalescer callbacks that run after dispose', async () => {
    const runtime = createHarness({ useRealCoalescer: true });
    runtime.resolveMutation('mutation');
    runtime.resolveDataChanged('data');
    await flushMicrotasks();
    runtime.calls.length = 0;

    runtime.sendDataChanged({ entity: 'task' });
    const queuedCallbacks = runtime.drainTimerCallbacks();

    runtime.dispose();
    for (const callback of queuedCallbacks) callback();

    expect(runtime.calls).toEqual(['unlisten:mutation', 'unlisten:data']);
  });
});
