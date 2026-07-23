import assert from 'node:assert/strict';
import test from 'node:test';

import {
  formatTimeDisplay,
  parseCanonicalClockTime,
} from '../../../app/src/components/settings/SettingsPrimitives.logic';

test('settings time parser accepts only canonical HH:MM values', () => {
  assert.deepEqual(parseCanonicalClockTime('09:30'), { hour: 9, minute: 30 });
  assert.deepEqual(parseCanonicalClockTime('23:59'), { hour: 23, minute: 59 });

  assert.equal(parseCanonicalClockTime('9:30'), null);
  assert.equal(parseCanonicalClockTime('09:30x'), null);
  assert.equal(parseCanonicalClockTime('24:00'), null);
  assert.equal(parseCanonicalClockTime('12:60'), null);
});

test('settings time display returns malformed values unchanged', () => {
  assert.equal(formatTimeDisplay('9:30', 'en-US'), '9:30');
  assert.equal(formatTimeDisplay('09:30x', 'en-US'), '09:30x');
});
