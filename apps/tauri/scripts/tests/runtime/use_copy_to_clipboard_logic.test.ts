import assert from 'node:assert/strict';
import test from 'node:test';

import { createClipboardCopyController } from '../../../app/src/lib/platform/useCopyToClipboard.logic';

function createDeferredPromise<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

test('clipboard copy controller writes text, toggles copying state, and emits success feedback', async () => {
  const copyingStates: boolean[] = [];
  const successMessages: string[] = [];
  const controller = createClipboardCopyController(
    {
      writeText: async (text) => {
        assert.equal(text, 'hello');
      },
      notifyCopyingChange: (copying) => copyingStates.push(copying),
      notifySuccess: (message) => successMessages.push(message),
      notifyError: () => assert.fail('error path should not run'),
    },
    () => 'Copied',
    () => 'Error',
  );

  assert.equal(await controller.copy('hello'), true);
  assert.equal(controller.isCopying(), false);
  assert.deepEqual(copyingStates, [true, false]);
  assert.deepEqual(successMessages, ['Copied']);
});

test('clipboard copy controller prefers an explicit success message', async () => {
  const successMessages: string[] = [];
  const controller = createClipboardCopyController(
    {
      writeText: async () => {},
      notifyCopyingChange: () => {},
      notifySuccess: (message) => successMessages.push(message),
      notifyError: () => assert.fail('error path should not run'),
    },
    () => 'Copied',
    () => 'Error',
  );

  await controller.copy('hello', 'Copied task link');
  assert.deepEqual(successMessages, ['Copied task link']);
});

test('clipboard copy controller dedupes overlapping copy attempts', async () => {
  const copyingStates: boolean[] = [];
  let writes = 0;
  const deferred = createDeferredPromise<void>();
  const controller = createClipboardCopyController(
    {
      writeText: async () => {
        writes += 1;
        await deferred.promise;
      },
      notifyCopyingChange: (copying) => copyingStates.push(copying),
      notifySuccess: () => {},
      notifyError: () => assert.fail('error path should not run'),
    },
    () => 'Copied',
    () => 'Error',
  );

  const first = controller.copy('hello');
  assert.equal(controller.isCopying(), true);
  assert.equal(await controller.copy('world'), false);
  assert.equal(writes, 1);

  deferred.resolve();
  assert.equal(await first, true);
  assert.deepEqual(copyingStates, [true, false]);
});

test('clipboard copy controller reports failures and still clears copying state', async () => {
  const copyingStates: boolean[] = [];
  const errors: Array<{ error: unknown; fallbackMessage: string }> = [];
  const failure = new Error('permission denied');
  const controller = createClipboardCopyController(
    {
      writeText: async () => { throw failure; },
      notifyCopyingChange: (copying) => copyingStates.push(copying),
      notifySuccess: () => assert.fail('success path should not run'),
      notifyError: (error, fallbackMessage) => errors.push({ error, fallbackMessage }),
    },
    () => 'Copied',
    () => 'Copy failed',
  );

  assert.equal(await controller.copy('hello'), true);
  assert.equal(controller.isCopying(), false);
  assert.deepEqual(copyingStates, [true, false]);
  assert.equal(errors.length, 1);
  assert.equal(errors[0]?.error, failure);
  assert.equal(errors[0]?.fallbackMessage, 'Copy failed');
});
