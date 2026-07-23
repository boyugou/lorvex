import assert from 'node:assert/strict';
import test from 'node:test';

import {
  readCurrentTimeValue,
  reconcileCurrentTimeValue,
} from '../../../app/src/lib/time/useCurrentTime.runtime';

test('readCurrentTimeValue formats the current minute in the requested timezone', () => {
  const now = new Date('2026-04-23T12:34:00Z');
  assert.equal(readCurrentTimeValue('America/New_York', now), '08:34');
  assert.equal(readCurrentTimeValue('Asia/Tokyo', now), '21:34');
});

test('reconcileCurrentTimeValue updates immediately when the timezone changes to a different displayed minute', () => {
  const now = new Date('2026-04-23T12:34:00Z');
  const current = readCurrentTimeValue('America/New_York', now);

  const next = reconcileCurrentTimeValue(current, 'Asia/Tokyo', now);

  assert.equal(current, '08:34');
  assert.equal(next, '21:34');
});

test('reconcileCurrentTimeValue preserves identity when the timezone change keeps the same displayed minute', () => {
  const now = new Date('2026-04-23T12:34:00Z');
  const current = readCurrentTimeValue('UTC', now);

  const next = reconcileCurrentTimeValue(current, 'Etc/UTC', now);

  assert.equal(next, current);
});
