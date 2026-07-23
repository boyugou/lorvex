import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import { QK } from '../../../app/src/lib/query/queryKeys';
import { STALE_DEFAULT } from '../../../app/src/lib/query/timing';
import {
  assertValidPreferenceWriteValue,
  buildPreferenceQueryConfig,
  parseBool,
  parseIntegerInRange,
  parseJson,
  parseJsonValidated,
  parseString,
} from '../../../app/src/lib/query/usePreference.logic';

test('buildPreferenceQueryConfig uses the canonical preference key head and default stale time', () => {
  assert.deepEqual(
    buildPreferenceQueryConfig({ key: 'quiet_hours_start' }),
    {
      queryKey: [QK.preference, 'quiet_hours_start'],
      staleTime: STALE_DEFAULT,
    },
  );
  assert.deepEqual(
    buildPreferenceQueryConfig({
      key: 'focus_break_minutes',
      staleTime: 1234,
      enabled: false,
    }),
    {
      queryKey: [QK.preference, 'focus_break_minutes'],
      staleTime: 1234,
      enabled: false,
    },
  );
});

test('assertValidPreferenceWriteValue rejects non-finite numeric writes and accepts finite or non-numeric values', () => {
  assert.doesNotThrow(() => assertValidPreferenceWriteValue('x', 0));
  assert.doesNotThrow(() => assertValidPreferenceWriteValue('x', -1));
  assert.doesNotThrow(() => assertValidPreferenceWriteValue('x', 'hello'));
  assert.throws(
    () => assertValidPreferenceWriteValue('x', Number.NaN),
    /rejected non-finite number/,
  );
  assert.throws(
    () => assertValidPreferenceWriteValue('x', Number.POSITIVE_INFINITY),
    /rejected non-finite number/,
  );
});

test('usePreference parser helpers keep their runtime contracts fail-closed', () => {
  assert.equal(parseBool(true)(null), true);
  assert.equal(parseBool(false)('true'), true);
  assert.equal(parseBool(true)('"oops"'), true);

  assert.equal(parseJson(5)('5'), 5);
  assert.equal(parseJson(5)('"5"'), 5);
  assert.deepEqual(parseJson<string[]>([])('["a", "b"]'), []);
  assert.deepEqual(parseJson<string[]>([])('{"a":1}'), []);
  assert.deepEqual(parseJson({ ok: false })('{"ok": true}'), { ok: false });
  assert.deepEqual(parseJson({ ok: false })('[{"ok": true}]'), { ok: false });

  assert.equal(parseIntegerInRange(7, 0, 10)('8'), 8);
  assert.equal(parseIntegerInRange(7, 0, 10)('8.5'), 7);
  assert.equal(parseIntegerInRange(7, 0, 10)('-1'), 7);
  assert.equal(parseIntegerInRange(7, 0, 10)('11'), 7);
  assert.equal(parseIntegerInRange(7, 0, 20)('1e1'), 7);
  assert.equal(parseIntegerInRange(7, -10, 10)('-3'), -3);

  const parseValidated = parseJsonValidated<{ id: string }>(
    { id: 'fallback' },
    (value): value is { id: string } =>
      typeof value === 'object' &&
      value !== null &&
      'id' in value &&
      typeof (value as { id?: unknown }).id === 'string',
  );
  assert.deepEqual(parseValidated('{"id":"abc"}'), { id: 'abc' });
  assert.deepEqual(parseValidated('{"id":1}'), { id: 'fallback' });

  const parseCanonicalString = parseString('fallback');
  assert.equal(parseCanonicalString('"hello"'), 'hello');
  assert.equal(parseCanonicalString('raw-string'), 'fallback');
  assert.equal(parseCanonicalString('null'), 'fallback');
  assert.equal(parseCanonicalString('42'), 'fallback');
});

test('parseIntegerInRange keeps integer scalar parsing out of JSON.parse', () => {
  const source = readFileSync('app/src/lib/query/usePreference.logic.ts', 'utf8');
  const parserBody = source.match(/export function parseIntegerInRange[\s\S]*?\n}\n\n\/\*\* Parse a JSON preference/);
  assert.ok(parserBody, 'parseIntegerInRange must remain a local parser');
  assert.doesNotMatch(parserBody[0], /JSON\.parse\(raw\)/);
});

test('usePreference JSON parser helpers delegate raw parsing to the shared helper', () => {
  const source = readFileSync('app/src/lib/query/usePreference.logic.ts', 'utf8');
  assert.match(source, /import \{ tryParseJson \} from '\.\.\/security\/jsonParse';/);
  assert.doesNotMatch(source, /JSON\.parse\(/);
});
