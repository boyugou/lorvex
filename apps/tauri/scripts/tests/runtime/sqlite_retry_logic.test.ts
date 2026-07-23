import assert from 'node:assert/strict';
import test from 'node:test';

import {
  computeJitteredBusyRetryDelay,
  isRetryableSqliteBusyMessage,
  SQLITE_BUSY_RETRY_BASE_DELAYS_MS,
  SQLITE_BUSY_RETRY_JITTER_FRACTION,
} from '../../../app/src/lib/recovery/sqliteRetry.logic';

test('sqlite busy retry base delays stay on the documented exponential schedule', () => {
  assert.deepEqual(
    SQLITE_BUSY_RETRY_BASE_DELAYS_MS,
    [0, 50, 100, 200, 400, 800, 1600],
  );
  assert.equal(SQLITE_BUSY_RETRY_JITTER_FRACTION, 0.2);
});

test('computeJitteredBusyRetryDelay keeps zero-delay retries immediate and bounds jitter', () => {
  assert.equal(computeJitteredBusyRetryDelay(0, 0.9), 0);
  assert.equal(computeJitteredBusyRetryDelay(100, 0), 80);
  assert.equal(computeJitteredBusyRetryDelay(100, 0.5), 100);
  assert.equal(computeJitteredBusyRetryDelay(100, 1), 120);
});

test('isRetryableSqliteBusyMessage matches SQLite busy wording regardless of case', () => {
  assert.equal(isRetryableSqliteBusyMessage('database is locked'), true);
  assert.equal(isRetryableSqliteBusyMessage('DATABASE BUSY while writing'), true);
  assert.equal(isRetryableSqliteBusyMessage('encountered SQL_BUSY during mutation'), true);
  assert.equal(isRetryableSqliteBusyMessage('permission denied'), false);
});
