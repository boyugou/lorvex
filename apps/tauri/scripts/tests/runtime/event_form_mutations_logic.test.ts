import assert from 'node:assert/strict';
import test from 'node:test';

import { normalizeRecurrenceIntervalInput } from '../../../app/src/components/calendar/event-form/mutations.logic';

test('event form recurrence interval parser accepts only decimal integer input', () => {
  assert.equal(normalizeRecurrenceIntervalInput('2'), 2);
  assert.equal(normalizeRecurrenceIntervalInput(' 12 '), 12);
  assert.equal(normalizeRecurrenceIntervalInput(''), 1);
  assert.equal(normalizeRecurrenceIntervalInput('0'), 1);
  assert.equal(normalizeRecurrenceIntervalInput('100'), 99);
  assert.equal(normalizeRecurrenceIntervalInput('365'), 99);

  assert.equal(normalizeRecurrenceIntervalInput('2x'), 1);
  assert.equal(normalizeRecurrenceIntervalInput('1.5'), 1);
  assert.equal(normalizeRecurrenceIntervalInput('1e2'), 1);
});
