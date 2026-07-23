import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createVisibilityGatedIntervalController,
  type IntervalHost,
  type VisibilityIntervalHost,
} from '../../../app/src/lib/time/intervalControllers';

interface VirtualInterval {
  callback: () => void;
  id: number;
}

function createIntervalHarness() {
  const ticks: number[] = [];
  const timers = new Map<number, VirtualInterval>();
  let nextId = 1;

  const baseHost: IntervalHost = {
    runTick: () => {
      ticks.push(ticks.length + 1);
    },
    setInterval: (callback) => {
      const id = nextId++;
      timers.set(id, { id, callback });
      return () => {
        timers.delete(id);
      };
    },
  };

  return {
    baseHost,
    fireAll: () => {
      for (const timer of [...timers.values()]) {
        timer.callback();
      }
    },
    ticks,
    timers,
  };
}

test('visibility-gated interval arms only while visible and performs one catch-up tick on resume', () => {
  const harness = createIntervalHarness();
  const visible = { value: false };
  const host: VisibilityIntervalHost = {
    ...harness.baseHost,
    isVisible: () => visible.value,
  };

  const controller = createVisibilityGatedIntervalController(host, 60_000);
  controller.mount();
  assert.deepEqual(harness.ticks, []);
  assert.equal(controller.hasActiveTimer(), false);

  visible.value = true;
  controller.handleVisibilityChange();
  assert.deepEqual(harness.ticks, [1]);
  assert.equal(controller.hasActiveTimer(), true);
  assert.equal(harness.timers.size, 1);

  harness.fireAll();
  assert.deepEqual(harness.ticks, [1, 2]);

  visible.value = false;
  controller.handleVisibilityChange();
  assert.equal(controller.hasActiveTimer(), false);
  assert.equal(harness.timers.size, 0);

  visible.value = true;
  controller.handleVisibilityChange();
  assert.deepEqual(harness.ticks, [1, 2, 3]);
  assert.equal(controller.hasActiveTimer(), true);
});

test('visibility-gated interval does not double-arm when visibility events repeat in the same state', () => {
  const harness = createIntervalHarness();
  const visible = { value: true };
  const host: VisibilityIntervalHost = {
    ...harness.baseHost,
    isVisible: () => visible.value,
  };

  const controller = createVisibilityGatedIntervalController(host, 60_000);
  controller.mount();
  assert.equal(harness.timers.size, 1);

  controller.handleVisibilityChange();
  controller.handleVisibilityChange();
  assert.equal(harness.timers.size, 1);
  assert.deepEqual(harness.ticks, [1]);
});
