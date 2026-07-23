import assert from 'node:assert/strict';
import test from 'node:test';

import { isAllowedLinkUrl } from '../../../app/src/lib/security/urlSafety';

test('isAllowedLinkUrl allows only the explicit protocol allowlist', () => {
  assert.equal(isAllowedLinkUrl('https://example.com'), true);
  assert.equal(isAllowedLinkUrl('HTTP://example.com'), true);
  assert.equal(isAllowedLinkUrl('mailto:test@example.com'), true);
  assert.equal(isAllowedLinkUrl('tel:+1234567'), true);
});

test('isAllowedLinkUrl rejects dangerous, relative, or malformed URLs', () => {
  for (const value of [
    'javascript:alert(1)',
    'data:text/html,boom',
    'file:///tmp/test.txt',
    '/relative/path',
    'not a url',
    '',
    '   ',
    null,
    undefined,
  ]) {
    assert.equal(isAllowedLinkUrl(value), false);
  }
});
