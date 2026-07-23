import { afterEach, describe, expect, test } from 'vitest';

import {
  __TEST_ONLY__,
  installQuitFlushListener,
} from './quitFlush';

function flushMicrotasks(): Promise<void> {
  return Promise.resolve().then(() => undefined);
}

describe('installQuitFlushListener', () => {
  afterEach(() => {
    __TEST_ONLY__.resetDepsForTests();
  });

  test('late listener rejection after cleanup does not poison the next install', async () => {
    let rejectFirst!: (error: unknown) => void;
    let listenCalls = 0;

    __TEST_ONLY__.setDepsForTests({
      listen: (() => {
        listenCalls += 1;
        if (listenCalls === 1) {
          return new Promise<() => void>((_resolve, reject) => {
            rejectFirst = reject;
          });
        }
        return Promise.resolve(() => {});
      }) as never,
    });

    const cleanupFirst = installQuitFlushListener();
    cleanupFirst();
    rejectFirst(new Error('event bus unavailable'));
    await flushMicrotasks();

    const cleanupSecond = installQuitFlushListener();
    await flushMicrotasks();
    cleanupSecond();

    expect(listenCalls).toBe(2);
  });

  test('cleanup swallows a throwing unlisten callback', async () => {
    __TEST_ONLY__.setDepsForTests({
      listen: (() => Promise.resolve(() => {
        throw new Error('unlisten failed');
      })) as never,
    });

    const cleanup = installQuitFlushListener();
    await flushMicrotasks();

    expect(() => cleanup()).not.toThrow();
  });
});
