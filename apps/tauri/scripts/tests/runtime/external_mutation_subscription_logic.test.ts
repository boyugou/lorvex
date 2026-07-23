import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createEntityInvalidationCoalescer,
  shouldIgnoreMutationBroadcast,
  type TimerApi,
} from '../../../app/src/lib/useExternalMutationSubscription.logic';

test('shouldIgnoreMutationBroadcast skips self-originated events only when the current window has a label', () => {
  assert.equal(shouldIgnoreMutationBroadcast('main', 'main'), true);
  assert.equal(shouldIgnoreMutationBroadcast('main', 'popover'), false);
  assert.equal(shouldIgnoreMutationBroadcast('', 'main'), false);
  assert.equal(shouldIgnoreMutationBroadcast('main', undefined), false);
});

test('entity invalidation coalescer collapses repeated invalidations for the same entity', () => {
  const invalidated: string[] = [];
  const scheduled = new Map<number, () => void>();
  const cleared: number[] = [];
  let nextHandle = 1;
  const timerApi: TimerApi = {
    schedule(cb) {
      const handle = nextHandle++;
      scheduled.set(handle, cb);
      return handle;
    },
    clear(handle) {
      const numeric = Number(handle);
      cleared.push(numeric);
      scheduled.delete(numeric);
    },
  };

  const coalescer = createEntityInvalidationCoalescer(
    (entity) => invalidated.push(entity),
    50,
    timerApi,
  );

  coalescer.schedule('task');
  coalescer.schedule('task');

  assert.deepEqual(cleared, [1]);
  assert.equal(scheduled.size, 1);

  const pending = [...scheduled.values()][0];
  assert.ok(pending, 'latest task invalidation should remain scheduled');
  pending?.();

  assert.deepEqual(invalidated, ['task']);
});

test('entity invalidation coalescer keeps different entities independent and clear() cancels outstanding timers', () => {
  const invalidated: string[] = [];
  const scheduled = new Map<number, () => void>();
  const cleared: number[] = [];
  let nextHandle = 1;
  const timerApi: TimerApi = {
    schedule(cb) {
      const handle = nextHandle++;
      scheduled.set(handle, cb);
      return handle;
    },
    clear(handle) {
      const numeric = Number(handle);
      cleared.push(numeric);
      scheduled.delete(numeric);
    },
  };

  const coalescer = createEntityInvalidationCoalescer(
    (entity) => invalidated.push(entity),
    50,
    timerApi,
  );

  coalescer.schedule('task');
  coalescer.schedule('list');
  assert.equal(scheduled.size, 2);

  coalescer.clear();
  assert.deepEqual(cleared.sort((a, b) => a - b), [1, 2]);
  assert.equal(scheduled.size, 0);
  assert.deepEqual(invalidated, []);
});
