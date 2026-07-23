import assert from 'node:assert/strict';
import test from 'node:test';

import {
  __TEST_ONLY__,
  installQuitFlushListener,
  registerQuitFlush,
} from '../../../app/src/lib/recovery/quitFlush';

async function flushAsyncWork(): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, 0));
}

test.afterEach(() => {
  __TEST_ONLY__.resetDepsForTests();
});

test('installQuitFlushListener dispatches every registered flusher on the quit event', async () => {
  const events: string[] = [];
  let handler: (() => Promise<void>) | null = null;
  let unlistenCalls = 0;

  __TEST_ONLY__.setDepsForTests({
    listen: async (_eventName, callback) => {
      handler = async () => {
        await callback({} as never);
      };
      return () => {
        unlistenCalls += 1;
      };
    },
  });

  const unregisterA = registerQuitFlush(async () => {
    events.push('a');
  });
  const unregisterB = registerQuitFlush(async () => {
    events.push('b');
  });
  const teardown = installQuitFlushListener();

  assert.ok(handler, 'expected quit-flush handler to be installed');
  await handler?.();

  assert.deepEqual(events.sort(), ['a', 'b']);

  unregisterA();
  unregisterB();
  teardown();
  assert.equal(unlistenCalls, 1);
});

test('installQuitFlushListener tears down a listener that resolves after cleanup already ran', async () => {
  let resolveFirstListen: ((unlisten: () => void) => void) | null = null;
  let unlistenCalls = 0;
  let listenCalls = 0;

  __TEST_ONLY__.setDepsForTests({
    listen: (_eventName, _callback) => {
      listenCalls += 1;
      if (listenCalls === 1) {
        return new Promise((resolve) => {
          resolveFirstListen = resolve;
        });
      }
      return Promise.resolve(() => {
        unlistenCalls += 100;
      });
    },
  });

  const teardown = installQuitFlushListener();
  teardown();

  assert.ok(resolveFirstListen, 'expected first listen() to remain pending');
  resolveFirstListen?.(() => {
    unlistenCalls += 1;
  });
  await flushAsyncWork();

  assert.equal(unlistenCalls, 1, 'late-resolving listener should be immediately unlistened');

  const teardown2 = installQuitFlushListener();
  await flushAsyncWork();
  teardown2();

  assert.equal(listenCalls, 2, 'cleanup should release the install latch so a later mount can re-install');
  assert.equal(unlistenCalls, 101);
});
