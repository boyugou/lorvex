import assert from 'node:assert/strict';
import test from 'node:test';

import {
  parseJsonValueOrNull,
  tryParseJson,
  tryParseOptionalJson,
} from '../../../app/src/lib/security/jsonParse';

test('tryParseJson distinguishes valid JSON from malformed payloads', () => {
  assert.deepEqual(tryParseJson('{"ok":true}'), { ok: true, value: { ok: true } });

  const malformed = tryParseJson('{oops');
  assert.equal(malformed.ok, false);
  assert.ok(malformed.error instanceof Error);
});

test('parseJsonValueOrNull parses canonical JSON and fails closed for malformed payloads', () => {
  assert.equal(parseJsonValueOrNull('"dark"'), 'dark');
  assert.equal(parseJsonValueOrNull('dark'), null);
});

test('tryParseOptionalJson validates optional payloads and surfaces guard failures', () => {
  const valid = tryParseOptionalJson('{"id":"cmd-1"}', (value): value is { id: string } => {
    return typeof value === 'object'
      && value !== null
      && typeof (value as { id?: unknown }).id === 'string';
  });
  assert.deepEqual(valid, { value: { id: 'cmd-1' }, error: null });

  const invalidShape = tryParseOptionalJson('{"id":123}', (value): value is { id: string } => {
    return typeof value === 'object'
      && value !== null
      && typeof (value as { id?: unknown }).id === 'string';
  });
  assert.equal(invalidShape.value, null);
  assert.ok(invalidShape.error instanceof SyntaxError);

  assert.deepEqual(tryParseOptionalJson(null), { value: null, error: null });
});
