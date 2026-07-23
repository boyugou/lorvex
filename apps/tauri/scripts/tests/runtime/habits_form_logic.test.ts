import assert from 'node:assert/strict';
import test from 'node:test';

import {
  normalizeHabitTargetCountInput,
  normalizeHabitTargetCountValue,
} from '../../../app/src/components/habits/form.logic';

test('habit target count parser accepts only decimal integer input', () => {
  assert.equal(normalizeHabitTargetCountInput('2'), 2);
  assert.equal(normalizeHabitTargetCountInput(' 12 '), 12);
  assert.equal(normalizeHabitTargetCountInput(''), 1);
  assert.equal(normalizeHabitTargetCountInput('0'), 1);
  assert.equal(normalizeHabitTargetCountInput('51'), 50);

  assert.equal(normalizeHabitTargetCountInput('2x'), 1);
  assert.equal(normalizeHabitTargetCountInput('1.5'), 1);
  assert.equal(normalizeHabitTargetCountInput('1e2'), 1);
});

test('habit target count value normalizer clamps persisted numbers to the UI range', () => {
  assert.equal(normalizeHabitTargetCountValue(3), 3);
  assert.equal(normalizeHabitTargetCountValue(3.9), 3);
  assert.equal(normalizeHabitTargetCountValue(0), 1);
  assert.equal(normalizeHabitTargetCountValue(100), 50);
  assert.equal(normalizeHabitTargetCountValue(Number.NaN), 1);
});
