import assert from 'node:assert/strict';
import test from 'node:test';

import { msUntilNextMidnightInTimezone } from '../../../app/src/lib/dayContextMath';
import { createMidnightRolloverController } from '../../../app/src/lib/midnightRolloverController';

test('msUntilNextMidnightInTimezone returns the remaining wall-clock time until midnight', () => {
  const now = new Date('2026-04-20T06:34:45Z');
  const remainingMs = msUntilNextMidnightInTimezone('America/Los_Angeles', now);
  assert.ok(remainingMs >= 1_515_000 && remainingMs < 1_516_000, `expected ~1_515_000ms, got ${remainingMs}`);
});

test('msUntilNextMidnightInTimezone returns one second when local midnight is one second away', () => {
  const now = new Date('2026-04-20T06:59:59Z');
  const remainingMs = msUntilNextMidnightInTimezone('America/Los_Angeles', now);
  assert.ok(remainingMs >= 1_000 && remainingMs < 2_000, `expected ~1_000ms, got ${remainingMs}`);
});

test('msUntilNextMidnightInTimezone honors spring-forward days with a 23-hour local day', () => {
  const now = new Date('2026-03-08T05:30:00Z');
  const remainingMs = msUntilNextMidnightInTimezone('America/New_York', now);
  assert.ok(remainingMs >= 81_000_000 && remainingMs < 81_001_000, `expected ~81_000_000ms, got ${remainingMs}`);
});

test('msUntilNextMidnightInTimezone honors fall-back days with a 25-hour local day', () => {
  const now = new Date('2026-11-01T04:30:00Z');
  const remainingMs = msUntilNextMidnightInTimezone('America/New_York', now);
  assert.ok(remainingMs >= 88_200_000 && remainingMs < 88_201_000, `expected ~88_200_000ms, got ${remainingMs}`);
});

test('midnight rollover controller fires on timer expiry and rearms the next cycle', () => {
  const timers: Array<{ callback: () => void; delayMs: number; cancelled: boolean }> = [];
  const observedYmds = ['2026-04-20', '2026-04-21', '2026-04-21'];
  let ymdIndex = 0;
  let rollovers = 0;

  const controller = createMidnightRolloverController({
    getCurrentYmd: () => observedYmds[Math.min(ymdIndex, observedYmds.length - 1)],
    getDelayMs: () => 5_000 + timers.length,
    onRollover: () => {
      rollovers += 1;
      ymdIndex += 1;
    },
    setTimeout: (callback, delayMs) => {
      const timer = { callback, delayMs, cancelled: false };
      timers.push(timer);
      return () => { timer.cancelled = true; };
    },
  });

  controller.mount();
  assert.equal(controller.hasActiveTimer(), true);
  assert.equal(timers.length, 1);
  assert.equal(timers[0].delayMs, 5_000);

  timers[0].callback();
  assert.equal(rollovers, 1);
  assert.equal(timers[0].cancelled, true);
  assert.equal(timers.length, 2);
  assert.equal(timers[1].delayMs, 5_001);
});

test('midnight rollover controller catches sleep-across-midnight on wake and re-arms once', () => {
  const timers: Array<{ callback: () => void; delayMs: number; cancelled: boolean }> = [];
  let currentYmd = '2026-04-20';
  let rollovers = 0;

  const controller = createMidnightRolloverController({
    getCurrentYmd: () => currentYmd,
    getDelayMs: () => 30_000,
    onRollover: () => { rollovers += 1; },
    setTimeout: (callback, delayMs) => {
      const timer = { callback, delayMs, cancelled: false };
      timers.push(timer);
      return () => { timer.cancelled = true; };
    },
  });

  controller.mount();
  controller.handleWake();
  assert.equal(rollovers, 0);
  assert.equal(timers.length, 1);

  currentYmd = '2026-04-21';
  controller.handleWake();
  assert.equal(rollovers, 1);
  assert.equal(timers.length, 2);
  assert.equal(timers[0].cancelled, true);
});

test('midnight rollover controller dispose clears the pending timer and suppresses late callbacks', () => {
  const timers: Array<{ callback: () => void; cancelled: boolean }> = [];
  let rollovers = 0;

  const controller = createMidnightRolloverController({
    getCurrentYmd: () => '2026-04-20',
    getDelayMs: () => 10_000,
    onRollover: () => { rollovers += 1; },
    setTimeout: (callback) => {
      const timer = { callback, cancelled: false };
      timers.push(timer);
      return () => { timer.cancelled = true; };
    },
  });

  controller.mount();
  controller.dispose();
  assert.equal(controller.hasActiveTimer(), false);
  assert.equal(timers[0].cancelled, true);

  timers[0].callback();
  assert.equal(rollovers, 0);
  assert.equal(timers.length, 1);
});
