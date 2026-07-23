import assert from 'node:assert/strict';
import test from 'node:test';

import {
  BACKGROUND_SYNC_GENTLE_RESUME_DELAY_MS,
  BACKGROUND_SYNC_INITIAL_DELAY_MS,
  createBackgroundSyncRuntimeController,
} from '../../../app/src/lib/sync/runtime.logic';

function createHarness(options: {
  mobilePlatform?: 'android' | 'unknown';
  now?: number;
  visible?: boolean;
} = {}) {
  const state = {
    now: options.now ?? 0,
    visible: options.visible ?? true,
    scheduled: [] as number[],
  };

  const controller = createBackgroundSyncRuntimeController({
    mobilePlatform: options.mobilePlatform ?? 'unknown',
    host: {
      now: () => state.now,
      isVisible: () => state.visible,
      schedule: (delayMs) => {
        state.scheduled.push(delayMs);
      },
    },
  });

  return { controller, state };
}

test('background sync runtime seeds the cold-start debounce delay', () => {
  const { controller, state } = createHarness();

  controller.scheduleInitialTick();

  assert.deepEqual(state.scheduled, [BACKGROUND_SYNC_INITIAL_DELAY_MS]);
});

test('background sync runtime schedules gentle resume only when focus arrives idle', () => {
  const { controller, state } = createHarness();

  controller.handleWindowFocus(false);
  controller.handleWindowFocus(true);

  assert.deepEqual(state.scheduled, [BACKGROUND_SYNC_GENTLE_RESUME_DELAY_MS]);
});

test('background sync runtime throttles repeated pageshow-triggered immediate syncs', () => {
  const { controller, state } = createHarness({ now: 10_000 });

  controller.handlePageShow(false);
  controller.handlePageShow(false);

  assert.deepEqual(state.scheduled, [0]);
});

test('background sync runtime online-resume requests bypass the normal resume throttle', () => {
  const { controller, state } = createHarness({ now: 5_000 });

  controller.handlePageShow(false);
  controller.handleCadenceResumeRequested(false);

  assert.deepEqual(state.scheduled, [0, 0]);
});

test('background sync runtime forces an immediate Android resume after a stale background gap', () => {
  const { controller, state } = createHarness({
    mobilePlatform: 'android',
    now: 1,
    visible: true,
  });

  controller.recordTickCompleted();
  state.now = 6 * 60_000 + 1;
  controller.handleVisibilityChange(false);

  assert.deepEqual(state.scheduled, [0]);
});

test('background sync runtime ignores hidden visibility changes and gently resumes visible desktop tabs', () => {
  const { controller, state } = createHarness({
    mobilePlatform: 'unknown',
    visible: false,
  });

  controller.handleVisibilityChange(false);
  assert.deepEqual(state.scheduled, []);

  state.visible = true;
  controller.handleVisibilityChange(false);
  assert.deepEqual(state.scheduled, [BACKGROUND_SYNC_GENTLE_RESUME_DELAY_MS]);
});

test('background sync runtime consumes immediate tick state exactly once', () => {
  const { controller } = createHarness({ now: 2_000 });

  controller.handleResume(true);

  assert.equal(controller.consumeNextDelay(60_000), 0);
  assert.equal(controller.consumeNextDelay(60_000), 60_000);
});

test('background sync runtime override delay clears any pending immediate resume request', () => {
  const { controller } = createHarness({ now: 2_000 });

  controller.handleResume(true);

  assert.equal(controller.consumeOverrideDelay(30_000, 5_000), 30_000);
  assert.equal(controller.consumeNextDelay(60_000), 60_000);
});

test('background sync runtime repeated-failure warning triggers only on the third consecutive error and resets after success', () => {
  const { controller } = createHarness();

  assert.equal(controller.recordTickError(), false);
  assert.equal(controller.recordTickError(), false);
  assert.equal(controller.recordTickError(), true);
  assert.equal(controller.recordTickError(), false);

  controller.resetConsecutiveErrors();

  assert.equal(controller.recordTickError(), false);
});
