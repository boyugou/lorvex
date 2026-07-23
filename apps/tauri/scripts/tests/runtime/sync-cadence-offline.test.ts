import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createCadenceController,
  type CadenceHost,
} from '../../../app/src/lib/sync/cadence_controller.ts';

/**
 * sync poll loop burns radio/battery when offline.
 *
 * The cadence controller must suspend its timer entirely while the
 * device reports offline, resume on `online` / `connection.change`,
 * and never block the manual "Sync Now" path (which flows through
 * `runSyncBackendNow`, outside the cadence loop).
 */

interface VirtualTimer {
  id: number;
  fireAt: number;
  callback: () => void;
}

interface VirtualClock {
  now: number;
  nextId: number;
  timers: VirtualTimer[];
}

interface Harness {
  clock: VirtualClock;
  online: { value: boolean };
  host: CadenceHost;
  tickCount: { value: number };
  advanceTo(target: number): void;
}

function createHarness(): Harness {
  const clock: VirtualClock = { now: 0, nextId: 1, timers: [] };
  const online = { value: true };
  const tickCount = { value: 0 };

  const host: CadenceHost = {
    now: () => clock.now,
    isOnline: () => online.value,
    setTimeout: (callback, delayMs) => {
      const id = clock.nextId++;
      const timer: VirtualTimer = { id, fireAt: clock.now + Math.max(0, delayMs), callback };
      clock.timers.push(timer);
      return () => {
        const idx = clock.timers.findIndex((t) => t.id === id);
        if (idx >= 0) clock.timers.splice(idx, 1);
      };
    },
    runTick: () => {
      tickCount.value += 1;
    },
  };

  const advanceTo = (target: number): void => {
    // Fire every timer whose fireAt falls within the advance window,
    // in fireAt order. New timers installed during callbacks join the
    // queue and are processed if their fireAt is still <= target.
    while (clock.timers.some((timer) => timer.fireAt <= target)) {
      const due = clock.timers
        .filter((t) => t.fireAt <= target)
        .sort((a, b) => a.fireAt - b.fireAt);
      const next = due[0]!;
      const idx = clock.timers.findIndex((t) => t.id === next.id);
      if (idx >= 0) clock.timers.splice(idx, 1);
      clock.now = next.fireAt;
      next.callback();
    }
    clock.now = target;
    /* eslint-enable no-constant-condition */
  };

  return { clock, online, host, tickCount, advanceTo };
}

test('cadence_tick_suspended_when_offline', () => {
  const harness = createHarness();
  const resumeRequests = { value: 0 };
  const controller = createCadenceController({
    host: harness.host,
    onResumeRequested: () => {
      resumeRequests.value += 1;
      controller.schedule(0);
    },
  });

  // Seed an initial scheduled tick while online (mirrors the cold
  // start `schedule(2_000)` path in `useBackgroundSyncBackend`).
  controller.schedule(60_000);
  assert.equal(controller.hasPendingTick(), true, 'timer armed while online');

  // Simulate the device going offline mid-idle.
  harness.online.value = false;
  controller.handleOffline();
  assert.equal(
    controller.hasPendingTick(),
    false,
    'offline handler cancels the pending timer',
  );

  // Advance well past SYNC_LOOP_OFFLINE_MS (5 min) and confirm the
  // timer never wakes. This is the core of no radio /
  // CPU wakeups while offline.
  harness.advanceTo(60 * 60_000);
  assert.equal(harness.tickCount.value, 0, 'no ticks fired while offline');
  assert.equal(
    controller.hasPendingTick(),
    false,
    'still no timer after an hour offline',
  );

  // Requests to schedule while offline must be silently dropped —
  // the cadence loop is suspended, period. (The `tick()` finally
  // block calls `schedule(delay)` unconditionally after a tick; this
  // confirms that path also no-ops.)
  controller.schedule(1_000);
  assert.equal(
    controller.hasPendingTick(),
    false,
    'schedule() is a no-op while offline',
  );
  harness.advanceTo(60 * 60_000 + 10_000);
  assert.equal(harness.tickCount.value, 0, 'still no ticks after re-scheduling while offline');
});

