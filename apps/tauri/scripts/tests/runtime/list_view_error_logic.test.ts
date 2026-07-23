import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { isListNotFoundError } from '../../../app/src/components/list-view/listError';

test('list not-found detection formats errors without invoking message accessors', () => {
  assert.equal(isListNotFoundError(new Error('list not found')), true);
  assert.equal(isListNotFoundError('database not found'), true);
  assert.equal(isListNotFoundError(new Error('network unavailable')), false);

  let accessed = 0;
  const error = new Error('original');
  Object.defineProperty(error, 'message', {
    enumerable: true,
    get() {
      accessed += 1;
      return 'not found';
    },
  });

  assert.equal(isListNotFoundError(error), false);
  assert.equal(accessed, 0);
});

test('list view controller delegates not-found error matching to the safe helper', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/list-view/useListViewController.ts'),
    'utf8',
  );

  assert.equal(source.match(/isListNotFoundError\(error\)/g)?.length, 2);
  assert.doesNotMatch(source, /\berror\.message\b/);
  assert.doesNotMatch(source, /\btoIpcErrorMessage\b/);
  assert.doesNotMatch(source, /\bString\(error\)/);
  assert.doesNotMatch(source, /\b(?:includes|match|test|search)\s*\([^)]*not found/iu);
  assert.doesNotMatch(source, /\/not found\//i);
});
