import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { formatChangelogActionErrorMessage } from '../../../app/src/components/changelog/changelogError';

const repoRoot = process.cwd();

test('formatChangelogActionErrorMessage appends safe user-facing details', () => {
  assert.equal(
    formatChangelogActionErrorMessage('backend says no', 'Clear failed'),
    'Clear failed: backend says no',
  );
  assert.equal(
    formatChangelogActionErrorMessage('Readable message\n    at stack frame', 'Undo failed'),
    'Undo failed: Readable message',
  );
});

test('formatChangelogActionErrorMessage falls back for empty or internal details', () => {
  assert.equal(formatChangelogActionErrorMessage(undefined, 'Clear failed'), 'Clear failed');
  assert.equal(
    formatChangelogActionErrorMessage(
      JSON.stringify({ kind: 'disk_full', message: 'Local storage is full.', detail: 'no space left on device' }),
      'Undo failed',
    ),
    'Undo failed',
  );
  assert.equal(
    formatChangelogActionErrorMessage('Failed to lock writer connection: PoisonError { .. }', 'Undo failed'),
    'Undo failed',
  );
});

test('formatChangelogActionErrorMessage ignores hostile accessors without invoking them', () => {
  let errorMessageAccessed = 0;
  const error = new Error('original');
  Object.defineProperty(error, 'message', {
    enumerable: true,
    get() {
      errorMessageAccessed += 1;
      return 'getter should not run';
    },
  });

  let recordMessageAccessed = 0;
  const record = Object.defineProperty({}, 'message', {
    enumerable: true,
    get() {
      recordMessageAccessed += 1;
      return 'getter should not run';
    },
  });

  assert.equal(formatChangelogActionErrorMessage(error, 'Clear failed'), 'Clear failed');
  assert.equal(formatChangelogActionErrorMessage(record, 'Undo failed'), 'Undo failed');
  assert.equal(errorMessageAccessed, 0);
  assert.equal(recordMessageAccessed, 0);
});

test('changelog controller uses centralized safe action error formatting', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/changelog/useChangelogController.ts'),
    'utf8',
  );

  assert.match(source, /import \{ formatChangelogActionErrorMessage \} from '\.\/changelogError';/);
  assert.match(
    source,
    /setActionState\(formatChangelogActionErrorMessage\(error, t\('changelog\.clearFailed'\)\), true\);/,
  );
  assert.match(
    source,
    /setActionState\(formatChangelogActionErrorMessage\(error, t\('changelog\.undoFailed'\)\), true\);/,
  );
  assert.doesNotMatch(source, /error instanceof Error \? error\.message : String\(error\)/);
});
