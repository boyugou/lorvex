import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import {
  estimatedMinutesDraftChanged,
  estimatedMinutesDraftValue,
  MAX_ESTIMATED_MINUTES,
  parseEstimatedMinutesInput,
  resolveEstimatedMinutesDraftState,
} from '../../../app/src/lib/estimatedMinutes';

test('parseEstimatedMinutesInput avoids prefix-truncating integer parsers', () => {
  const source = readFileSync('app/src/lib/estimatedMinutes.ts', 'utf8');
  assert.doesNotMatch(source, /Number\.parseInt|parseInt/);
});

test('parseEstimatedMinutesInput accepts positive decimal minute counts within range', () => {
  assert.equal(parseEstimatedMinutesInput('1'), 1);
  assert.equal(parseEstimatedMinutesInput(' 045 '), 45);
  assert.equal(parseEstimatedMinutesInput(String(MAX_ESTIMATED_MINUTES)), MAX_ESTIMATED_MINUTES);
});

test('parseEstimatedMinutesInput rejects empty, zero, negative, and out-of-range values', () => {
  for (const value of ['', '0', '-1', '1441', '999999']) {
    assert.equal(parseEstimatedMinutesInput(value), null);
  }
});

test('parseEstimatedMinutesInput rejects non-decimal numeric notations', () => {
  for (const value of ['1.5', '1e2', '0x10', '+5', '10m']) {
    assert.equal(parseEstimatedMinutesInput(value), null);
  }
});

test('resolveEstimatedMinutesDraftState drives invalid versus active state from the shared parser', () => {
  assert.deepEqual(resolveEstimatedMinutesDraftState('45'), {
    parsed: 45,
    invalid: false,
    hasValidValue: true,
  });
  assert.deepEqual(resolveEstimatedMinutesDraftState('1e2'), {
    parsed: null,
    invalid: true,
    hasValidValue: false,
  });
  assert.deepEqual(resolveEstimatedMinutesDraftState('   '), {
    parsed: null,
    invalid: false,
    hasValidValue: false,
  });
});

test('estimatedMinutesDraftValue serializes nullable minute values for editor state resets', () => {
  assert.equal(estimatedMinutesDraftValue(45), '45');
  assert.equal(estimatedMinutesDraftValue(null), '');
});

test('estimatedMinutesDraftChanged only flags real metadata changes', () => {
  assert.equal(estimatedMinutesDraftChanged(null, null), false);
  assert.equal(estimatedMinutesDraftChanged(45, 45), false);
  assert.equal(estimatedMinutesDraftChanged(null, 45), true);
  assert.equal(estimatedMinutesDraftChanged(45, null), true);
});
