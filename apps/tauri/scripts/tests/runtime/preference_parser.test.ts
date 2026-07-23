import assert from 'node:assert/strict';
import test from 'node:test';

import {
  parseBooleanPreference,
  parsePreferenceJson,
  parseStringArrayPreference,
  parseStringPreference,
  tryParsePreferenceJson,
} from '../../../app/src/lib/preferences/parser';
import {
  parseTimePreference,
  parseWeekdayPreference,
} from '../../../app/src/lib/notifications/preferences';

test('tryParsePreferenceJson preserves invalid-json detection while parsePreferenceJson remains null-safe', () => {
  assert.deepEqual(tryParsePreferenceJson(null), { ok: true, value: null });
  assert.deepEqual(tryParsePreferenceJson('null'), { ok: true, value: null });
  assert.deepEqual(tryParsePreferenceJson('false'), { ok: true, value: false });
  assert.deepEqual(tryParsePreferenceJson('"hello"'), { ok: true, value: 'hello' });
  assert.deepEqual(tryParsePreferenceJson('not json'), { ok: false });

  assert.equal(parsePreferenceJson(null), null);
  assert.equal(parsePreferenceJson('not json'), null);
});

test('shared preference parsers honor fallbacks and reject malformed values', () => {
  assert.equal(parseBooleanPreference(null, true), true);
  assert.equal(parseBooleanPreference('false', true), false);
  assert.equal(parseBooleanPreference('"false"', true), true);

  assert.equal(parseStringPreference(null, 'fallback'), 'fallback');
  assert.equal(parseStringPreference('"Lorvex"', 'fallback'), 'Lorvex');
  assert.equal(parseStringPreference('false', 'fallback'), 'fallback');

  assert.deepEqual(parseStringArrayPreference(null), []);
  assert.deepEqual(parseStringArrayPreference('["alpha", "beta"]'), ['alpha', 'beta']);
  assert.deepEqual(parseStringArrayPreference('["alpha", 1, "beta", null]'), []);
  assert.deepEqual(parseStringArrayPreference('"not-an-array"'), []);
});

test('notification preference parsers normalize valid values and reject malformed ones', () => {
  assert.equal(parseTimePreference('" 09:30 "', '08:00'), '09:30');
  assert.equal(parseTimePreference('"25:61"', '08:00'), '08:00');

  assert.equal(parseWeekdayPreference('" Friday "', 'monday'), 'friday');
  assert.equal(parseWeekdayPreference('"Funday"', 'monday'), 'monday');
});
