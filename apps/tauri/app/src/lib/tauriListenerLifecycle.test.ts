import { describe, expect, test } from 'vitest';

import { createAsyncTauriListenerScope, type TauriUnlistenFn } from './tauriListenerLifecycle';

function deferredUnlisten(): {
  promise: Promise<TauriUnlistenFn>;
  resolve: (unlisten: TauriUnlistenFn) => void;
} {
  let resolve!: (unlisten: TauriUnlistenFn) => void;
  const promise = new Promise<TauriUnlistenFn>((resolver) => {
    resolve = resolver;
  });
  return { promise, resolve };
}

function deferredFailure(): {
  promise: Promise<TauriUnlistenFn>;
  reject: (error: unknown) => void;
} {
  let reject!: (error: unknown) => void;
  const promise = new Promise<TauriUnlistenFn>((_resolve, rejecter) => {
    reject = rejecter;
  });
  return { promise, reject };
}

async function flushMicrotasks(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
}

describe('createAsyncTauriListenerScope', () => {
  test('unlistens when cleanup runs before the listener promise resolves', async () => {
    const listener = deferredUnlisten();
    const calls: string[] = [];
    const scope = createAsyncTauriListenerScope();

    scope.add(listener.promise, () => {
      throw new Error('unexpected listener registration failure');
    });
    scope.dispose();

    listener.resolve(() => {
      calls.push('unlisten');
    });
    await flushMicrotasks();

    expect(calls).toEqual(['unlisten']);
  });

  test('unlistens when cleanup runs after the listener promise resolves', async () => {
    const listener = deferredUnlisten();
    const calls: string[] = [];
    const scope = createAsyncTauriListenerScope();

    scope.add(listener.promise, () => {
      throw new Error('unexpected listener registration failure');
    });
    listener.resolve(() => {
      calls.push('unlisten');
    });
    await flushMicrotasks();

    scope.dispose();
    scope.dispose();

    expect(calls).toEqual(['unlisten']);
  });

  test('continues disposing listeners when one unlisten callback throws', async () => {
    const first = deferredUnlisten();
    const second = deferredUnlisten();
    const calls: string[] = [];
    const scope = createAsyncTauriListenerScope();

    scope.add(first.promise, () => {
      throw new Error('unexpected listener registration failure');
    });
    scope.add(second.promise, () => {
      throw new Error('unexpected listener registration failure');
    });
    first.resolve(() => {
      calls.push('first');
      throw new Error('teardown failed');
    });
    second.resolve(() => {
      calls.push('second');
    });
    await flushMicrotasks();

    expect(() => scope.dispose()).not.toThrow();
    expect(calls).toEqual(['first', 'second']);
  });

  test('reports listener registration failure after cleanup without throwing', async () => {
    const listener = deferredFailure();
    const errors: unknown[] = [];
    const scope = createAsyncTauriListenerScope();

    scope.add(listener.promise, (error) => {
      errors.push(error);
    });
    scope.dispose();

    const failure = new Error('listen failed');
    listener.reject(failure);
    await flushMicrotasks();

    expect(errors).toEqual([failure]);
  });
});
