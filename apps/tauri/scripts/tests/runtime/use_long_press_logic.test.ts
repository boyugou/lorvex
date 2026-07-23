import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createLongPressController,
  LONG_PRESS_MS,
  MOVE_THRESHOLD_PX,
  type LongPressTimerApi,
} from '../../../app/src/lib/useLongPress.logic';

test('long press fires once with the original touch point after the hold delay', () => {
  const pressed: Array<{ x: number; y: number }> = [];
  const timers = new Map<number, () => void>();
  let nextHandle = 1;
  const timerApi: LongPressTimerApi = {
    schedule(callback, delayMs) {
      assert.equal(delayMs, LONG_PRESS_MS);
      const handle = nextHandle++;
      timers.set(handle, callback);
      return handle;
    },
    clear(handle) {
      timers.delete(Number(handle));
    },
  };

  const controller = createLongPressController((point) => pressed.push(point), timerApi);
  controller.start({ x: 12, y: 34 });
  assert.equal(controller.hasPending(), true);

  timers.get(1)?.();
  assert.equal(controller.hasPending(), false);
  assert.deepEqual(pressed, [{ x: 12, y: 34 }]);
});

test('long press cancels when movement exceeds the threshold', () => {
  const pressed: Array<{ x: number; y: number }> = [];
  const timers = new Map<number, () => void>();
  const cleared: number[] = [];
  let nextHandle = 1;
  const timerApi: LongPressTimerApi = {
    schedule(callback) {
      const handle = nextHandle++;
      timers.set(handle, callback);
      return handle;
    },
    clear(handle) {
      const numeric = Number(handle);
      cleared.push(numeric);
      timers.delete(numeric);
    },
  };

  const controller = createLongPressController((point) => pressed.push(point), timerApi);
  controller.start({ x: 10, y: 20 });
  controller.move({ x: 10 + MOVE_THRESHOLD_PX + 1, y: 20 });

  assert.equal(controller.hasPending(), false);
  assert.deepEqual(cleared, [1]);
  assert.deepEqual(pressed, []);
});

test('long press keeps the pending timer when movement stays within the threshold', () => {
  const pressed: Array<{ x: number; y: number }> = [];
  const timers = new Map<number, () => void>();
  let nextHandle = 1;
  const timerApi: LongPressTimerApi = {
    schedule(callback) {
      const handle = nextHandle++;
      timers.set(handle, callback);
      return handle;
    },
    clear(handle) {
      timers.delete(Number(handle));
    },
  };

  const controller = createLongPressController((point) => pressed.push(point), timerApi);
  controller.start({ x: 10, y: 20 });
  controller.move({ x: 10 + MOVE_THRESHOLD_PX, y: 20 });

  assert.equal(controller.hasPending(), true);
  timers.get(1)?.();
  assert.deepEqual(pressed, [{ x: 10, y: 20 }]);
});

test('long press start replaces any older pending timer', () => {
  const timers = new Map<number, () => void>();
  const cleared: number[] = [];
  let nextHandle = 1;
  const timerApi: LongPressTimerApi = {
    schedule(callback) {
      const handle = nextHandle++;
      timers.set(handle, callback);
      return handle;
    },
    clear(handle) {
      const numeric = Number(handle);
      cleared.push(numeric);
      timers.delete(numeric);
    },
  };

  const controller = createLongPressController(() => {}, timerApi);
  controller.start({ x: 1, y: 2 });
  controller.start({ x: 3, y: 4 });

  assert.deepEqual(cleared, [1]);
  assert.equal(timers.has(1), false);
  assert.equal(timers.has(2), true);
});

test('long press end and dispose both clear any pending timer', () => {
  const timers = new Map<number, () => void>();
  const cleared: number[] = [];
  let nextHandle = 1;
  const timerApi: LongPressTimerApi = {
    schedule(callback) {
      const handle = nextHandle++;
      timers.set(handle, callback);
      return handle;
    },
    clear(handle) {
      const numeric = Number(handle);
      cleared.push(numeric);
      timers.delete(numeric);
    },
  };

  const controller = createLongPressController(() => {}, timerApi);
  controller.start({ x: 1, y: 2 });
  controller.end();
  controller.start({ x: 3, y: 4 });
  controller.dispose();

  assert.deepEqual(cleared, [1, 2]);
  assert.equal(controller.hasPending(), false);
});