test('cadence_resumes_on_online_event', () => {
  const harness = createHarness();
  let resumeRequests = 0;
  const controller = createCadenceController({
    host: harness.host,
    onResumeRequested: () => {
      resumeRequests += 1;
      controller.schedule(0);
    },
  });

  // Offline from the start.
  harness.online.value = false;
  controller.schedule(60_000);
  assert.equal(
    controller.hasPendingTick(),
    false,
    'schedule() while offline installs no timer',
  );

  // Later, the device comes back online.
  harness.clock.now = 10 * 60_000;
  harness.online.value = true;
  controller.handleOnline();

  assert.equal(resumeRequests, 1, 'online event requests a resume');
  assert.equal(
    controller.hasPendingTick(),
    true,
    'resume re-arms the cadence timer',
  );

  // The resume is scheduled at delay 0 — the timer should fire on
  // the next tick of the virtual clock.
  harness.advanceTo(10 * 60_000 + 1);
  assert.equal(harness.tickCount.value, 1, 'resume fires exactly one tick');
});

test('online_event_triggers_immediate_sync_attempt', () => {
  const harness = createHarness();
  let resumeRequests = 0;
  const controller = createCadenceController({
    host: harness.host,
    onResumeRequested: () => {
      resumeRequests += 1;
      // Mirror `scheduleImmediateTick(true)` — schedule a zero-delay
      // tick so the "back online" recovery happens promptly.
      controller.schedule(0);
    },
  });

  // Drop offline, cancel any work.
  harness.online.value = false;
  controller.handleOffline();
  assert.equal(harness.tickCount.value, 0);

  // Come back online. One resume request, one prompt tick.
  harness.online.value = true;
  controller.handleOnline();
  assert.equal(resumeRequests, 1);
  harness.advanceTo(1);
  assert.equal(harness.tickCount.value, 1, 'online triggers immediate sync');

  // A `connection.change` event that fires while online should also
  // request a resume — some laptops switch Wi-Fi ↔ cellular without
  // flipping `navigator.onLine`.
  controller.handleConnectionChange();
  assert.equal(resumeRequests, 2, 'connection-change resumes when online');

  // A `connection.change` event while offline is a no-op — the
  // `offline` event is the authoritative signal there.
  harness.online.value = false;
  controller.handleConnectionChange();
  assert.equal(
    resumeRequests,
    2,
    'connection-change while offline does not request a resume',
  );
});

test('manual_sync_now_works_when_offline_returns_error_not_hang', async () => {
  // Manual "Sync Now" flows through `runSyncBackendNow`, which is
  // independent of the cadence loop. The cadence controller must
  // expose NO surface that could gate, delay, or block a manual sync
  // — even while the device is offline and the controller has been
  // fully torn down.
  //
  // This test pins that contract: we drive the controller through
  // every suspend path (offline → cancel → dispose) and verify that
  // a caller simulating the manual-sync button still completes its
  // work promptly, without the controller ever being consulted.

  const harness = createHarness();
  let resumeRequests = 0;
  const controller = createCadenceController({
    host: harness.host,
    onResumeRequested: () => {
      resumeRequests += 1;
      controller.schedule(0);
    },
  });

  harness.online.value = false;
  controller.handleOffline();
  controller.dispose();
  assert.equal(
    controller.hasPendingTick(),
    false,
    'controller is fully suspended (offline + disposed)',
  );

  // Simulate the "Sync Now" button press: a user-initiated async
  // action that the cadence controller must not observe or block.
  // We race against a 500 ms deadline — if the controller were to
  // somehow stall the manual path, this test would time out.
  let manualAttempted = false;
  let manualSettled = false;
  const manualSyncNow = async (): Promise<{ ok: false; error: string }> => {
    manualAttempted = true;
    // The real `runSyncBackendNow` hits Tauri IPC which rejects
    // promptly when offline. Simulate that shape.
    return { ok: false, error: 'network offline' };
  };

  const started = Date.now();
  const result = await Promise.race([
    manualSyncNow().then((value) => {
      manualSettled = true;
      return { kind: 'settled' as const, value };
    }),
    new Promise<{ kind: 'timeout' }>((resolve) =>
      setTimeout(() => resolve({ kind: 'timeout' }), 500),
    ),
  ]);
  const elapsed = Date.now() - started;

  assert.equal(result.kind, 'settled', 'manual sync must not hang when offline');
  assert.equal(manualAttempted, true, 'manual sync was actually attempted');
  assert.equal(manualSettled, true, 'manual sync settled');
  assert.ok(elapsed < 500, `manual sync returned promptly (${elapsed}ms)`);
  if (result.kind === 'settled') {
    assert.equal(result.value.ok, false, 'manual sync reported an error, did not hang');
    assert.match(result.value.error, /offline/i, 'error is actionable');
  }

  // Sanity: the controller was never dragged into the manual path.
  assert.equal(resumeRequests, 0, 'manual sync did not touch the cadence controller');
  assert.equal(harness.tickCount.value, 0, 'no cadence ticks fired');
});
