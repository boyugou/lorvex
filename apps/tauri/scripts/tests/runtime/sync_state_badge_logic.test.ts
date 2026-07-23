import test from 'node:test';
import assert from 'node:assert/strict';

import {
  buildSyncStateBadge,
  buildSyncStatusLine,
} from '../../../app/src/components/settings/controller/assistant/sync/presentation';

function t(key: string): string {
  return key;
}

test('buildSyncStateBadge stays pending when pending inbox still has entries', () => {
  const badge = buildSyncStateBadge(
    {
      failed_count: 0,
      pending_count: 0,
      pending_inbox_count: 2,
      reseed_required: false,
      retrying_count: 0,
    },
    t,
  );

  assert.deepEqual(badge, {
    label: 'settings.syncPending',
    className: 'bg-accent/15 text-accent',
  });
});

test('buildSyncStateBadge reports up to date only when outbox and pending inbox are empty', () => {
  const badge = buildSyncStateBadge(
    {
      failed_count: 0,
      pending_count: 0,
      pending_inbox_count: 0,
      reseed_required: false,
      retrying_count: 0,
    },
    t,
  );

  assert.deepEqual(badge, {
    label: 'settings.syncUpToDate',
    className: 'chip-success',
  });
});

test('buildSyncStateBadge reports reseed-required state ahead of generic up-to-date status', () => {
  const badge = buildSyncStateBadge(
    {
      failed_count: 0,
      pending_count: 0,
      pending_inbox_count: 0,
      reseed_required: true,
      retrying_count: 0,
    },
    t,
  );

  assert.deepEqual(badge, {
    label: 'settings.syncReseedRequired',
    className: 'chip-danger',
  });
});

test('buildSyncStatusLine surfaces reseed-required as an assertive steady-state error', () => {
  const statusLine = buildSyncStatusLine(
    {
      hasAvailableSyncBackends: true,
      syncEnabled: true,
      syncRunning: false,
      seedSyncRunning: false,
      syncLastRunAt: '2026-04-22T00:00:00Z',
      syncStatus: {
        failed_count: 0,
        pending_count: 0,
        pending_inbox_count: 0,
        reseed_required: true,
        retrying_count: 0,
        last_error: null,
      },
    },
    t,
  );

  assert.deepEqual(statusLine, {
    text: 'settings.syncReseedRequired',
    className: 'text-danger',
    ariaLive: 'assertive',
  });
});
