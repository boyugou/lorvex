import assert from 'node:assert/strict';
import test from 'node:test';

import { reminderNotificationKey } from '../../../app/src/lib/notifications/taskKey';

test('notification task keys include the exact reminder timestamp', () => {
  assert.notEqual(
    reminderNotificationKey({ id: 'task-1', reminder_at: 'a' }),
    reminderNotificationKey({ id: 'task-1', reminder_at: 'b' }),
  );
});

test('reminderNotificationKey serializes the canonical reminder object shape', () => {
  assert.equal(
    reminderNotificationKey({ id: 'task-1', reminder_at: 'alpha' }),
    'task-1@alpha',
  );
});

// the at-risk dedup Set keyed by (id, due_date, due_time)
// was dropped entirely in favor of the persisted per-day marker. The
// `atRiskNotificationKey` helper and its regression tests went with
// it. If the at-risk dedup layer ever comes back, the test shape from
// the deleted case (preserve null vs "" in field contents) is the
// right pattern to restore.
