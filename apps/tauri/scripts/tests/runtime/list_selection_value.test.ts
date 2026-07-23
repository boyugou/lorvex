import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  decodeListSelectionValue,
  encodeListSelectionValue,
} from '../../../app/src/lib/listSelection';

test('list selection encoding preserves exact empty-string list ids', () => {
  const encoded = encodeListSelectionValue('');
  assert.notEqual(
    encoded,
    encodeListSelectionValue(null),
    'empty-string list ids must not collapse to the no-list sentinel',
  );
  assert.equal(
    decodeListSelectionValue(encoded),
    '',
    'empty-string list ids should survive a select round-trip exactly',
  );
});

test('list selection encoding preserves structured-looking list ids and null', () => {
  assert.equal(decodeListSelectionValue(encodeListSelectionValue(null)), null);
  assert.equal(decodeListSelectionValue(encodeListSelectionValue('list-1')), 'list-1');
  assert.equal(
    decodeListSelectionValue(encodeListSelectionValue('{"kind":"none"}')),
    '{"kind":"none"}',
  );
});

test('list selection decoding fails closed for raw and malformed structured values', () => {
  assert.equal(decodeListSelectionValue('legacy-list-id'), null);
  assert.equal(decodeListSelectionValue('{"kind":"none","id":"list-1"}'), null);
  assert.equal(decodeListSelectionValue('{"kind":"list","id":"list-1","extra":true}'), null);
  assert.equal(decodeListSelectionValue('{"kind":"list","id":1}'), null);
});

test('list selection decoder delegates JSON parsing to the shared helper', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/listSelection.ts'),
    'utf8',
  );

  assert.match(source, /from '\.\/security\/jsonParse';/);
  assert.doesNotMatch(source, /JSON\.parse\(/);
});
