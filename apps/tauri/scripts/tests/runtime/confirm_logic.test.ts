import assert from 'node:assert/strict';
import test from 'node:test';

import {
  dismissConfirm,
  enqueueConfirm,
  type ConfirmQueueEntry,
  type ConfirmQueueState,
} from '../../../app/src/lib/dialogs/confirm.logic';

function entry(id: number): ConfirmQueueEntry<string | null> {
  return {
    id,
    triggerElement: `trigger-${id}`,
    resolve: () => {},
  };
}

test('confirm queue promotes the first entry immediately and preserves later entries in FIFO order', () => {
  const first = entry(1);
  const second = entry(2);
  const third = entry(3);

  let state: ConfirmQueueState<ConfirmQueueEntry<string | null>> = { current: null, queue: [] };
  state = enqueueConfirm(state, first);
  state = enqueueConfirm(state, second);
  state = enqueueConfirm(state, third);

  assert.equal(state.current?.id, 1);
  assert.deepEqual(state.queue.map((item) => item.id), [2, 3]);
});

test('dismissConfirm advances the queue until it becomes empty', () => {
  const first = entry(1);
  const second = entry(2);

  let state: ConfirmQueueState<ConfirmQueueEntry<string | null>> = {
    current: first,
    queue: [second],
  };

  state = dismissConfirm(state);
  assert.equal(state.current?.id, 2);
  assert.deepEqual(state.queue, []);

  state = dismissConfirm(state);
  assert.equal(state.current, null);
  assert.deepEqual(state.queue, []);
});

test('dismissConfirm on an already-empty tail stays empty and does not invent state', () => {
  const state = dismissConfirm<ConfirmQueueEntry<string | null>>({
    current: null,
    queue: [],
  });

  assert.equal(state.current, null);
  assert.deepEqual(state.queue, []);
});
