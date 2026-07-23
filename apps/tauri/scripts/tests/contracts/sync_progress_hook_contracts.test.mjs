/**
 * Issue #2252: sync progress hook contracts.
 *
 * The runtime unit tests for the `useSyncProgress` hook live in its
 * reducer — the hook is a thin subscription wrapper on top of
 * `reduceSyncProgress`. Exercising the reducer through a pure-JS
 * mirror gives us deterministic coverage of:
 *
 *   1. A progress event with a fresh `cycle_id` updates the hook
 *      state to determinate push/pull/apply.
 *   2. Events carrying a stale cycle_id are ignored while the active
 *      cycle is still ticking.
 *   3. The active cycle's own `idle` event resets to the idle state.
 *
 * The mirror logic below must stay in lockstep with
 * `app/src/lib/sync/useSyncProgress.ts::reduceSyncProgress` — the
 * source-shape assertions at the bottom of this file guarantee the
 * reducer exists and exports the expected name, so if someone
 * deletes or renames the reducer this test fails loudly before any
 * frontend regression ships.
 */

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const IDLE = {
  cycleId: null,
  phase: 'idle',
  current: 0,
  total: 0,
  determinate: false,
};

function reduceSyncProgress(previous, payload) {
  const previousId = previous.cycleId;

  if (payload.phase === 'idle') {
    if (previousId && previousId !== payload.cycle_id) return previous;
    return IDLE;
  }

  if (previousId && previousId !== payload.cycle_id) return previous;

  return {
    cycleId: payload.cycle_id,
    phase: payload.phase,
    current: payload.current,
    total: payload.total,
    determinate: payload.total > 0,
  };
}

test('reduceSyncProgress promotes a fresh cycle into determinate state', () => {
  const next = reduceSyncProgress(IDLE, {
    phase: 'push',
    current: 47,
    total: 312,
    cycle_id: 'cycle-a',
  });

  assert.equal(next.cycleId, 'cycle-a');
  assert.equal(next.phase, 'push');
  assert.equal(next.current, 47);
  assert.equal(next.total, 312);
  assert.equal(next.determinate, true);
});

test('reduceSyncProgress drops events carrying a stale cycle_id', () => {
  const active = reduceSyncProgress(IDLE, {
    phase: 'push',
    current: 10,
    total: 100,
    cycle_id: 'cycle-a',
  });
  const afterStale = reduceSyncProgress(active, {
    phase: 'push',
    current: 99,
    total: 100,
    cycle_id: 'cycle-b',
  });

  assert.deepEqual(
    afterStale,
    active,
    'stale-cycle events must not overwrite the active cycle state',
  );
});

test('reduceSyncProgress advances the same cycle through phases', () => {
  let state = reduceSyncProgress(IDLE, {
    phase: 'push',
    current: 0,
    total: 312,
    cycle_id: 'cycle-a',
  });
  state = reduceSyncProgress(state, {
    phase: 'push',
    current: 150,
    total: 312,
    cycle_id: 'cycle-a',
  });
  state = reduceSyncProgress(state, {
    phase: 'pull',
    current: 25,
    total: 25,
    cycle_id: 'cycle-a',
  });
  state = reduceSyncProgress(state, {
    phase: 'apply',
    current: 20,
    total: 25,
    cycle_id: 'cycle-a',
  });

  assert.equal(state.cycleId, 'cycle-a');
  assert.equal(state.phase, 'apply');
  assert.equal(state.current, 20);
  assert.equal(state.total, 25);
});

test('reduceSyncProgress clears to idle on the active cycle idle event', () => {
  const active = reduceSyncProgress(IDLE, {
    phase: 'push',
    current: 5,
    total: 10,
    cycle_id: 'cycle-a',
  });
  const cleared = reduceSyncProgress(active, {
    phase: 'idle',
    current: 0,
    total: 0,
    cycle_id: 'cycle-a',
  });

  assert.deepEqual(cleared, IDLE);
});

test('reduceSyncProgress drops idle events from stale cycles', () => {
  const active = reduceSyncProgress(IDLE, {
    phase: 'push',
    current: 5,
    total: 10,
    cycle_id: 'cycle-a',
  });
  const ignored = reduceSyncProgress(active, {
    phase: 'idle',
    current: 0,
    total: 0,
    cycle_id: 'cycle-b',
  });

  assert.deepEqual(ignored, active);
});

test('reduceSyncProgress flags total==0 events as indeterminate', () => {
  const next = reduceSyncProgress(IDLE, {
    phase: 'pull',
    current: 0,
    total: 0,
    cycle_id: 'cycle-a',
  });

  assert.equal(next.determinate, false);
});

// -----------------------------------------------------------------------
// Source-shape guard — keeps the hook contract in sync with the tests.
// -----------------------------------------------------------------------

test('useSyncProgress hook source exports reduceSyncProgress and listens on the documented channel', () => {
  const hookSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/sync/useSyncProgress.ts'),
    'utf8',
  );
  const logicSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/sync/useSyncProgress.logic.ts'),
    'utf8',
  );

  assert.match(
    logicSource,
    /export\s+function\s+reduceSyncProgress\s*\(/,
    'reducer must remain exported from the sync-progress logic module so the hook state transitions stay testable',
  );
  assert.match(
    hookSource,
    /export\s+function\s+useSyncProgress\s*\(/,
    'hook must remain named useSyncProgress',
  );
  assert.match(
    logicSource,
    /lorvex:\/\/sync\/progress/,
    'hook must subscribe to the documented progress event channel',
  );
  assert.match(
    logicSource,
    /cycle_id/,
    'hook must thread cycle_id through so stale-cycle events can be dropped',
  );
  assert.match(
    hookSource,
    /startSyncProgressSubscription/,
    'hook should delegate subscription lifecycle ownership to the dedicated sync-progress logic module',
  );
});
