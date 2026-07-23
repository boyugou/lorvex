import assert from 'node:assert/strict';
import test from 'node:test';

// Issue #2433 — pin the pure reducer that `useNetworkStatus` uses to
// translate browser `online` / `offline` / `connection.change` events
// into React state. The hook itself needs a DOM to mount, while the
// transition logic lives in the runtime seam for DOM-free coverage.

import {
  reduceNetworkStatus,
  type NetworkStatusState,
} from '../../../app/src/lib/useNetworkStatus.runtime';

test('network status: online event on an already-online state is a no-op (reference equality)', () => {
  const start: NetworkStatusState = { online: true };
  const next = reduceNetworkStatus(start, { type: 'online' });
  // Identity preserved so React skips the render.
  assert.equal(next, start);
  assert.equal(next.online, true);
});

test('network status: offline event on an already-offline state is a no-op', () => {
  const start: NetworkStatusState = { online: false };
  const next = reduceNetworkStatus(start, { type: 'offline' });
  assert.equal(next, start);
  assert.equal(next.online, false);
});

test('network status: online → offline transitions and returns a fresh state object', () => {
  const start: NetworkStatusState = { online: true };
  const next = reduceNetworkStatus(start, { type: 'offline' });
  assert.notEqual(next, start);
  assert.equal(next.online, false);
});

test('network status: offline → online transitions and returns a fresh state object', () => {
  const start: NetworkStatusState = { online: false };
  const next = reduceNetworkStatus(start, { type: 'online' });
  assert.notEqual(next, start);
  assert.equal(next.online, true);
});

test('network status: connection.change sync adopts the observed online value', () => {
  const start: NetworkStatusState = { online: true };
  // `connection.change` carries no payload itself — the listener re-reads
  // navigator.onLine and dispatches `sync` with the current boolean.
  const next = reduceNetworkStatus(start, { type: 'sync', online: false });
  assert.equal(next.online, false);
});

test('network status: sync with the same boolean is a no-op (reference equality)', () => {
  const start: NetworkStatusState = { online: true };
  const next = reduceNetworkStatus(start, { type: 'sync', online: true });
  // Same state object so an unchanged connection.change doesn't cause a
  // needless render.
  assert.equal(next, start);
});

test('network status: multi-step sequence converges to the final browser state', () => {
  let state: NetworkStatusState = { online: true };
  state = reduceNetworkStatus(state, { type: 'offline' });
  assert.equal(state.online, false);
  state = reduceNetworkStatus(state, { type: 'sync', online: false });
  assert.equal(state.online, false);
  state = reduceNetworkStatus(state, { type: 'online' });
  assert.equal(state.online, true);
  // A late-arriving stale `offline` followed by an `online` should still
  // leave the machine consistent.
  state = reduceNetworkStatus(state, { type: 'offline' });
  state = reduceNetworkStatus(state, { type: 'online' });
  assert.equal(state.online, true);
});

test('network status: rapid offline → online → offline toggle lands on final value', () => {
  let state: NetworkStatusState = { online: true };
  state = reduceNetworkStatus(state, { type: 'offline' });
  state = reduceNetworkStatus(state, { type: 'online' });
  state = reduceNetworkStatus(state, { type: 'offline' });
  assert.equal(state.online, false);
});
