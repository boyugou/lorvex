import assert from 'node:assert/strict';
import test from 'node:test';

import {
  daysBetween,
  parseTimeToMinutes,
  timeToMinutes,
} from '../../../app/src/lib/timeUtils';

test('parseTimeToMinutes accepts canonical HH:MM values and trims surrounding whitespace', () => {
  assert.equal(parseTimeToMinutes('00:00'), 0);
  assert.equal(parseTimeToMinutes('09:30'), 570);
  assert.equal(parseTimeToMinutes(' 23:59 '), 1439);
});

test('parseTimeToMinutes rejects malformed or out-of-range values', () => {
  for (const value of [null, undefined, '', '9:30', '24:00', '12:60', 'aa:bb', '09:30:00']) {
    assert.equal(parseTimeToMinutes(value), null);
  }
});

test('timeToMinutes fails closed to zero instead of leaking NaN through layout math', () => {
  assert.equal(timeToMinutes('bad-value'), 0);
  assert.equal(timeToMinutes('25:99'), 0);
});

test('daysBetween returns the UTC day delta for canonical YYYY-MM-DD inputs', () => {
  assert.equal(daysBetween('2026-04-20', '2026-04-22'), 2);
  assert.equal(daysBetween('2026-04-22', '2026-04-20'), -2);
});

test('daysBetween fails closed for malformed or impossible date-only inputs', () => {
  assert.equal(daysBetween('2026-02-30', '2026-03-01'), 0);
  assert.equal(daysBetween('not-a-date', '2026-03-01'), 0);
  assert.equal(daysBetween('2026-03-01', '2026-13-01'), 0);
});
