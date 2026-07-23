import assert from 'node:assert/strict';
import test from 'node:test';

import { truncateGraphemes } from '../../../app/src/lib/textTruncate';

test('truncateGraphemes keeps multi-codepoint emoji intact when truncating', () => {
  assert.equal(truncateGraphemes('👍🏽abc', 1), '👍🏽…');
  assert.equal(truncateGraphemes('👨‍👩‍👧‍👦 family', 1), '👨‍👩‍👧‍👦…');
});

test('truncateGraphemes can suppress the ellipsis when requested', () => {
  assert.equal(truncateGraphemes('abcdef', 3, false), 'abc');
});

test('truncateGraphemes returns empty string for zero-or-negative limits', () => {
  assert.equal(truncateGraphemes('abcdef', 0), '');
  assert.equal(truncateGraphemes('abcdef', -1), '');
});
